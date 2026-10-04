import Foundation

/// Small-n statistics for grouping beans: Ward clustering, silhouette, principal axes.
enum Clustering {
    /// Agglomerative Ward clustering. Returns the merges in the order they happen, each as the
    /// pair of point indices whose clusters were joined; replaying the first `n - k` of them
    /// leaves `k` clusters.
    static func wardMerges(_ points: [SIMD3<Double>]) -> [(Int, Int)] {
        let n = points.count
        guard n > 1 else { return [] }
        // Squared distances between clusters, updated in place (Lance–Williams).
        var d = [Double](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let diff = points[i] - points[j]
                let v = (diff * diff).sum()
                d[i * n + j] = v
                d[j * n + i] = v
            }
        }
        var size = [Double](repeating: 1, count: n)
        var active = [Bool](repeating: true, count: n)
        var merges: [(Int, Int)] = []
        for _ in 0..<(n - 1) {
            var best = Double.infinity
            var a = -1, b = -1
            for i in 0..<n where active[i] {
                for j in (i + 1)..<n where active[j] && d[i * n + j] < best {
                    best = d[i * n + j]
                    a = i
                    b = j
                }
            }
            merges.append((a, b))
            for k in 0..<n where active[k] && k != a && k != b {
                let total = size[a] + size[b] + size[k]
                let v = ((size[a] + size[k]) * d[a * n + k] + (size[b] + size[k]) * d[b * n + k] - size[k] * d[a * n + b]) / total
                d[a * n + k] = v
                d[k * n + a] = v
            }
            size[a] += size[b]
            active[b] = false
        }
        return merges
    }

    /// Cluster index (0..<k, in order of first appearance) for each point after cutting the
    /// hierarchy at `k` clusters.
    static func cut(merges: [(Int, Int)], count n: Int, clusters k: Int) -> [Int] {
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            return r
        }
        for (a, b) in merges.prefix(max(0, n - k)) {
            let keep = find(a), absorbed = find(b)
            parent[absorbed] = keep
        }
        var index: [Int: Int] = [:]
        return (0..<n).map { i in
            let root = find(i)
            if let known = index[root] { return known }
            index[root] = index.count
            return index.count - 1
        }
    }

    /// Mean silhouette of a labelling under Euclidean distance. Near 1: tight, well-separated
    /// groups; near 0: one cloud cut arbitrarily.
    static func silhouette(_ points: [SIMD3<Double>], labels: [Int], clusters k: Int) -> Double {
        let n = points.count
        var sizes = [Int](repeating: 0, count: k)
        for l in labels { sizes[l] += 1 }
        var total = 0.0
        var sums = [Double](repeating: 0, count: k)
        for i in 0..<n {
            for c in 0..<k { sums[c] = 0 }
            for j in 0..<n {
                let diff = points[i] - points[j]
                sums[labels[j]] += (diff * diff).sum().squareRoot()
            }
            let own = labels[i]
            guard sizes[own] > 1 else { continue }
            let a = sums[own] / Double(sizes[own] - 1)
            var b = Double.infinity
            for c in 0..<k where c != own && sizes[c] > 0 { b = min(b, sums[c] / Double(sizes[c])) }
            total += (b - a) / max(max(a, b), 1e-12)
        }
        return total / Double(n)
    }

    /// Eigenvalues (descending) and unit eigenvectors of a symmetric 3×3 matrix, by cyclic
    /// Jacobi rotations. Each vector's sign is fixed so its largest component is positive,
    /// which makes plots reproducible.
    static func symmetricEigen(_ matrix: [[Double]]) -> (values: [Double], vectors: [SIMD3<Double>]) {
        var a = matrix
        var v: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<50 {
            let off = abs(a[0][1]) + abs(a[0][2]) + abs(a[1][2])
            if off < 1e-14 { break }
            for (p, q) in [(0, 1), (0, 2), (1, 2)] where abs(a[p][q]) > 1e-300 {
                let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
                let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
                let c = 1 / (t * t + 1).squareRoot()
                let s = t * c
                for k in 0..<3 {
                    let akp = a[k][p], akq = a[k][q]
                    a[k][p] = c * akp - s * akq
                    a[k][q] = s * akp + c * akq
                }
                for k in 0..<3 {
                    let apk = a[p][k], aqk = a[q][k]
                    a[p][k] = c * apk - s * aqk
                    a[q][k] = s * apk + c * aqk
                }
                for k in 0..<3 {
                    let vkp = v[k][p], vkq = v[k][q]
                    v[k][p] = c * vkp - s * vkq
                    v[k][q] = s * vkp + c * vkq
                }
            }
        }
        let order = [0, 1, 2].sorted { a[$0][$0] > a[$1][$1] }
        let vectors = order.map { i -> SIMD3<Double> in
            var e = SIMD3(v[0][i], v[1][i], v[2][i])
            let largest = [e.x, e.y, e.z].max { abs($0) < abs($1) }!
            if largest < 0 { e = -e }
            return e
        }
        return (order.map { a[$0][$0] }, vectors)
    }
}
