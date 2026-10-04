import Foundation
import Testing
@testable import BeanCore

@Suite struct RasterTests {
    static func mask(_ rows: [String]) -> (data: [UInt8], w: Int, h: Int) {
        (rows.flatMap { $0.map { $0 == "#" ? UInt8(1) : 0 } }, rows[0].count, rows.count)
    }

    @Test func componentsAreLabelledInRasterOrderWithTheirBoxes() {
        let m = Self.mask([
            "##...#",
            "##...#",
            "......",
            "..#...",
            ".#....",
        ])
        let eight = Raster.components(m.data, width: m.w, height: m.h, eightConnected: true)
        #expect(eight.count == 4)
        #expect(eight.area == [0, 4, 2, 2])
        #expect(eight.labels[0] == 1 && eight.labels[5] == 2 && eight.labels[3 * 6 + 2] == 3 && eight.labels[4 * 6 + 1] == 3)
        #expect((eight.minX[3], eight.minY[3], eight.maxX[3], eight.maxY[3]) == (1, 3, 2, 4))
        // The diagonal pair is two components when only edges connect.
        #expect(Raster.components(m.data, width: m.w, height: m.h, eightConnected: false).count == 5)
    }

    @Test func frameHuggingNeedsBothTheEdgeAndLength() {
        var data = [UInt8](repeating: 0, count: 40 * 40)
        for x in 0..<40 { data[x] = 1 }             // a strip along the top edge
        data[20 * 40 + 0] = 1                        // a speck touching the left edge
        for x in 10..<30 { data[30 * 40 + x] = 1 }   // long, but not touching the frame
        let parts = Raster.components(data, width: 40, height: 40, eightConnected: true)
        #expect(parts.frameHugging(width: 40, height: 40) == [false, true, false, false])
    }

    @Test func openRemovesSpecksAndKeepsBlobs() {
        var data = [UInt8](repeating: 0, count: 30 * 30)
        for y in 8..<22 { for x in 8..<22 { data[y * 30 + x] = 1 } }
        data[2 * 30 + 2] = 1
        for x in 0..<30 { data[26 * 30 + x] = 1 }  // a one-pixel line
        let opened = Raster.open(data, width: 30, height: 30, iterations: 2)
        #expect(opened[2 * 30 + 2] == 0)
        #expect(opened[26 * 30 + 15] == 0)
        #expect(opened[15 * 30 + 15] == 1 && opened[9 * 30 + 15] == 1)
    }

    @Test func dilateGrowsByHalfTheSquare() {
        var data = [UInt8](repeating: 0, count: 21 * 21)
        data[10 * 21 + 10] = 1
        let grown = Raster.dilate(data, width: 21, height: 21, size: 5)
        for y in 0..<21 {
            for x in 0..<21 { #expect(grown[y * 21 + x] == (abs(x - 10) <= 2 && abs(y - 10) <= 2 ? 1 : 0)) }
        }
    }

    @Test func nearestSiteIsExact() {
        // Against brute force on random masks, including ones with empty rows and columns.
        var rng = SplitMix64(state: 9)
        for density in [0.02, 0.2, 0.7] {
            let w = 37, h = 23
            let sites = (0..<(w * h)).map { _ in rng.uniform() < density }
            let result = Raster.nearestSite(width: w, height: h) { sites[$0] }
            for y in 0..<h {
                for x in 0..<w {
                    var best = Int.max
                    for sy in 0..<h { for sx in 0..<w where sites[sy * w + sx] { best = min(best, (sx - x) * (sx - x) + (sy - y) * (sy - y)) } }
                    let i = y * w + x
                    #expect(Int(result.squared[i]) == best)
                    let s = Int(result.site[i])
                    #expect(sites[s] && (s % w - x) * (s % w - x) + (s / w - y) * (s / w - y) == best)
                }
            }
        }
        let none = Raster.nearestSite(width: 5, height: 4) { _ in false }
        #expect(none.site.allSatisfy { $0 == -1 } && none.squared.allSatisfy { $0 == .infinity })
    }

    @Test func linearSolve() throws {
        let x = try #require(Raster.solve([[2, 1, -1], [-3, -1, 2], [-2, 1, 2]], [8, -11, -3]))
        #expect(abs(x[0] - 2) < 1e-12 && abs(x[1] - 3) < 1e-12 && abs(x[2] + 1) < 1e-12)
        #expect(Raster.solve([[1, 2], [2, 4]], [1, 2]) == nil)
    }
}

@Suite struct ClusteringTests {
    @Test func wardSeparatesObviousClustersAtEveryCut() {
        var rng = SplitMix64(state: 3)
        let centres = [SIMD3(0.0, 0, 0), SIMD3(10.0, 0, 0), SIMD3(0.0, 12, 0)]
        let points = (0..<45).map { i in centres[i % 3] + SIMD3(rng.normal(), rng.normal(), rng.normal()) * 0.5 }
        let merges = Clustering.wardMerges(points)
        #expect(merges.count == 44)
        let three = Clustering.cut(merges: merges, count: 45, clusters: 3)
        for i in 0..<45 { #expect(three[i] == three[i % 3]) }
        #expect(Set(three).count == 3)
        // Two clusters: the two nearest centres (0 and 1, 10 apart) join first.
        let two = Clustering.cut(merges: merges, count: 45, clusters: 2)
        #expect(two[0] == two[1] && two[0] != two[2])
        #expect(Set(Clustering.cut(merges: merges, count: 45, clusters: 1)) == [0])
        #expect(Clustering.silhouette(points, labels: three, clusters: 3) > 0.85)
        #expect(Clustering.silhouette(points, labels: two, clusters: 2) < Clustering.silhouette(points, labels: three, clusters: 3))
    }

    @Test func eigenOfAKnownMatrix() {
        // Eigenvalues 4, 2, 1 with vectors (1,1,0)/√2, (1,-1,0)/√2, (0,0,1).
        let e = Clustering.symmetricEigen([[3, 1, 0], [1, 3, 0], [0, 0, 1]])
        #expect(abs(e.values[0] - 4) < 1e-12 && abs(e.values[1] - 2) < 1e-12 && abs(e.values[2] - 1) < 1e-12)
        let r = 0.5.squareRoot()
        #expect(abs(e.vectors[0].x - r) < 1e-9 && abs(e.vectors[0].y - r) < 1e-9 && abs(e.vectors[0].z) < 1e-9)
        #expect(abs(abs(e.vectors[1].x) - r) < 1e-9 && abs(e.vectors[1].x + e.vectors[1].y) < 1e-9)
        #expect(abs(e.vectors[2].z - 1) < 1e-9)
    }
}
