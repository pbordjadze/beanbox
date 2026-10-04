import Foundation

/// Groups look-alike beans photographed on a plain sheet.
///
/// Pipeline: find the sheet the beans are lying on → flat-field the photo against it →
/// segment every bean → measure each bean's body colour → cluster at every group count, so
/// the interface can slide between groupings without recomputing.
///
/// The sheet is normally white paper. White and pale beans don't show up against that, so a
/// dark sheet works too — ideally with some of the white paper underneath still visible at
/// the frame's edge to calibrate against.
public enum Sorting {
    /// One per colour in the app's validated group palette.
    public static let maxGroups = 6
    /// Foreground = far enough from the sheet's colour. Being darker than the sheet counts for
    /// less, so a cast shadow stays background.
    static let foregroundThreshold = 12.0
    static let shadowLWeight = 0.35
    /// The sheet must fill at least this much of the frame to be recognised.
    static let sheetShare = 0.15
    /// Something this much brighter than the sheet, over this much of the frame, means the
    /// sheet itself isn't the white in the shot.
    static let brighter = 1.25
    static let sizeable = 0.01
    /// Lightness is the noisiest part of a bean measurement (it depends on how the bean
    /// happens to be lying), so it gets less say in the grouping.
    static let lWeight = 0.7
    /// Below this silhouette score the "groups" are just one cloud cut in half.
    static let minSilhouette = 0.5
    static let minSeparation = 2.0
    /// How deep into a blob (as a fraction of its half-width) a pixel must be to seed a bean.
    /// Higher splits beans that touch along more of their length, but starts cutting single
    /// kidney-shaped beans in two at the waist.
    static let coreDepth = 0.8

    public enum Failure: Error, Equatable {
        /// No plain sheet filling the frame, or fewer than two beans on it.
        case noBeans
    }

    /// An ellipse in photo pixels; `angle` in degrees, clockwise with y down.
    public struct Blob: Sendable, Equatable {
        public var cx, cy, rx, ry, angle: Double
    }

    public struct Bean: Sendable, Equatable {
        public var shape: Blob
        public var lab: Lab
        /// The bean's colour with the pile's differences stretched until they are easy to see.
        public var enhanced: Lab
        /// Position along the pile's two strongest colour differences, in Lab units.
        public var principal: SIMD2<Double>
    }

    /// What the beans were lying on.
    public struct Sheet: Sendable, Equatable {
        public var lab: Lab
        public var isWhite: Bool
        /// False when the shot had no white to measure against: colours are then consistent
        /// within the photo (fine for grouping) but not comparable with other photos.
        public var calibrated: Bool
    }

    public struct Partition: Sendable, Equatable {
        public var groupCount: Int
        /// Group of each bean; groups are ordered light → dark.
        public var assignment: [Int]
        public var centroids: [Lab]
        public var counts: [Int]
        /// Smallest ΔE between any two group centres; nil for a single group.
        public var minSeparation: Double?
    }

    public struct Analysis: Sendable, Equatable {
        public var beans: [Bean]
        /// Blobs too big to be one bean that couldn't be split; left out of the grouping.
        public var clumps: [Blob]
        public var sheet: Sheet
        /// One per group count, from 1 up to `maxGroups` (fewer for tiny piles).
        public var partitions: [Partition]
        public var suggestedGroupCount: Int
    }

    public static func analyze(_ image: PixelImage, tappedWhite: XYZ? = nil) throws -> Analysis {
        let found = try segment(image, tappedWhite: tappedWhite)
        return group(found.beans, clumps: found.clumps, sheet: found.sheet)
    }

    // MARK: Segmentation

    struct Measured: Sendable {
        var shape: Blob
        var lab: Lab
    }

    private struct Surface {
        /// Six quadratic coefficients per cone channel.
        var c: [SIMD3<Double>]

        @inline(__always)
        func value(u: Double, v: Double) -> SIMD3<Double> {
            let s = c[0] + c[1] * u + c[2] * v + c[3] * (u * u) + c[4] * (u * v) + c[5] * (v * v)
            return s.clamped(lowerBound: SIMD3(repeating: 0.02), upperBound: SIMD3(repeating: .infinity))
        }
    }

