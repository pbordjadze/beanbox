import BeanCore
import Foundation

/// A photo the user added. Its pixels are kept as the original file; this is what was learned
/// from them.
nonisolated struct PhotoRecord: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var created = Date()
    /// Size of the working image (long edge ≤ `PhotoLoader.maxPixelSize`). Taps are in these pixels.
    var width: Int
    var height: Int
    /// The white every colour in this photo is measured against.
    var white: XYZ
    /// Where the user tapped to set that white; nil while the automatic guess is in use.
    var whiteAt: SIMD2<Double>?
    /// The white was overexposed: colours from this photo read too pale.
    var whiteClipped: Bool
    /// Where `white` came from. Nil in photos saved before this was recorded: tapped if
    /// `whiteAt` is set, found in the photo otherwise.
    var whiteBasis: WhiteBasis?

    var basis: WhiteBasis { whiteBasis ?? (whiteAt == nil ? .found : .tapped) }
}

/// Where a photo's white came from, best first.
nonisolated enum WhiteBasis: String, Codable, Sendable {
    /// The user tapped something white.
    case tapped
    /// The brightest neutral surface in the photo.
    case found
    /// Nothing white in the photo: the white of the photo added just before it.
    case borrowed
    /// Nothing white, and no recent photo to borrow from: the camera's own balance.
    case camera

    /// Measured against something white in this very photo.
    var isMeasured: Bool { self == .tapped || self == .found }
}

/// One measured colour: a sheet of paper or a bean flavour.
nonisolated struct SampleRecord: Codable, Identifiable, Sendable, Equatable {
    nonisolated enum Kind: String, Codable, Sendable {
        case paper, bean
    }

    nonisolated struct Tap: Codable, Sendable, Equatable {
        var x, y, r: Double
    }

    var id = UUID()
    var kind: Kind
    var label: String
    var photoID: UUID?
    /// Where it was measured, in photo pixels; nil for a colour saved from a sorted group.
    var tap: Tap?
    var lab: Lab
    /// Papers only: false once the sheet is used up or ruined.
    var available = true
    var created = Date()
}

/// Everything the app saves (`project.json`). Never rename a field, and add new ones as
/// optionals: the synthesized decoder has no defaults, so a required field that an older
/// file lacks makes the whole file unreadable.
nonisolated struct ProjectData: Codable, Sendable, Equatable {
    var version = 1
    var photos: [PhotoRecord] = []
    var samples: [SampleRecord] = []
    /// Flavour key → the sheet it is locked to (how an already-folded box is recorded).
    var locks: [String: UUID] = [:]
}

nonisolated enum AppTab: String, Hashable, Sendable {
    case papers, beans, match, sort
}

nonisolated enum SampleSize: String, CaseIterable, Identifiable, Sendable {
    case small = "S", medium = "M", large = "L"

    var id: String { rawValue }

    /// Sampling radius as a fraction of the photo's long edge.
    var fraction: Double {
        switch self {
        case .small: 0.006
        case .medium: 0.012
        case .large: 0.025
        }
    }
}
