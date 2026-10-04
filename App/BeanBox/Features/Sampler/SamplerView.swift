import BeanCore
import SwiftUI

/// Measuring colours by tapping them in a photo: sheets of paper in the Papers tab, bean
/// flavours in the Beans tab.
struct SamplerView: View {
    let kind: SampleRecord.Kind
    @Environment(Project.self) private var project
    @State private var loaded: LoadedPhoto?
    /// The next tap sets the photo's white instead of measuring a colour.
    @State private var isSettingWhite = false
    @State private var size = SampleSize.medium
    @State private var zoom: CGFloat = 1
    @State private var name = ""
    @State private var editing: SampleRecord?
    @State private var isShowingTips = false
    @FocusState private var isNaming: Bool

    private var tab: AppTab { kind == .paper ? .papers : .beans }
    private var photo: PhotoRecord? { project.photo(project.focus[tab]) }
    private var samples: [SampleRecord] { project.samples(kind) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 14) {
                        if samples.isEmpty && photo == nil { Tips(kind: kind) }
                        Card {
                            PhotoStrip(tab: tab)
                            if let photo, let loaded { canvas(photo, loaded) }
                        }
                        if !samples.isEmpty { swatches.id("swatches") }
                    }
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: samples.count) {
                    // A demo scenario can ask for the measured swatches to be in view.
                    if Launch.shows("swatches") { scroller.scrollTo("swatches", anchor: .top) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.plane)
            .navigationTitle(kind == .paper ? "Papers" : "Beans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tips", systemImage: "questionmark.circle") { isShowingTips = true }
                }
            }
            .sheet(isPresented: $isShowingTips) {
                NavigationStack {
                    ScrollView { Tips(kind: kind).padding() }
                        .background(Theme.plane)
                        .navigationTitle("Getting a good reading")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingTips = false } } }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editing) { sample in
                SampleEditor(sampleID: sample.id)
                    .presentationDetents([.medium])
            }
            .task(id: photo?.id) {
                loaded = nil
                guard let photo else { return }
                loaded = await project.loaded(photo)
                // A fresh photo that has something white in it starts by asking for a tap on
                // it: one tap, and every colour is measured against the real thing rather than
                // a guess. A photo with nothing white has nothing to ask for.
                isSettingWhite = photo.basis == .found && !project.data.samples.contains { $0.photoID == photo.id }
            }
            .onChange(of: photo?.whiteAt) { _, white in
                // However the white got set, the prompt for it has been answered.
                if white != nil { isSettingWhite = false }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: project.data.samples.count)
        }
    }

    // MARK: Photo

    @ViewBuilder
    private func canvas(_ photo: PhotoRecord, _ loaded: LoadedPhoto) -> some View {
        if isSettingWhite {
            HStack(alignment: .firstTextBaseline) {
                Text("**Tap something white** in this photo if there is any — paper is best — so colours are measured against it.")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Button(photo.whiteAt == nil ? "None" : "Cancel") { isSettingWhite = false }
                    .font(.subheadline)
            }
            .padding(10)
            .background(Theme.plane, in: .rect(cornerRadius: 10))
        } else if kind == .bean {
            nameField
        }
        if photo.whiteClipped {
            Label("The white in this photo is blown out, so colours will read paler than they are. Retake it a little darker.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        PhotoCanvas(image: loaded.image, zoom: zoom) { point in
            tapped(point, photo, loaded)
        } annotate: { context, scale in
            annotate(&context, scale, photo)
        }
        .accessibilityLabel(kind == .paper ? "Photo of the paper. Tap a sheet to measure it." : "Photo of the beans. Tap a bean to measure it.")
        HStack {
            Picker("Sample size", selection: $size) {
                ForEach(SampleSize.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 130)
            Picker("Zoom", selection: $zoom) {
                ForEach([1, 2, 3], id: \.self) { Text("\($0)×").tag(CGFloat($0)) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 130)
            Spacer()
            Menu("White", systemImage: "circle.lefthalf.filled") {
                Button("Tap Something White", systemImage: "hand.tap") { isSettingWhite = true }
                if photo.whiteAt != nil {
                    Button("Guess Automatically", systemImage: "wand.and.stars") {
                        project.setWhite(of: photo.id, pixels: loaded.pixels, at: nil, radius: 0)
                    }
                }
            }
            .font(.subheadline)
        }
        Text(whiteNote(photo.basis))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// What this photo's colours are measured against, and what to do if that looks wrong.
    private func whiteNote(_ basis: WhiteBasis) -> String {
        switch basis {
        case .tapped:
            "White: where you tapped (the square on the photo)."
        case .found:
            "White: the brightest neutral area, found automatically. If the swatches look tinted, tap something white."
        case .borrowed:
            "Nothing white in this photo, so it uses the white from your previous one. That holds while the light hasn’t changed."
        case .camera:
            "Nothing white in this photo, so colours are as the camera saw them — a little warm under indoor light. They still compare well with other photos taken the same way."
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Flavour for the next tap", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($isNaming)
                .submitLabel(.done)
            if isNaming {
                FlavorSuggestions(text: $name) { isNaming = false }
            }
        }
    }

    private func tapped(_ point: CGPoint, _ photo: PhotoRecord, _ loaded: LoadedPhoto) {
        let radius = size.fraction * Double(max(photo.width, photo.height))
        if isSettingWhite {
            project.setWhite(of: photo.id, pixels: loaded.pixels, at: point, radius: radius)
            isSettingWhite = false
        } else {
            let label = name.trimmingCharacters(in: .whitespaces)
            project.addSample(kind, in: photo, pixels: loaded.pixels, at: point, radius: radius, label: kind == .bean && !label.isEmpty ? label : nil)
            name = ""
            isNaming = false
        }
    }

    private func annotate(_ context: inout GraphicsContext, _ scale: Double, _ photo: PhotoRecord) {
        if let white = photo.whiteAt {
            let side = 16.0
            let box = CGRect(x: white.x * scale - side / 2, y: white.y * scale - side / 2, width: side, height: side)
            Marks.ring(&context, Path(box), color: .white, width: 2)
            Marks.tag(&context, "white", at: CGPoint(x: box.midX, y: box.minY - 11))
        }
        // Both kinds are marked: beans and paper measured in the same shot are the most
        // trustworthy comparison there is. This tab's own are drawn last, on top.
        let here = project.data.samples.filter { $0.photoID == photo.id && $0.tap != nil }
        for sample in here where sample.kind != kind {
            guard let tap = sample.tap else { continue }
            Marks.ring(&context, ring(tap, scale), color: .white.opacity(0.6), width: 1.5)
        }
        // Flavour names are long: neighbours along a row take turns above and below their
        // rings so they don't run into each other.
        let mine = here.filter { $0.kind == kind }.sorted { ($0.tap?.x ?? 0) < ($1.tap?.x ?? 0) }
        for (index, sample) in mine.enumerated() {
            guard let tap = sample.tap else { continue }
            Marks.ring(&context, ring(tap, scale), color: .white, width: 2)
            let radius = max(tap.r * scale, 5)
            let below = kind == .bean && index % 2 == 1
            let name = sample.label.count > 16 ? String(sample.label.prefix(15)) + "…" : sample.label
            Marks.tag(
                &context, name, at: CGPoint(x: tap.x * scale, y: tap.y * scale + (below ? radius + 10 : -radius - 10)),
                size: kind == .paper ? 11 : 10)
        }
    }

    private func ring(_ tap: SampleRecord.Tap, _ scale: Double) -> Path {
        let radius = max(tap.r * scale, 5)
        return Path(ellipseIn: CGRect(x: tap.x * scale - radius, y: tap.y * scale - radius, width: 2 * radius, height: 2 * radius))
    }

    // MARK: Swatches

    private var swatches: some View {
        Card {
            Text(kind == .paper ? "\(samples.count) sheets measured" : "\(project.flavors.count) flavours measured")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 10)], spacing: 12) {
                ForEach(samples) { sample in
                    Button {
                        editing = sample
                    } label: {
                        VStack(spacing: 4) {
                            Swatch(lab: sample.lab)
                                .frame(height: 46)
                                .opacity(sample.available ? 1 : 0.35)
                            Text(sample.label)
                                .font(.caption2)
                                .lineLimit(1)
                                .strikethrough(!sample.available)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sample.label)
                }
            }
        }
    }
}

/// Tappable flavour names matching what has been typed.
struct FlavorSuggestions: View {
    @Binding var text: String
    var onChoose: () -> Void = {}
    @Environment(Project.self) private var project

    var body: some View {
        let measured = Set(project.beans.map { $0.label.lowercased() })
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Flavors.suggestions(for: text, measured: measured).prefix(12), id: \.self) { flavor in
                    Button(flavor) {
                        text = flavor
                        onChoose()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .foregroundStyle(measured.contains(flavor.lowercased()) ? .secondary : .primary)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Rename, retire or delete one measured colour.
struct SampleEditor: View {
    let sampleID: UUID
    @Environment(Project.self) private var project
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @FocusState private var isNaming: Bool

    var body: some View {
        NavigationStack {
            if let sample = project.sample(sampleID) {
                Form {
                    Section {
                        HStack(spacing: 14) {
                            Swatch(lab: sample.lab, corner: 12).frame(width: 72, height: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                TextField(sample.kind == .paper ? "Sheet number" : "Flavour", text: $label)
                                    .font(.title3.weight(.semibold))
                                    .autocorrectionDisabled()
                                    .focused($isNaming)
                                    .submitLabel(.done)
                                    .onSubmit { project.rename(sampleID, to: label) }
                                Text("L \(sample.lab.x, format: .number.precision(.fractionLength(1)))  a \(sample.lab.y, format: .number.precision(.fractionLength(1)))  b \(sample.lab.z, format: .number.precision(.fractionLength(1)))")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if sample.kind == .bean && isNaming {
                            FlavorSuggestions(text: $label) {
                                project.rename(sampleID, to: label)
                                isNaming = false
                            }
                        }
                    }
                    if sample.kind == .paper {
                        Section {
                            Toggle("Used up", isOn: Binding(get: { !sample.available }, set: { project.setAvailable(sampleID, !$0) }))
                        } footer: {
                            Text("A used-up sheet is never suggested for a flavour, unless it is locked to one.")
                        }
                    }
                    Section {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            project.deleteSample(sampleID)
                            dismiss()
                        }
                    }
                }
                .navigationTitle(sample.kind == .paper ? "Sheet" : "Flavour")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            project.rename(sampleID, to: label)
                            dismiss()
                        }
                    }
                }
                .onAppear { label = sample.label }
            }
        }
    }
}

/// How to shoot for a trustworthy colour.
struct Tips: View {
    let kind: SampleRecord.Kind

    private var steps: [String] {
        switch kind {
        case .paper:
            [
                "Fan a few sheets out so a strip of each shows. No flash, and keep your own shadow off them.",
                "Something white in the shot — printer paper under the sheets is ideal — makes the colours more accurate: tap it once when asked. Without any, the app carries on with the white from your previous photo, or the camera’s own.",
                "Then tap each sheet. Every tap becomes the next number — pencil that number on the sheet’s corner so you can find it again.",
                "Shoot the beans in the same spot under the same light. Daylight by a window beats a warm lamp.",
            ]
        case .bean:
            [
                "Photograph the beans in the same spot and light you used for the paper — on white paper if you can, though any surface works.",
                "Type the flavour, then tap the bean. Leave the name blank to save it as “Bean 1” and name it later.",
                "Tapping the same flavour again averages the readings. Flavours you can’t tell apart by eye? Split them in the Sort tab first.",
            ]
        }
    }

    var body: some View {
        Card {
            Text(kind == .paper ? "Measure the paper" : "Measure the beans")
                .font(.headline)
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
