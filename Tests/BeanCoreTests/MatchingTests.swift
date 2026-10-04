import Foundation
import Testing
@testable import BeanCore

@Suite struct MatchingTests {
    static let ids = (0..<8).map { _ in UUID() }

    static func flavor(_ name: String, _ lab: Lab) -> Matching.Flavor {
        Matching.Flavor(key: Matching.flavorKey(name), label: name, lab: lab)
    }

    static func paper(_ i: Int, _ lab: Lab, available: Bool = true) -> Matching.Paper {
        Matching.Paper(id: ids[i], label: "#\(i)", lab: lab, available: available)
    }

    static func rows(_ flavors: [Matching.Flavor], _ papers: [Matching.Paper], locks: [String: UUID] = [:]) -> [String: Matching.Row] {
        Dictionary(uniqueKeysWithValues: Matching.solve(flavors: flavors, papers: papers, locks: locks).map { ($0.flavor.label, $0) })
    }

    @Test func eachFlavorGetsItsClosestSheet() {
        let r = Self.rows(
            [Self.flavor("Cherry", Lab(40, 60, 35)), Self.flavor("Lime", Lab(70, -50, 55))],
            [Self.paper(1, Lab(70, -48, 50)), Self.paper(2, Lab(42, 58, 30)), Self.paper(3, Lab(50, 0, 0))])
        #expect(r["Cherry"]?.paper?.id == Self.ids[2])
        #expect(r["Lime"]?.paper?.id == Self.ids[1])
    }

    @Test func contestedSheetGoesWhereTheTotalIsBest() {
        // Both reds prefer sheet 1. Greedy would give it to whichever came first and leave
        // the other with a terrible match; the optimum splits them.
        let r = Self.rows(
            [Self.flavor("A", Lab(40, 60, 30)), Self.flavor("B", Lab(41, 60, 30))],
            [Self.paper(1, Lab(40.5, 60, 30)), Self.paper(2, Lab(35, 60, 30)), Self.paper(3, Lab(80, 0, 0))])
        #expect(r["A"]?.paper?.id == Self.ids[2])
        #expect(r["B"]?.paper?.id == Self.ids[1])
    }

    @Test func lockIsHonouredAndTheRestResolvesAroundIt() {
        let r = Self.rows(
            [Self.flavor("Cherry", Lab(40, 60, 35)), Self.flavor("Berry", Lab(40, 55, 20))],
            [Self.paper(1, Lab(40, 60, 35)), Self.paper(2, Lab(40, 54, 21)), Self.paper(3, Lab(60, 10, 10))],
            locks: ["berry": Self.ids[1]])
        #expect(r["Berry"]?.paper?.id == Self.ids[1] && r["Berry"]?.locked == true)
        #expect(r["Cherry"]?.paper?.id == Self.ids[2] && r["Cherry"]?.locked == false)
    }

    @Test func unavailableSheetIsSkippedUnlessLocked() {
        let flavors = [Self.flavor("Cherry", Lab(40, 60, 35))]
        let papers = [Self.paper(1, Lab(40, 60, 35), available: false), Self.paper(2, Lab(45, 50, 30))]
        #expect(Self.rows(flavors, papers)["Cherry"]?.paper?.id == Self.ids[2])
        #expect(Self.rows(flavors, papers, locks: ["cherry": Self.ids[1]])["Cherry"]?.paper?.id == Self.ids[1])
    }

    @Test func moreFlavorsThanSheetsLeavesTheWorstFitEmpty() {
        let r = Self.rows(
            [Self.flavor("Cherry", Lab(40, 60, 35)), Self.flavor("Lime", Lab(70, -50, 55))],
            [Self.paper(1, Lab(41, 59, 34))])
        #expect(r["Cherry"]?.paper != nil)
        #expect(r["Lime"]?.paper == nil && r["Lime"]?.deltaE == nil)
    }

    @Test func alternatesAreRankedAndShowWhoHoldsThem() throws {
        let r = Self.rows(
            [Self.flavor("Cherry", Lab(40, 60, 35)), Self.flavor("Berry", Lab(40, 55, 20))],
            [Self.paper(1, Lab(40, 60, 35)), Self.paper(2, Lab(40, 54, 21)), Self.paper(3, Lab(60, 10, 10))])
        let cherry = try #require(r["Cherry"])
        #expect(cherry.alternates.map(\.paper.id) == [Self.ids[1], Self.ids[2], Self.ids[3]])
        #expect(cherry.alternates.map(\.takenBy) == [nil, "Berry", nil])
        #expect(cherry.alternates[0].deltaE <= cherry.alternates[1].deltaE)
    }

    @Test func noPapersYet() {
        let r = Matching.solve(flavors: [Self.flavor("Cherry", Lab(40, 60, 35))], papers: [], locks: [:])
        #expect(r.count == 1 && r[0].paper == nil && r[0].alternates.isEmpty)
    }

    @Test func flavorKeyIgnoresCaseAndSpacing() {
        #expect(Matching.flavorKey("  Very   Cherry ") == "very cherry")
        #expect(Matching.flavorKey("VERY CHERRY") == Matching.flavorKey("very cherry"))
    }

    @Test func assignmentIsOptimalOnSmallMatricesOfEveryShape() {
        // Against brute force over all injections of the shorter side into the longer.
        var rng = SplitMix64(state: 42)
        func permutations(_ n: Int, of m: Int) -> [[Int]] {
            if n == 0 { return [[]] }
            return permutations(n - 1, of: m).flatMap { head in (0..<m).filter { !head.contains($0) }.map { head + [$0] } }
        }
        for (rows, columns) in [(1, 1), (2, 2), (3, 3), (4, 4), (2, 5), (5, 2), (3, 6), (6, 3), (1, 4), (4, 1)] {
            for _ in 0..<20 {
                let cost = (0..<rows).map { _ in (0..<columns).map { _ in rng.uniform(0, 10) } }
                let result = Assignment.solve(cost)
                let assigned = result.enumerated().filter { $0.element >= 0 }
                #expect(assigned.count == min(rows, columns))
                #expect(Set(assigned.map(\.element)).count == assigned.count)
                let total = assigned.reduce(0.0) { $0 + cost[$1.offset][$1.element] }
                let best: Double
                if rows <= columns {
                    best = permutations(rows, of: columns).map { p in p.enumerated().reduce(0.0) { $0 + cost[$1.offset][$1.element] } }.min()!
                } else {
                    best = permutations(columns, of: rows).map { p in p.enumerated().reduce(0.0) { $0 + cost[$1.element][$1.offset] } }.min()!
                }
                #expect(abs(total - best) < 1e-9)
            }
        }
    }
}
