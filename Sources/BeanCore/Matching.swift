import Foundation

/// Optimal flavour → paper assignment.
public enum Matching {
    /// A curved glossy bean never photographs at the same lightness as a flat matte sheet of
    /// the same colour, so lightness is the least trustworthy axis of a bean-versus-paper
    /// comparison. Its weight is halved (the textile-industry CIEDE2000 convention).
    public static let kL = 2.0
    static let alternateCount = 5

    public struct Flavor: Sendable, Equatable {
        /// Case- and whitespace-insensitive name: samples sharing it are one flavour.
        public var key: String
        public var label: String
        public var lab: Lab
        public var sampleCount: Int

        public init(key: String, label: String, lab: Lab, sampleCount: Int = 1) {
            self.key = key
            self.label = label
            self.lab = lab
            self.sampleCount = sampleCount
        }
    }

    public struct Paper: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var label: String
        public var lab: Lab
        /// False once the sheet is used up or ruined.
        public var available: Bool

        public init(id: UUID, label: String, lab: Lab, available: Bool = true) {
            self.id = id
            self.label = label
            self.lab = lab
            self.available = available
        }
    }

    public struct Alternate: Sendable, Equatable, Identifiable {
        public var paper: Paper
        public var deltaE: Double
        /// The other flavour currently holding this sheet, if any.
        public var takenBy: String?
        public var id: UUID { paper.id }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public var flavor: Flavor
        public var paper: Paper?
        public var deltaE: Double?
        public var locked: Bool
        public var alternates: [Alternate]
        public var id: String { flavor.key }
    }

    public static func flavorKey(_ label: String) -> String {
        label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Gives every flavour its own sheet, minimising total squared ΔE.
    ///
    /// Squaring makes one bad mismatch cost more than several slight ones, so the solver
    /// spreads the compromise instead of sacrificing a flavour. Locked pairs are honoured
    /// as-is; unavailable sheets are never assigned unless locked (a lock is how an
    /// already-folded box is recorded). Rows come back in the order of `flavors`.
    public static func solve(flavors: [Flavor], papers: [Paper], locks: [String: UUID]) -> [Row] {
        guard !flavors.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: papers.map { ($0.id, $0) })
        var chosen: [String: Paper] = [:]
        for flavor in flavors {
            if let id = locks[flavor.key], let paper = byID[id] { chosen[flavor.key] = paper }
        }
        let taken = Set(chosen.values.map(\.id))
        let freeFlavors = flavors.filter { chosen[$0.key] == nil }
        let freePapers = papers.filter { $0.available && !taken.contains($0.id) }

        func cost(_ flavor: Flavor, _ paper: Paper) -> Double {
            ColorScience.ciede2000(flavor.lab, paper.lab, kL: kL)
        }
        if !freeFlavors.isEmpty, !freePapers.isEmpty {
            let squared = freeFlavors.map { f in freePapers.map { p in pow(cost(f, p), 2) } }
            for (row, column) in Assignment.solve(squared).enumerated() where column >= 0 {
                chosen[freeFlavors[row].key] = freePapers[column]
            }
        }

        var owner: [UUID: String] = [:]
        for flavor in flavors {
            if let paper = chosen[flavor.key] { owner[paper.id] = flavor.label }
        }
        return flavors.map { flavor in
            let paper = chosen[flavor.key]
            let candidates = papers
                .filter { $0.available || taken.contains($0.id) }
                .map { (paper: $0, deltaE: cost(flavor, $0)) }
                .sorted { $0.deltaE < $1.deltaE }
            return Row(
                flavor: flavor,
                paper: paper,
                deltaE: paper.map { cost(flavor, $0) },
                locked: paper != nil && locks[flavor.key] == paper?.id,
                alternates: candidates.prefix(alternateCount).map {
                    let holder = owner[$0.paper.id]
                    return Alternate(paper: $0.paper, deltaE: $0.deltaE, takenBy: holder == flavor.label ? nil : holder)
                })
        }
    }
}

/// The assignment problem (Hungarian method), for rectangular cost matrices.
enum Assignment {
    /// For each row, the column assigned to it, or -1 when there are more rows than columns
    /// and the row went without. The total cost of the assigned pairs is minimal.
    static func solve(_ cost: [[Double]]) -> [Int] {
        let rows = cost.count
        let columns = cost.first?.count ?? 0
        guard rows > 0, columns > 0 else { return [Int](repeating: -1, count: rows) }
        if rows > columns {
            // Solve the transpose, then invert the mapping.
            let transposed = (0..<columns).map { c in (0..<rows).map { r in cost[r][c] } }
            var out = [Int](repeating: -1, count: rows)
            for (column, row) in solve(transposed).enumerated() where row >= 0 { out[row] = column }
            return out
        }
        // Potentials method, 1-indexed, rows ≤ columns.
        var u = [Double](repeating: 0, count: rows + 1)
        var v = [Double](repeating: 0, count: columns + 1)
        var match = [Int](repeating: 0, count: columns + 1)  // row matched to each column
        var way = [Int](repeating: 0, count: columns + 1)
        for row in 1...rows {
            match[0] = row
            var j0 = 0
            var minv = [Double](repeating: .infinity, count: columns + 1)
            var used = [Bool](repeating: false, count: columns + 1)
            repeat {
                used[j0] = true
                let i0 = match[j0]
                var delta = Double.infinity
                var j1 = 0
                for j in 1...columns where !used[j] {
                    let reduced = cost[i0 - 1][j - 1] - u[i0] - v[j]
                    if reduced < minv[j] {
                        minv[j] = reduced
                        way[j] = j0
                    }
                    if minv[j] < delta {
                        delta = minv[j]
                        j1 = j
                    }
                }
                for j in 0...columns {
                    if used[j] {
                        u[match[j]] += delta
                        v[j] -= delta
                    } else {
                        minv[j] -= delta
                    }
                }
                j0 = j1
            } while match[j0] != 0
            repeat {
                let j1 = way[j0]
                match[j0] = match[j1]
                j0 = j1
            } while j0 != 0
        }
        var out = [Int](repeating: -1, count: rows)
        for j in 1...columns where match[j] != 0 { out[match[j] - 1] = j - 1 }
        return out
    }
}
