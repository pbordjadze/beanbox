import BeanCore
import CoreGraphics
import Foundation
import Observation

/// Everything measured so far: photos, the colours tapped in them, and which sheet is locked
/// to which flavour. Saved as one small JSON file beside the photos' original files.
///
///     <root>/project.json
///     <root>/photos/<uuid>   the photo exactly as it was picked or taken
@Observable
final class Project {
    private(set) var data = ProjectData()
    /// The photo each tab is working on. Not saved.
    var focus: [AppTab: UUID] = [:]
    /// Small previews for the photo strip, filled in as they are decoded.
    private(set) var thumbnails: [UUID: CGImage] = [:]
    /// A photo is being added.
    private(set) var isImporting = false
    /// The last thing that went wrong, in words for the user; cleared by the next success.
    var problem: String?

    private let root: URL
    @ObservationIgnored private var recent: [(id: UUID, photo: LoadedPhoto)] = []

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Project", directoryHint: .isDirectory)
    }

    static func forLaunch() -> Project {
        #if DEBUG
        if DemoMode.isActive {
            // A demo keeps no state between runs.
            let scratch = FileManager.default.temporaryDirectory.appending(path: "demo-project", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: scratch)
            return Project(root: scratch)
        }
        #endif
        return Project(root: defaultRoot)
    }

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        if let saved = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(ProjectData.self, from: saved) {
                data = decoded
            } else {
                // Never start over on top of a file this build can't read: the next save
                // would replace it. Set it aside, where a later build can still find it.
                let aside = root.appending(path: "project-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: fileURL, to: aside)
                problem = "Your saved measurements couldn’t be read, so this starts empty. The old file was kept."
            }
        }
        let urls = data.photos.map { ($0.id, url(of: $0.id)) }
        Task { [weak self] in
            for (id, url) in urls {
                guard let thumbnail = await Project.thumbnail(url) else { continue }
                self?.thumbnails[id] = thumbnail
            }
        }
    }

    private var fileURL: URL { root.appending(path: "project.json") }
    private var photosDirectory: URL { root.appending(path: "photos", directoryHint: .isDirectory) }
    private func url(of photo: UUID) -> URL { photosDirectory.appending(path: photo.uuidString) }

    private func save() {
        do {
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch {
            problem = "Couldn’t save your measurements: \(error.localizedDescription)"
        }
    }

    // MARK: Reading

    var papers: [SampleRecord] { data.samples.filter { $0.kind == .paper } }
    var beans: [SampleRecord] { data.samples.filter { $0.kind == .bean } }

    func samples(_ kind: SampleRecord.Kind) -> [SampleRecord] { data.samples.filter { $0.kind == kind } }

    func photo(_ id: UUID?) -> PhotoRecord? {
        guard let id else { return nil }
        return data.photos.first { $0.id == id }
    }

    func sample(_ id: UUID) -> SampleRecord? { data.samples.first { $0.id == id } }

    /// Bean samples grouped by name; a flavour's colour is the mean of its samples.
    var flavors: [Matching.Flavor] {
        var order: [String] = []
        var groups: [String: [SampleRecord]] = [:]
        for sample in beans {
            let key = Matching.flavorKey(sample.label)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(sample)
        }
        return order.map { key in
            let members = groups[key]!
            let mean = members.reduce(Lab(repeating: 0)) { $0 + $1.lab } / Double(members.count)
            return Matching.Flavor(key: key, label: members[0].label, lab: mean, sampleCount: members.count)
        }
    }

    /// The best sheet for every flavour, in rainbow order with near-neutrals (white → black)
    /// last.
    var matchRows: [Matching.Row] {
        let sheets = papers.map { Matching.Paper(id: $0.id, label: $0.label, lab: $0.lab, available: $0.available) }
        func hueOrder(_ lab: Lab) -> (Int, Double) {
            if hypot(lab.y, lab.z) < 10 { return (1, -lab.x) }
            let hue = atan2(lab.z, lab.y) * 180 / .pi
            return (0, hue < 0 ? hue + 360 : hue)
        }
        return Matching.solve(flavors: flavors, papers: sheets, locks: data.locks)
            .sorted { hueOrder($0.flavor.lab) < hueOrder($1.flavor.lab) }
    }

    // MARK: Photos

    /// The decoded photo, from the last couple used or freshly decoded off the main thread.
    func loaded(_ photo: PhotoRecord) async -> LoadedPhoto? {
        if let hit = recent.first(where: { $0.id == photo.id }) { return hit.photo }
        guard let fresh = try? await Self.decode(url(of: photo.id)) else {
            problem = "That photo’s file can’t be read any more."
            return nil
        }
        remember(photo.id, fresh)
        return fresh
    }

    private func remember(_ id: UUID, _ photo: LoadedPhoto) {
        recent.removeAll { $0.id == id }
        recent.insert((id, photo), at: 0)
        // Two is enough to flip between tabs without re-decoding; each is ~8 MB.
        if recent.count > 2 { recent.removeLast() }
    }

    /// Adds a photo from its file data and makes it the one `tab` is working on.
    @discardableResult
    func addPhoto(_ fileData: Data, for tab: AppTab) async -> PhotoRecord? {
        isImporting = true
        defer { isImporting = false }
        guard let imported = try? await Self.importPhoto(fileData) else {
            problem = "That file isn’t a photo this app can read."
            return nil
        }
        let white = automaticWhite(imported.white, for: imported.photo.pixels, at: Date(), excluding: nil)
        let record = PhotoRecord(
            width: imported.photo.pixels.width, height: imported.photo.pixels.height,
            white: white.xyz, whiteAt: nil, whiteClipped: imported.white.clipped, whiteBasis: white.basis)
        do {
            try fileData.write(to: url(of: record.id), options: .atomic)
        } catch {
            problem = "Couldn’t keep that photo: \(error.localizedDescription)"
            return nil
        }
        remember(record.id, imported.photo)
        thumbnails[record.id] = imported.thumbnail
        data.photos.append(record)
        focus[tab] = record.id
        problem = nil
        save()
        return record
    }

    /// How long a photo's white stays good for the photos after it: about one sitting.
    private static let sameSitting: TimeInterval = 2 * 60 * 60

    /// The white for a photo nobody has tapped: what was found in it; failing that, the
    /// white of the last photo that had one, if it was added in the same sitting (same
    /// light, presumably); failing that, the camera's own balance.
    private func automaticWhite(
        _ guess: Sampling.White, for pixels: PixelImage, at date: Date, excluding photo: UUID?
    ) -> (xyz: XYZ, basis: WhiteBasis) {
        if guess.found { return (guess.xyz, .found) }
        let reference = data.photos
            .filter { $0.id != photo && $0.basis.isMeasured && $0.created <= date && date.timeIntervalSince($0.created) < Self.sameSitting }
            .max { $0.created < $1.created }
        if let reference { return (Sampling.borrowedWhite(for: pixels, from: reference.white), .borrowed) }
        return (guess.xyz, .camera)
    }

    /// Deletes a photo. Colours already measured from it are kept.
    func deletePhoto(_ id: UUID) {
        data.photos.removeAll { $0.id == id }
        for i in data.samples.indices where data.samples[i].photoID == id {
            data.samples[i].photoID = nil
            data.samples[i].tap = nil
        }
        for (tab, focused) in focus where focused == id { focus[tab] = nil }
        recent.removeAll { $0.id == id }
        thumbnails[id] = nil
        try? FileManager.default.removeItem(at: url(of: id))
        save()
    }

    /// Re-references a photo's white — to the tap at `point`, or back to the automatic guess
    /// when nil — and re-measures every colour tapped in it.
    func setWhite(of id: UUID, pixels: PixelImage, at point: CGPoint?, radius: Double) {
        guard let index = data.photos.firstIndex(where: { $0.id == id }) else { return }
        let white: XYZ
        if let point {
            guard let tapped = Sampling.white(in: pixels, x: point.x, y: point.y, r: radius) else { return }
            white = tapped.xyz
            data.photos[index].whiteAt = SIMD2(point.x, point.y)
            data.photos[index].whiteClipped = tapped.clipped
            data.photos[index].whiteBasis = .tapped
        } else {
            let guess = Sampling.autoWhite(pixels)
            let automatic = automaticWhite(guess, for: pixels, at: data.photos[index].created, excluding: id)
            white = automatic.xyz
            data.photos[index].whiteAt = nil
            data.photos[index].whiteClipped = guess.clipped
            data.photos[index].whiteBasis = automatic.basis
        }
        data.photos[index].white = white
        for i in data.samples.indices where data.samples[i].photoID == id {
            guard let tap = data.samples[i].tap,
                  let lab = Sampling.sample(pixels, white: white, x: tap.x, y: tap.y, r: tap.r) else { continue }
            data.samples[i].lab = lab
        }
        save()
    }

    // MARK: Samples

    /// The next "#N" (paper) or "Bean N": one past the highest in use, so deleting a mis-tap
    /// frees its number but never renumbers a sheet.
    private func nextLabel(_ kind: SampleRecord.Kind) -> String {
        let prefix = kind == .paper ? "#" : "Bean "
        let taken = samples(kind).filter { $0.label.hasPrefix(prefix) }.compactMap { Int($0.label.dropFirst(prefix.count)) }
        return "\(prefix)\((taken.max() ?? 0) + 1)"
    }

    /// Measures the colour under a tap and saves it.
    @discardableResult
    func addSample(_ kind: SampleRecord.Kind, in photo: PhotoRecord, pixels: PixelImage, at point: CGPoint, radius: Double, label: String?) -> SampleRecord? {
        guard let lab = Sampling.sample(pixels, white: photo.white, x: point.x, y: point.y, r: radius) else { return nil }
        let sample = SampleRecord(
            kind: kind, label: label ?? nextLabel(kind), photoID: photo.id,
            tap: SampleRecord.Tap(x: point.x, y: point.y, r: radius), lab: lab)
        data.samples.append(sample)
        save()
        return sample
    }

    /// Saves a sorted group's colour as a bean flavour.
    func addFlavor(named label: String, lab: Lab, from photo: UUID) {
        data.samples.append(SampleRecord(kind: .bean, label: label, photoID: photo, tap: nil, lab: lab))
        save()
    }

    func rename(_ id: UUID, to label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = data.samples.firstIndex(where: { $0.id == id }) else { return }
        let old = data.samples[index]
        guard old.label != trimmed else { return }
        data.samples[index].label = trimmed
        if old.kind == .bean { moveLock(from: Matching.flavorKey(old.label), to: Matching.flavorKey(trimmed)) }
        save()
    }

    /// Carries a flavour's lock across a rename of its last sample.
    private func moveLock(from old: String, to new: String) {
        guard old != new, let sheet = data.locks[old] else { return }
        guard !beans.contains(where: { Matching.flavorKey($0.label) == old }) else { return }
        data.locks[old] = nil
        if data.locks[new] == nil { data.locks[new] = sheet }
    }

    func setAvailable(_ id: UUID, _ available: Bool) {
        guard let index = data.samples.firstIndex(where: { $0.id == id }) else { return }
        data.samples[index].available = available
        save()
    }

    func deleteSample(_ id: UUID) {
        data.samples.removeAll { $0.id == id }
        data.locks = data.locks.filter { $0.value != id }
        save()
    }

    /// Locks a flavour to a sheet, or unlocks it when `paper` is nil. A sheet can only be one
    /// flavour's box.
    func setLock(flavor key: String, paper: UUID?) {
        data.locks[key] = nil
        if let paper {
            data.locks = data.locks.filter { $0.value != paper }
            data.locks[key] = paper
        }
        save()
    }

    // MARK: Background work

    private nonisolated struct Imported: Sendable {
        var photo: LoadedPhoto
        var white: Sampling.White
        var thumbnail: CGImage?
    }

    @concurrent
    private static func importPhoto(_ data: Data) async throws -> Imported {
        let photo = try PhotoLoader.load(data: data)
        return Imported(photo: photo, white: Sampling.autoWhite(photo.pixels), thumbnail: Self.small(photo.image))
    }

    @concurrent
    private static func decode(_ url: URL) async throws -> LoadedPhoto {
        try PhotoLoader.load(url: url)
    }

    @concurrent
    private static func thumbnail(_ url: URL) async -> CGImage? {
        PhotoLoader.thumbnail(url: url, maxPixelSize: 200)
    }

    /// A 200-px copy for the photo strip.
    nonisolated private static func small(_ image: CGImage) -> CGImage? {
        let scale = 200 / Double(max(image.width, image.height))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    /// Runs the sorter on a photo, off the main thread. The photo's white only matters when
    /// the beans aren't on white paper: a tapped one is used as is, a borrowed one stands in
    /// when the shot turns out to have no white of its own.
    @concurrent
    static func sort(_ pixels: PixelImage, white: XYZ, basis: WhiteBasis) async -> Sorting.Analysis? {
        try? Sorting.analyze(
            pixels, tappedWhite: basis == .tapped ? white : nil, fallbackWhite: basis == .borrowed ? white : nil)
    }
}