    /// Finds every bean on the sheet. `tappedWhite` is the photo's white if the user set one;
    /// it only matters when the sheet isn't white paper.
    static func segment(_ image: PixelImage, tappedWhite: XYZ?) throws -> (beans: [Measured], clumps: [Blob], sheet: Sheet) {
        let w = image.width, h = image.height, n = w * h
        guard w >= 32, h >= 32 else { throw Failure.noBeans }
        // Work in Bradford cone space throughout, so dividing by the white here is the same
        // adaptation `Sampling.sample` applies — a group saved from a sort is then comparable
        // with a tapped sample.
        let toCone = ColorScience.bradford * ColorScience.toXYZ(image.space)
        let toXYZ = ColorScience.bradfordInverse
        let target = ColorScience.bradford * (ColorScience.d65 * ColorScience.whiteY)
        let table = ColorScience.decodeTable
        var cone = [Float](repeating: 0, count: n * 3)
        image.rgba.withUnsafeBufferPointer { src in
            for i in 0..<n {
                let c = toCone * SIMD3(table[Int(src[i * 4])], table[Int(src[i * 4 + 1])], table[Int(src[i * 4 + 2])])
                cone[i * 3] = Float(c.x)
                cone[i * 3 + 1] = Float(c.y)
                cone[i * 3 + 2] = Float(c.z)
            }
        }
        @inline(__always) func coneAt(_ i: Int) -> SIMD3<Double> {
            SIMD3(Double(cone[i * 3]), Double(cone[i * 3 + 1]), Double(cone[i * 3 + 2]))
        }
        @inline(__always) func labAt(_ lab: [Float], _ i: Int) -> Lab {
            Lab(Double(lab[i * 3]), Double(lab[i * 3 + 1]), Double(lab[i * 3 + 2]))
        }

        // Pass 1: a rough global white is enough to tell sheet from not-sheet. The sheet is
        // whatever colour fills most of the frame.
        let tapped = tappedWhite.map { ColorScience.bradford * $0 }
        let guess = tapped ?? ColorScience.bradford * Sampling.autoWhite(image).xyz
        var lab = [Float](repeating: 0, count: n * 3)
        let roughScale = target / guess
        for i in 0..<n {
            let v = ColorScience.lab(fromXYZ: toXYZ * (coneAt(i) * roughScale))
            lab[i * 3] = Float(v.x)
            lab[i * 3 + 1] = Float(v.y)
            lab[i * 3 + 2] = Float(v.z)
        }
        var subsampled: [Lab] = []
        for y in stride(from: 0, to: h, by: 4) {
            for x in stride(from: 0, to: w, by: 4) { subsampled.append(labAt(lab, y * w + x)) }
        }
        let (roughSheet, share) = dominant(subsampled)
        let rough = foreground(lab, sheet: roughSheet, flat: false, width: w, height: h)
        let grow = max(5, Int(0.02 * Double(max(w, h)))) | 1
        let notSheet = Raster.dilate(rough, width: w, height: h, size: grow)
        var bareCount = 0
        for v in notSheet where v == 0 { bareCount += 1 }
        guard share >= sheetShare, Double(bareCount) >= sheetShare * Double(n) else { throw Failure.noBeans }
        let roughParts = Raster.components(rough, width: w, height: h, eightConnected: true)
        let hugging = roughParts.frameHugging(width: w, height: h)

        // Pass 2: divide out the sheet's own brightness, so lighting fall-off is gone
        // everywhere on it, not just on average. `level` is the sheet's colour under this light.
        guard let surface = fitSurface(cone: cone, bare: notSheet, width: w, height: h) else { throw Failure.noBeans }
        @inline(__always) func surfaceAt(_ i: Int) -> SIMD3<Double> {
            surface.value(u: Double(i % w) / Double(w) * 2 - 1, v: Double(i / w) / Double(h) * 2 - 1)
        }
        var levelSamples: [SIMD3<Double>] = []
        var seen = 0
        for i in 0..<n where notSheet[i] == 0 {
            if seen % 16 == 0 { levelSamples.append(surfaceAt(i)) }
            seen += 1
        }
        let level = Stats.median(levelSamples)
        @inline(__always) func flatAt(_ i: Int) -> SIMD3<Double> { coneAt(i) / surfaceAt(i) * level }

        let reference = referenceWhite(
            width: w, height: h, notSheet: notSheet, level: level, tapped: tapped,
            flat: flatAt, isSurround: { hugging[Int(roughParts.labels[$0])] })
        let scale = target / reference.white
        for i in 0..<n {
            let v = ColorScience.lab(fromXYZ: toXYZ * (flatAt(i) * scale))
            lab[i * 3] = Float(v.x)
            lab[i * 3 + 1] = Float(v.y)
            lab[i * 3 + 2] = Float(v.z)
        }
        var sheetSamples: [Lab] = []
        seen = 0
        for i in 0..<n where notSheet[i] == 0 {
            if seen % 16 == 0 { sheetSamples.append(labAt(lab, i)) }
            seen += 1
        }
        let sheetLab = Stats.median(sheetSamples)
        var fg = foreground(lab, sheet: sheetLab, flat: true, width: w, height: h)

        // Dust, the sheet's surroundings, and anything else touching the frame that is far
        // bigger than a bean.
        let parts = Raster.components(fg, width: w, height: h, eightConnected: true)
        var junk = (0..<parts.count).map { $0 == 0 || parts.area[$0] < 40 }
        let inner = (1..<parts.count).filter { !junk[$0] && !parts.onEdge($0, width: w, height: h) }
        if !inner.isEmpty {
            let typical = Stats.median(inner.map { Double(parts.area[$0]) })
            for i in 1..<parts.count where parts.onEdge(i, width: w, height: h) && Double(parts.area[i]) > 4 * typical {
                junk[i] = true
            }
        }
        for (i, hugs) in parts.frameHugging(width: w, height: h).enumerated() where hugs { junk[i] = true }
        guard junk.contains(false) else { throw Failure.noBeans }
        for i in 0..<n where junk[Int(parts.labels[i])] { fg[i] = 0 }

        // Touching beans: seed each one from the core of its distance transform and give
        // every pixel to the nearest seed. The core threshold follows each blob's own
        // thickness (so a small bean still gets a seed) but is capped at the typical bean's,
        // so a fat pile doesn't hide its necks.
        let distance = Raster.nearestSite(width: w, height: h) { fg[$0] == 0 }.squared.map { $0.squareRoot() }
        var thickness = [Float](repeating: 0, count: parts.count)
        for i in 0..<n where fg[i] != 0 {
            let p = Int(parts.labels[i])
            thickness[p] = max(thickness[p], distance[i])
        }
        let typicalRadius = Float(Stats.median((0..<parts.count).filter { !junk[$0] }.map { Double(thickness[$0]) }))
        var core = [UInt8](repeating: 0, count: n)
        for i in 0..<n where fg[i] != 0 {
            let p = Int(parts.labels[i])
            if distance[i] > Float(coreDepth) * min(thickness[p], typicalRadius) { core[i] = 1 }
        }
        let seeds = Raster.components(core, width: w, height: h, eightConnected: true)
        guard seeds.count > 1 else { throw Failure.noBeans }
        let nearest = Raster.nearestSite(width: w, height: h) { seeds.labels[$0] != 0 }.site

        // Per seed: area, image moments (for the ellipse) and its deepest point.
        let count = seeds.count
        var owner = [Int32](repeating: 0, count: n)
        var area = [Double](repeating: 0, count: count)
        var sx = area, sy = area, sxx = area, syy = area, sxy = area
        var deepest = [Float](repeating: 0, count: count)
        for i in 0..<n where fg[i] != 0 {
            let s = Int(nearest[i])
            guard s >= 0, parts.labels[s] == parts.labels[i] else { continue }
            let label = Int(seeds.labels[s])
            owner[i] = Int32(label)
            let x = Double(i % w), y = Double(i / w)
            area[label] += 1
            sx[label] += x; sy[label] += y
            sxx[label] += x * x; syy[label] += y * y; sxy[label] += x * y
            deepest[label] = max(deepest[label], distance[i])
        }
        var body = [[Lab]](repeating: [], count: count)
        for i in 0..<n where owner[i] != 0 {
            let label = Int(owner[i])
            if distance[i] >= 0.35 * deepest[label] { body[label].append(labAt(lab, i)) }
        }
        var found: [(area: Double, shape: Blob, lab: Lab)] = []
        for label in 1..<count where area[label] > 0 && !body[label].isEmpty {
            let m = area[label]
            let cx = sx[label] / m, cy = sy[label] / m
            let mu20 = sxx[label] / m - cx * cx, mu02 = syy[label] / m - cy * cy, mu11 = sxy[label] / m - cx * cy
            let common = (4 * mu11 * mu11 + (mu20 - mu02) * (mu20 - mu02)).squareRoot()
            let shape = Blob(
                cx: cx, cy: cy,
                rx: (2 * (mu20 + mu02 + common)).squareRoot(),
                ry: max(2 * (mu20 + mu02 - common), 1).squareRoot(),
                angle: 0.5 * atan2(2 * mu11, mu20 - mu02) * 180 / .pi)
            found.append((m, shape, Sampling.bodyColor(body[label])))
        }
        guard !found.isEmpty else { throw Failure.noBeans }
        let typicalArea = Stats.median(found.map(\.area))
        let beans = found.filter { $0.area >= 0.3 * typicalArea && $0.area <= 1.9 * typicalArea }
            .map { Measured(shape: $0.shape, lab: $0.lab) }
        let clumps = found.filter { $0.area > 1.9 * typicalArea }.map(\.shape)
        guard beans.count >= 2 else { throw Failure.noBeans }
        return (beans, clumps, Sheet(lab: sheetLab, isWhite: reference.isWhite, calibrated: reference.calibrated))
    }

