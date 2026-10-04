import Foundation

/// Binary-image primitives for the sorter. Masks are row-major `[UInt8]` of 0/1.
enum Raster {
    /// Morphological opening with the 3×3 cross: `iterations` erosions, then as many
    /// dilations. Pixels outside the image never constrain the result.
    static func open(_ mask: [UInt8], width w: Int, height h: Int, iterations: Int) -> [UInt8] {
        var current = mask
        for _ in 0..<iterations { current = cross(current, w, h, erode: true) }
        for _ in 0..<iterations { current = cross(current, w, h, erode: false) }
        return current
    }

    private static func cross(_ m: [UInt8], _ w: Int, _ h: Int, erode: Bool) -> [UInt8] {
        var out = m
        m.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    for x in 0..<w {
                        let i = y * w + x
                        var v = src[i]
                        if erode {
                            if x > 0 { v &= src[i - 1] }
                            if x < w - 1 { v &= src[i + 1] }
                            if y > 0 { v &= src[i - w] }
                            if y < h - 1 { v &= src[i + w] }
                        } else {
                            if x > 0 { v |= src[i - 1] }
                            if x < w - 1 { v |= src[i + 1] }
                            if y > 0 { v |= src[i - w] }
                            if y < h - 1 { v |= src[i + w] }
                        }
                        dst[i] = v
                    }
                }
            }
        }
        return out
    }

    /// Dilation with a `size × size` square (odd `size`).
    static func dilate(_ mask: [UInt8], width w: Int, height h: Int, size: Int) -> [UInt8] {
        let r = size / 2
        var rows = [UInt8](repeating: 0, count: w * h)
        var prefix = [Int](repeating: 0, count: max(w, h) + 1)
        for y in 0..<h {
            for x in 0..<w { prefix[x + 1] = prefix[x] + Int(mask[y * w + x]) }
            for x in 0..<w where prefix[min(w, x + r + 1)] - prefix[max(0, x - r)] > 0 { rows[y * w + x] = 1 }
        }
        var out = [UInt8](repeating: 0, count: w * h)
        for x in 0..<w {
            for y in 0..<h { prefix[y + 1] = prefix[y] + Int(rows[y * w + x]) }
            for y in 0..<h where prefix[min(h, y + r + 1)] - prefix[max(0, y - r)] > 0 { out[y * w + x] = 1 }
        }
        return out
    }

    struct Components {
        /// 0 for background, 1... for components in raster order of their first pixel.
        var labels: [Int32]
        /// Indexed by label; entry 0 (background) is unused.
        var area: [Int]
        var minX: [Int], minY: [Int], maxX: [Int], maxY: [Int]

        var count: Int { area.count }

        /// Touching the frame and running a long way along it: the sheet's surroundings (table,
        /// or white paper under a dark sheet), never a bean.
        func frameHugging(width w: Int, height h: Int) -> [Bool] {
            (0..<count).map { i in
                guard i > 0 else { return false }
                let onEdge = minX[i] == 0 || minY[i] == 0 || maxX[i] == w - 1 || maxY[i] == h - 1
                let long = Double(maxX[i] - minX[i] + 1) > 0.25 * Double(w) || Double(maxY[i] - minY[i] + 1) > 0.25 * Double(h)
                return onEdge && long
            }
        }

        func onEdge(_ i: Int, width w: Int, height h: Int) -> Bool {
            minX[i] == 0 || minY[i] == 0 || maxX[i] == w - 1 || maxY[i] == h - 1
        }
    }

    /// Connected components of the non-zero pixels, 4- or 8-connected.
    static func components(_ mask: [UInt8], width w: Int, height h: Int, eightConnected: Bool) -> Components {
        var labels = [Int32](repeating: 0, count: w * h)
        var area = [0], minX = [0], minY = [0], maxX = [0], maxY = [0]
        var stack: [Int32] = []
        for start in 0..<(w * h) where mask[start] != 0 && labels[start] == 0 {
            let label = Int32(area.count)
            var n = 0
            var x0 = w, y0 = h, x1 = -1, y1 = -1
            labels[start] = label
            stack.append(Int32(start))
            while let top = stack.popLast() {
                let i = Int(top)
                let x = i % w, y = i / w
                n += 1
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                for dy in -1...1 {
                    let yy = y + dy
                    guard yy >= 0, yy < h else { continue }
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        if !eightConnected && dx != 0 && dy != 0 { continue }
                        let xx = x + dx
                        guard xx >= 0, xx < w else { continue }
                        let j = yy * w + xx
                        if mask[j] != 0 && labels[j] == 0 {
                            labels[j] = label
                            stack.append(Int32(j))
                        }
                    }
                }
            }
            area.append(n); minX.append(x0); minY.append(y0); maxX.append(x1); maxY.append(y1)
        }
        return Components(labels: labels, area: area, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// For every pixel, the squared Euclidean distance to the nearest site and that site's
    /// pixel index (-1 when the image has no site). Exact, in two linear passes
    /// (Felzenszwalb & Huttenlocher's lower envelope of parabolas).
    static func nearestSite(width w: Int, height h: Int, isSite: (Int) -> Bool) -> (squared: [Float], site: [Int32]) {
        let n = w * h
        let far = Float.infinity
        // Pass 1, down each column: vertical distance to the nearest site in the column.
        var vertical = [Float](repeating: far, count: n)
        var siteRow = [Int32](repeating: -1, count: n)
        for x in 0..<w {
            var last = -1
            for y in 0..<h {
                let i = y * w + x
                if isSite(i) { last = y }
                if last >= 0 {
                    let d = Float(y - last)
                    vertical[i] = d * d
                    siteRow[i] = Int32(last)
                }
            }
            last = -1
            for y in stride(from: h - 1, through: 0, by: -1) {
                let i = y * w + x
                if isSite(i) { last = y }
                if last >= 0 {
                    let d = Float(last - y)
                    if d * d < vertical[i] {
                        vertical[i] = d * d
                        siteRow[i] = Int32(last)
                    }
                }
            }
        }
        // Pass 2, along each row: the lower envelope of one parabola per column.
        var squared = [Float](repeating: far, count: n)
        var site = [Int32](repeating: -1, count: n)
        var v = [Int](repeating: 0, count: w)
        var z = [Double](repeating: 0, count: w + 1)
        for y in 0..<h {
            let row = y * w
            var k = -1
            for q in 0..<w where vertical[row + q] < far {
                let fq = Double(vertical[row + q]) + Double(q * q)
                while k >= 0 {
                    let p = v[k]
                    let s = (fq - (Double(vertical[row + p]) + Double(p * p))) / Double(2 * (q - p))
                    if s <= z[k] { k -= 1 } else {
                        k += 1
                        v[k] = q
                        z[k] = s
                        break
                    }
                }
                if k < 0 {
                    k = 0
                    v[0] = q
                    z[0] = -.infinity
                }
                z[k + 1] = .infinity
            }
            guard k >= 0 else { continue }
            var j = 0
            for x in 0..<w {
                while z[j + 1] < Double(x) { j += 1 }
                let q = v[j]
                let dx = Float(x - q)
                squared[row + x] = dx * dx + vertical[row + q]
                site[row + x] = siteRow[row + q] * Int32(w) + Int32(q)
            }
        }
        return (squared, site)
    }

    /// Solves `A x = b` for a small dense system by Gaussian elimination with partial pivoting.
    /// Nil when `A` is singular.
    static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = a
        var rhs = b
        for col in 0..<n {
            let pivot = (col..<n).max { abs(m[$0][col]) < abs(m[$1][col]) }!
            guard abs(m[pivot][col]) > 1e-12 else { return nil }
            m.swapAt(col, pivot)
            rhs.swapAt(col, pivot)
            for row in (col + 1)..<n {
                let f = m[row][col] / m[col][col]
                guard f != 0 else { continue }
                for k in col..<n { m[row][k] -= f * m[col][k] }
                rhs[row] -= f * rhs[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[row]
            for k in (row + 1)..<n { sum -= m[row][k] * x[k] }
            x[row] = sum / m[row][row]
        }
        return x
    }
}
