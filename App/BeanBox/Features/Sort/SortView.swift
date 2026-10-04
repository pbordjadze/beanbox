import BeanCore
import SwiftUI

/// Splits a pile of look-alike beans: every bean in the photo is found, measured and lettered
/// by group.
struct SortView: View {
    @Environment(Project.self) private var project
    @State private var loaded: LoadedPhoto?
    @State private var analysis: Sorting.Analysis?
    @State private var isWorking = false
    @State private var didFail = false
    @State private var groupCount = 1
    @State private var overlay = Launch.shows("exaggerated") ? Overlay.exaggerated : .groups
    /// The one group being shown; nil shows all.
    @State private var isolated: Int?
    @State private var picked: Int?
    @State private var names: [Int: String] = [:]
    @State private var isShowingMat = Launch.shows("mat")
    @State private var isShowingTips = false

    enum Overlay: String, CaseIterable, Identifiable {
        case groups = "Groups", exaggerated = "Exaggerated", photo = "Photo"
        var id: String { rawValue }
    }

    private struct Input: Equatable {
        var photo: UUID?
        var white: XYZ?
    }

    private var photo: PhotoRecord? { project.photo(project.focus[.sort]) }
    private var partition: Sorting.Partition? {
        analysis.flatMap { a in a.partitions.first { $0.groupCount == groupCount } ?? a.partitions.first }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 14) {
                    if photo == nil { SortTips() }
                    Card {
                        PhotoStrip(tab: .sort)
                        if isWorking { ProgressView("Finding beans…").frame(maxWidth: .infinity) }
                        if didFail { failure }
                        if let photo, let loaded, let analysis, let partition {
                            result(photo, loaded, analysis, partition)
                        }
                    }
                    if let photo, let analysis, let partition {
                        Card {
                            GroupChart(beans: analysis.beans, partition: partition, picked: $picked)
                            readout(analysis, partition)
                        }
                        .id("chart")
                        groups(photo, analysis, partition)
                    }
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: analysis != nil) {
                // A demo scenario can ask for the chart and groups to be in view.
                if Launch.shows("chart") { scroller.scrollTo("chart", anchor: .top) }
            }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.plane)
            .navigationTitle("Sort")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sorting Mat", systemImage: "printer") { isShowingMat = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tips", systemImage: "questionmark.circle") { isShowingTips = true }
                }
            }
            .sheet(isPresented: $isShowingMat) { MatSheet() }
            .sheet(isPresented: $isShowingTips) {
                NavigationStack {
                    ScrollView { SortTips().padding() }
                        .background(Theme.plane)
                        .navigationTitle("Shooting the pile")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingTips = false } } }
                }
                .presentationDetents([.medium, .large])
            }
            // The tapped white matters on a dark sheet, so setting it elsewhere re-sorts.
            .task(id: Input(photo: photo?.id, white: photo?.whiteAt == nil ? nil : photo?.white)) { await analyse() }
        }
    }

    private func analyse() async {
        analysis = nil
        loaded = nil
        didFail = false
        guard let photo else { return }
        isWorking = true
        defer { isWorking = false }
        guard let fresh = await project.loaded(photo) else { return }
        let result = await Project.sort(fresh.pixels, tappedWhite: photo.whiteAt == nil ? nil : photo.white)
        guard !Task.isCancelled else { return }
        loaded = fresh
        analysis = result
        didFail = result == nil
        groupCount = result?.suggestedGroupCount ?? 1
        isolated = nil
        picked = nil
        names = [:]
        #if DEBUG
        DemoMode.markReady()
        #endif
    }

    private var failure: some View {
        Label {
            Text("Couldn’t find beans on a plain sheet. Fill the frame with one sheet — white paper for coloured or dark beans, a dark sheet for white or pale ones — and spread the beans out in a single layer.")
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(.subheadline)
    }

    // MARK: Photo and its overlay

    @ViewBuilder
    private func result(_ photo: PhotoRecord, _ loaded: LoadedPhoto, _ analysis: Sorting.Analysis, _ partition: Sorting.Partition) -> some View {
        Text(verdict(analysis, partition)).font(.subheadline)
        HStack {
            Stepper(value: $groupCount, in: 1...analysis.partitions.count) {
                Text("Groups: **\(groupCount)**")
            }
            .fixedSize()
            .onChange(of: groupCount) {
                isolated = nil
                names = [:]
            }
            Spacer()
        }
        Picker("Overlay", selection: $overlay) {
            ForEach(Overlay.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        PhotoCanvas(image: loaded.image) { point in
            let hit = analysis.beans.indices
                .map { ($0, hypot(analysis.beans[$0].shape.cx - point.x, analysis.beans[$0].shape.cy - point.y)) }
                .filter { $0.1 < analysis.beans[$0.0].shape.rx * 1.3 }
                .min { $0.1 < $1.1 }
            picked = hit?.0
        } annotate: { context, scale in
            annotate(&context, scale, analysis, partition)
        }
        .accessibilityLabel("Photo of the beans, each marked with its group letter")
        if !analysis.clumps.isEmpty {
            note("Dashed outlines are beans too close together to pull apart, so they’re left out of the groups. Nudge them apart and retake to include them.")
        }
        if !analysis.sheet.calibrated {
            note("There’s no white paper in this shot, so these colours are only good for sorting, not for matching to paper. To save groups as flavours, retake with a strip of white paper showing at the edge.", warning: true)
        }
        if analysis.sheet.isWhite {
            note("A bean with no outline wasn’t seen. If it’s white or very pale, shoot those on a dark sheet instead.")
        }
        if overlay == .exaggerated {
            note("Exaggerated colours stretch whatever differences exist until they’re easy to see — real flavours come out as distinct blocks of colour. A smooth rainbow with no blocks means there’s only one flavour here.")
        }
    }

    private func note(_ text: LocalizedStringKey, warning: Bool = false) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: warning ? "exclamationmark.triangle" : "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(warning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }

    private func verdict(_ analysis: Sorting.Analysis, _ partition: Sorting.Partition) -> String {
        var text = "\(analysis.beans.count) beans found. "
        text += analysis.suggestedGroupCount == 1
            ? "They all measure as one colour — no split worth trusting."
            : "They look like \(analysis.suggestedGroupCount) different flavours."
        if let separation = partition.minSeparation {
            text += " At \(partition.groupCount) groups, the two closest differ by ΔE \(separation.formatted(.number.precision(.fractionLength(1)))) — \(Verdict.separation(separation))."
        }
        if partition.groupCount > analysis.suggestedGroupCount {
            text += " That’s more groups than the measurements support, so some of these splits are arbitrary."
        }
        return text
    }

    private func annotate(_ context: inout GraphicsContext, _ scale: Double, _ analysis: Sorting.Analysis, _ partition: Sorting.Partition) {
        // On a dark sheet the casing flips to white, or the coloured rings sink into it.
        let casing = analysis.sheet.lab.x < 50 ? Color.white.opacity(0.85) : Theme.ink.opacity(0.65)
        let grouped = partition.groupCount > 1
        if overlay != .photo {
            for (i, bean) in analysis.beans.enumerated() {
                let group = partition.assignment[i]
                context.opacity = isolated == nil || isolated == group ? 1 : 0.12
                // Drawn a little outside the bean, so the bean itself stays visible.
                let s = bean.shape
                let outline = Marks.ellipse(cx: s.cx, cy: s.cy, rx: s.rx * 1.25, ry: s.ry * 1.25, degrees: s.angle, scale: scale)
                if overlay == .exaggerated {
                    context.fill(outline, with: .color(Color(lab: bean.enhanced)))
                    context.stroke(outline, with: .color(casing), lineWidth: 1.5)
                } else {
                    Marks.ring(&context, outline, color: grouped ? Theme.groups[group].color : .white, casing: casing)
                }
                if grouped {
                    Marks.tag(&context, Theme.letters[group], at: CGPoint(x: s.cx * scale, y: s.cy * scale), size: 10)
                }
            }
            context.opacity = 1
            for clump in analysis.clumps {
                let outline = Marks.ellipse(cx: clump.cx, cy: clump.cy, rx: clump.rx, ry: clump.ry, degrees: clump.angle, scale: scale)
                context.stroke(outline, with: .color(casing), lineWidth: 4.5)
                context.stroke(outline, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))
            }
        }
        if let picked, analysis.beans.indices.contains(picked) {
            let s = analysis.beans[picked].shape
            let halo = Marks.ellipse(cx: s.cx, cy: s.cy, rx: s.rx * 1.7, ry: s.ry * 1.7, degrees: s.angle, scale: scale)
            Marks.ring(&context, halo, color: .white, casing: Theme.ink.opacity(0.8), width: 4)
        }
    }

    // MARK: Chart readout and groups

    @ViewBuilder
    private func readout(_ analysis: Sorting.Analysis, _ partition: Sorting.Partition) -> some View {
        if let picked, analysis.beans.indices.contains(picked) {
            let lab = analysis.beans[picked].lab
            HStack(spacing: 8) {
                if partition.groupCount > 1 { GroupChip(group: partition.assignment[picked]) }
                Swatch(lab: lab).frame(width: 28, height: 28)
                Text("L \(lab.x, format: .number.precision(.fractionLength(1)))  a \(lab.y, format: .number.precision(.fractionLength(1)))  b \(lab.z, format: .number.precision(.fractionLength(1)))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text("ringed on the photo").font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Text("Each dot is one bean. Separate clouds are separate flavours; one cloud is one flavour. Tap a dot to find that bean on the photo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func groups(_ photo: PhotoRecord, _ analysis: Sorting.Analysis, _ partition: Sorting.Partition) -> some View {
        let flavors = project.flavors
        return Card {
            ForEach(0..<partition.groupCount, id: \.self) { group in
                if group > 0 { Divider() }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if partition.groupCount > 1 { GroupChip(group: group) }
                        Swatch(lab: partition.centroids[group]).frame(width: 30, height: 30)
                        Text("^[\(partition.counts[group]) bean](inflect: true)").font(.body.weight(.semibold))
                        Spacer()
                        if partition.groupCount > 1 {
                            Button(isolated == group ? "Show All" : "Show Only") {
                                isolated = isolated == group ? nil : group
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    if let hint = hint(partition.centroids[group], flavors) {
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                    }
                    if analysis.sheet.calibrated {
                        HStack {
                            TextField("Tasted one? Name the flavour", text: Binding(get: { names[group] ?? "" }, set: { names[group] = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                            Button("Save") {
                                let label = (names[group] ?? "").trimmingCharacters(in: .whitespaces)
                                project.addFlavor(named: label, lab: partition.centroids[group], from: photo.id)
                                names[group] = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled((names[group] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
    }

    /// How a group compares with the nearest flavour already saved. Readings from different
    /// photos agree less tightly than within one, hence the generous "same" threshold.
    private func hint(_ lab: Lab, _ flavors: [Matching.Flavor]) -> String? {
        guard let nearest = flavors.min(by: { ColorScience.ciede2000(lab, $0.lab) < ColorScience.ciede2000(lab, $1.lab) }) else { return nil }
        let deltaE = ColorScience.ciede2000(lab, nearest.lab)
        guard deltaE < 7 else { return nil }
        let shown = "ΔE \(deltaE.formatted(.number.precision(.fractionLength(1))))"
        return deltaE < 3
            ? "Matches your saved “\(nearest.label)” (\(shown))."
            : "Closest saved flavour is “\(nearest.label)” (\(shown)) — similar, but probably not the same."
    }
}

struct SortTips: View {
    private let steps = [
        "Spread the look-alike beans on plain white printer paper, one layer, not touching. Fill the frame with the paper. Any colour family works — reds, yellows, greens, the dark ones.",
        "White, cream or very pale beans don’t show up against white. Put those on a dark sheet with a strip of white paper showing at the edge — a black or navy origami sheet, or the printable sorting mat (the printer button above).",
        "Shoot straight down. No flash; keep your shadow off the sheet.",
        "Every bean comes back lettered by group. Taste one bean per group to name it, then save the group as a flavour.",
        "More than three or four flavours in one pile? Split it in two, then shoot each half on its own and split again — small differences show up better once the big ones are out of the frame.",
    ]

    var body: some View {
        Card {
            Text("Sort look-alike beans").font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Theme.ink, in: .circle)
                    Text(step).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