    /// Most common colour among the pixels → (its Lab, share of the pixels near it).
    private static func dominant(_ lab: [Lab]) -> (Lab, Double) {
        var counts: [SIMD3<Int32>: Int] = [:]
        for v in lab {
            let bin = SIMD3(Int32((v.x / 8).rounded(.down)), Int32((v.y / 8).rounded(.down)), Int32((v.z / 8).rounded(.down)))
            counts[bin, default: 0] += 1
        }
        // The fullest bin; ties go to the lowest bin so the result doesn't depend on hashing.
        let best = counts.max { a, b in
            if a.value != b.value { return a.value < b.value }
            return (b.key.x, b.key.y, b.key.z) < (a.key.x, a.key.y, a.key.z)
        }!.key
        let centre = Lab((Double(best.x) + 0.5) * 8, (Double(best.y) + 0.5) * 8, (Double(best.z) + 0.5) * 8)
        let weight = SIMD3(shadowLWeight, 1.0, 1.0)
        let near = lab.filter {
            let d = ($0 - centre) * weight
            return (d * d).sum().squareRoot() < foregroundThreshold
        }
        return (Stats.median(near), Double(near.count) / Double(lab.count))
    }

    /// Mask of everything that isn't bare sheet.
    ///
    /// Once the lighting has been flattened (`flat`), anything *lighter* than the sheet counts
    /// in full — that is what makes a white bean on a dark sheet visible. Before that, lighter
    /// may just mean better lit, so lightness is down-weighted both ways.
    private static func foreground(_ lab: [Float], sheet: Lab, flat: Bool, width w: Int, height h: Int) -> [UInt8] {
        let n = w * h
        var mask = [UInt8](repeating: 0, count: n)
        let threshold = foregroundThreshold * foregroundThreshold
        for i in 0..<n {
            let dl = Double(lab[i * 3]) - sheet.x
            let wl = flat && dl > 0 ? 1.0 : shadowLWeight
            let da = Double(lab[i * 3 + 1]) - sheet.y, db = Double(lab[i * 3 + 2]) - sheet.z
            if wl * dl * wl * dl + da * da + db * db > threshold { mask[i] = 1 }
        }
        var fg = Raster.open(mask, width: w, height: h, iterations: 2)
        // On white paper, specular glints read as holes inside a bean; fill them. Only small
        // holes — the sheet is itself a "hole" in the table.
        let inverse = fg.map { 1 - $0 }
        let holes = Raster.components(inverse, width: w, height: h, eightConnected: false)
        let limit = 0.00025 * Double(n)
        for i in 0..<n where holes.labels[i] != 0 && Double(holes.area[Int(holes.labels[i])]) < limit { fg[i] = 1 }
        return fg
    }

