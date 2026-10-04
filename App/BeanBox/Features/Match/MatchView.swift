import BeanCore
import SwiftUI

/// Which sheet for which flavour: the best one-to-one pairing of everything measured.
struct MatchView: View {
    @Environment(Project.self) private var project
    @State private var open: FlavorRef?
    @State private var isShowingHow = false

    struct FlavorRef: Identifiable {
        let id: String
    }

    var body: some View {
        NavigationStack {
            let rows = project.matchRows
            Group {
                if rows.isEmpty || project.papers.isEmpty {
                    ContentUnavailableView(
                        "Nothing to pair yet", systemImage: "link",
                        description: Text("Measure some sheets in Papers and some flavours in Beans, and the best pairing shows up here."))
                } else {
                    List {
                        Section {
                            summary(rows)
                        }
                        Section {
                            ForEach(rows) { row in
                                Button {
                                    open = FlavorRef(id: row.id)
                                } label: {
                                    MatchRowLabel(row: row)
                                }
                                .buttonStyle(.plain)
                            }
                        } footer: {
                            Text("Screen colours are only a guide — go by the sheet number. Tap a row for runners-up, hold a bean against them, and lock the one you fold.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.plane)
            .navigationTitle("Match")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("How It Works", systemImage: "questionmark.circle") { isShowingHow = true }
                }
            }
            .sheet(item: $open) { ref in
                MatchDetail(flavorKey: ref.id)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingHow) {
                HowMatchingWorks()
                    .presentationDetents([.medium])
            }
            .task(id: rows.count) {
                // A demo scenario can ask for a row's detail to be showing.
                if Launch.shows("open"), open == nil, let second = rows.dropFirst().first { open = FlavorRef(id: second.id) }
            }
        }
    }

    private func summary(_ rows: [Matching.Row]) -> some View {
        let matched = rows.compactMap(\.deltaE)
        let mean = matched.reduce(0, +) / Double(max(matched.count, 1))
        let worst = rows.filter { $0.deltaE != nil }.max { $0.deltaE! < $1.deltaE! }
        let spare = project.papers.filter(\.available).count - rows.filter { $0.paper != nil }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(matched.count) of \(rows.count) flavours have a sheet")
                .font(.headline)
            Text("Typical ΔE \(mean, format: .number.precision(.fractionLength(1))) · \(max(spare, 0)) sheets spare")
                .foregroundStyle(.secondary)
            if let worst, let deltaE = worst.deltaE, deltaE > 5 {
                Text("Furthest off: \(worst.flavor.label) at ΔE \(deltaE, format: .number.precision(.fractionLength(1)))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

/// A flavour, its sheet and how close they are. The two swatches butt up against each other,
/// so any mismatch shows as a visible seam.
struct MatchRowLabel: View {
    let row: Matching.Row

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Rectangle().fill(Color(lab: row.flavor.lab))
                if let paper = row.paper {
                    Rectangle().fill(Color(lab: paper.lab))
                } else {
                    Rectangle().fill(Theme.plane)
                }
            }
            .frame(width: 84, height: 44)
            .clipShape(.rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline) }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.flavor.label).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(row.paper.map { "sheet \($0.label)" } ?? "no sheet left")
                    if row.locked { Image(systemName: "lock.fill").accessibilityLabel("locked") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let deltaE = row.deltaE {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ΔE \(deltaE, format: .number.precision(.fractionLength(1)))")
                        .font(.subheadline.monospacedDigit())
                    Text(Verdict.match(deltaE)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(.rect)
    }
}

/// One flavour's runners-up, and the lock.
struct MatchDetail: View {
    let flavorKey: String
    @Environment(Project.self) private var project
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let row = project.matchRows.first(where: { $0.id == flavorKey }) {
                List {
                    Section {
                        MatchRowLabel(row: row)
                    }
                    Section {
                        ForEach(row.alternates) { alternate in
                            let isCurrent = alternate.paper.id == row.paper?.id
                            HStack(spacing: 12) {
                                Swatch(lab: alternate.paper.lab).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sheet \(alternate.paper.label)").font(.body.weight(isCurrent ? .semibold : .regular))
                                    Text(caption(alternate)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isCurrent && row.locked {
                                    Button("Unlock") { project.setLock(flavor: row.flavor.key, paper: nil) }
                                        .buttonStyle(.bordered)
                                } else {
                                    Button(isCurrent ? "Lock" : "Use & Lock") {
                                        project.setLock(flavor: row.flavor.key, paper: alternate.paper.id)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    } header: {
                        Text("Closest sheets")
                    } footer: {
                        Text("Locked pairs never move; every other flavour re-solves around them.")
                    }
                }
                .navigationTitle(row.flavor.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
    }

    private func caption(_ alternate: Matching.Alternate) -> String {
        let deltaE = "ΔE \(alternate.deltaE.formatted(.number.precision(.fractionLength(1)))) · \(Verdict.match(alternate.deltaE))"
        guard let holder = alternate.takenBy else { return deltaE }
        return "\(deltaE) · held by \(holder)"
    }
}

struct HowMatchingWorks: View {
    @Environment(\.dismiss) private var dismiss

    private let points = [
        "Every flavour gets its own sheet, chosen so the whole set matches best — so a flavour may not get its single closest sheet if another flavour needs it more.",
        "ΔE is the colour difference: under 2 is hard to see, 2–5 is close, over 10 is a different colour. Lightness counts half, since a shiny curved bean never photographs as light as flat paper.",
        "Lock the pair you actually fold. Locked pairs never move; everything else re-solves around them. Mark a sheet used up in Papers if you spoil it.",
    ]

    var body: some View {
        NavigationStack {
            List(points, id: \.self) { Text($0).font(.subheadline) }
                .navigationTitle("How the pairing is worked out")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