    /// Quadratic fit of the bare sheet's brightness, per cone channel.
    private static func fitSurface(cone: [Float], bare notSheet: [UInt8], width w: Int, height h: Int) -> Surface? {
        var design: [[Double]] = []
        var values: [SIMD3<Double>] = []
        for y in stride(from: 0, to: h, by: 6) {
            for x in stride(from: 0, to: w, by: 6) where notSheet[y * w + x] == 0 {
                let u = Double(x) / Double(w) * 2 - 1, v = Double(y) / Double(h) * 2 - 1
                design.append([1, u, v, u * u, u * v, v * v])
                let i = (y * w + x) * 3
                values.append(SIMD3(Double(cone[i]), Double(cone[i + 1]), Double(cone[i + 2])))
            }
        }
        func fit(_ rows: [Int]) -> [SIMD3<Double>]? {
            guard rows.count >= 6 else { return nil }
            var a = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 6)
            var b = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 3)
            for r in rows {
                let d = design[r]
                let val = values[r]
                for i in 0..<6 {
                    for j in 0..<6 { a[i][j] += d[i] * d[j] }
                    b[0][i] += d[i] * val.x
                    b[1][i] += d[i] * val.y
                    b[2][i] += d[i] * val.z
                }
            }
            guard let cx = Raster.solve(a, b[0]), let cy = Raster.solve(a, b[1]), let cz = Raster.solve(a, b[2]) else { return nil }
            return (0..<6).map { SIMD3(cx[$0], cy[$0], cz[$0]) }
        }
        guard let first = fit(Array(design.indices)) else { return nil }
        // Soft shadows drag the fit down; drop points well below it and refit.
        let residual = design.indices.map { r -> Double in
            let d = design[r]
            var predicted = SIMD3<Double>(repeating: 0)
            for i in 0..<6 { predicted += first[i] * d[i] }
            return (values[r] - predicted).sum() / 3
        }
        let centre = Stats.median(residual)
        let sigma = 1.4826 * Stats.median(residual.map { abs($0 - centre) }) + 1e-6
        let kept = design.indices.filter { residual[$0] > -1.5 * sigma }
        return (fit(kept) ?? first).map { Surface(c: $0) }
    }

    /// Picks the white for a flattened shot, in cone space.
    private static func referenceWhite(
        width w: Int, height h: Int, notSheet: [UInt8], level: SIMD3<Double>, tapped: SIMD3<Double>?,
        flat: (Int) -> SIMD3<Double>, isSurround: (Int) -> Bool
    ) -> (white: SIMD3<Double>, isWhite: Bool, calibrated: Bool) {
        let toXYZ = ColorScience.bradfordInverse
        var pixels: [SIMD3<Double>] = []
        var luminance: [Double] = []
        var paperLike: [Bool] = []
        var frame = 0
        let levelXYZ = toXYZ * level
        for y in stride(from: 0, to: h, by: 4) {
            for x in stride(from: 0, to: w, by: 4) {
                frame += 1
                let i = y * w + x
                guard notSheet[i] != 0 else { continue }
                let p = flat(i)
                let xyz = toXYZ * p
                pixels.append(p)
                luminance.append(xyz.y)
                paperLike.append(
                    xyz.y > brighter * levelXYZ.y && isSurround(i)
                        && Sampling.neutralChroma(of: xyz) < Sampling.neutralChromaLimit)
            }
        }
        let sizeablePixels = sizeable * Double(frame)
        let brighterCount = luminance.count(where: { $0 > brighter * levelXYZ.y })
        let sheetNeutral = Sampling.neutralChroma(of: levelXYZ) < Sampling.neutralChromaLimit

        // White paper: neutral, and nothing much in the shot outshines it.
        if sheetNeutral && Double(brighterCount) < sizeablePixels { return (level, true, true) }
        if let tapped { return (tapped, false, true) }

        // White paper showing around the sheet. Only the surroundings are searched, so white
        // beans can't pass for paper.
        let paper = paperLike.indices.filter { paperLike[$0] }
        if Double(paper.count) >= sizeablePixels / 2 {
            let top = Stats.percentile(paper.map { luminance[$0] }.sorted(), 98)
            let band = paper.filter { luminance[$0] >= 0.8 * top && luminance[$0] <= top }
            return (Stats.median(band.map { pixels[$0] }), false, true)
        }

        // No white anywhere. Take the light's colour from the sheet if it is neutral (black or
        // grey paper reflects the lamp), and call the brightest thing in the shot white so
        // values stay in a sane range.
        let tint = sheetNeutral ? level : ColorScience.bradford * ColorScience.d65
        let peak = luminance.isEmpty ? levelXYZ.y : Stats.percentile(luminance.sorted(), 99.5)
        return (tint * (peak / (toXYZ * tint).y), false, false)
    }

    // MARK: Grouping

    /// Clusters beans at every group count up to `maxGroups` and picks a default. Groups are
    /// lettered light → dark so the labelling is stable as the count moves.
    static func group(_ measured: [Measured], clumps: [Blob], sheet: Sheet) -> Analysis {
        let n = measured.count
        let labs = measured.map(\.lab)
        let weight = SIMD3(lWeight, 1.0, 1.0)
        let features = labs.map { $0 * weight }
        let mean = features.reduce(SIMD3<Double>(repeating: 0), +) / Double(max(n, 1))
        let centred = features.map { $0 - mean }

        var beans = measured.map { Bean(shape: $0.shape, lab: $0.lab, enhanced: $0.lab, principal: .zero) }
        if n >= 3 {
            var covariance = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
            for c in centred {
                for i in 0..<3 {
                    for j in 0..<3 { covariance[i][j] += c[i] * c[j] / Double(n - 1) }
                }
            }
            let eigen = Clustering.symmetricEigen(covariance)
            // Decorrelation stretch: equalise the spread along every principal axis so
            // differences too small to see become obvious. The floor (σ = 1.5 ΔE, about one
            // flavour's natural bean-to-bean scatter) keeps pure measurement noise from being
            // blown up to full scale.
            let gain = eigen.values.map { 1 / max($0, 2.25).squareRoot() }
            for i in 0..<n {
                let c = centred[i]
                var white = SIMD3<Double>(repeating: 0)
                for axis in 0..<3 {
                    let e = eigen.vectors[axis]
                    white += e * ((c * e).sum() * gain[axis])
                }
                beans[i].enhanced = Lab(min(max(62 + 15 * white.x, 25), 92), 36 * white.y, 36 * white.z)
                beans[i].principal = SIMD2((c * eigen.vectors[0]).sum(), (c * eigen.vectors[1]).sum())
            }
        }

        var partitions = [Partition(groupCount: 1, assignment: [Int](repeating: 0, count: n), centroids: [Stats.median(labs)], counts: [n], minSeparation: nil)]
        var suggested = 1
        guard n >= 2 else { return Analysis(beans: beans, clumps: clumps, sheet: sheet, partitions: partitions, suggestedGroupCount: 1) }

        let merges = Clustering.wardMerges(features)
        var bestScore = minSilhouette
        for k in 2...min(maxGroups, n) {
            let raw = Clustering.cut(merges: merges, count: n, clusters: k)
            guard Set(raw).count == k else { break }
            let centroids = (0..<k).map { g in Stats.median(labs.indices.filter { raw[$0] == g }.map { labs[$0] }) }
            let order = (0..<k).sorted { centroids[$0].x > centroids[$1].x }
            var rank = [Int](repeating: 0, count: k)
            for (position, g) in order.enumerated() { rank[g] = position }
            let assignment = raw.map { rank[$0] }
            let ordered = order.map { centroids[$0] }
            var separation = Double.infinity
            for i in 0..<k {
                for j in (i + 1)..<k { separation = min(separation, ColorScience.ciede2000(ordered[i], ordered[j])) }
            }
            var counts = [Int](repeating: 0, count: k)
            for g in assignment { counts[g] += 1 }
            partitions.append(Partition(groupCount: k, assignment: assignment, centroids: ordered, counts: counts, minSeparation: separation))
            if k < n {
                let score = Clustering.silhouette(features, labels: assignment, clusters: k)
                if score > bestScore && separation >= minSeparation {
                    suggested = k
                    bestScore = score
                }
            }
        }
        return Analysis(beans: beans, clumps: clumps, sheet: sheet, partitions: partitions, suggestedGroupCount: suggested)
    }
}
