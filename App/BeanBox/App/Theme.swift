import BeanCore
import SwiftUI

/// Shared visual language. Deliberately neutral: greys and ink only, so the only colours on
/// screen are the measured ones.
enum Theme {
    static let ink = Color(red: 0.043, green: 0.043, blue: 0.043)
    /// Screen background: a light neutral grey that neither warms nor cools the swatches on it.
    static let plane = Color(red: 0.93, green: 0.93, blue: 0.925)
    static let surface = Color(red: 0.988, green: 0.988, blue: 0.984)
    static let hairline = Color.black.opacity(0.1)
    static let cardRadius: CGFloat = 18

    struct GroupStyle {
        let color: Color
        /// Light fills take ink lettering instead of white.
        let isLight: Bool
    }

    /// Group identity colours, in fixed order (group A is always blue): six hues from the
    /// dataviz reference palette that validate for all-pairs use, where any group can sit next
    /// to any other. The beans can be any colour, so a ring will sometimes match the beans it
    /// surrounds — which is why every ring has a contrasting casing, sits just outside the
    /// bean, and is always paired with the group letter. The sixth only clears the
    /// colour-blind floor with that second cue. One per `Sorting.maxGroups`.
    static let groups: [GroupStyle] = [
        GroupStyle(color: Color(red: 0.165, green: 0.471, blue: 0.839), isLight: false),
        GroupStyle(color: Color(red: 0.929, green: 0.631, blue: 0.000), isLight: true),
        GroupStyle(color: Color(red: 0.106, green: 0.686, blue: 0.478), isLight: true),
        GroupStyle(color: Color(red: 0.290, green: 0.227, blue: 0.655), isLight: false),
        GroupStyle(color: Color(red: 0.000, green: 0.514, blue: 0.000), isLight: false),
        GroupStyle(color: Color(red: 0.910, green: 0.482, blue: 0.643), isLight: true),
    ]
    static let letters = ["A", "B", "C", "D", "E", "F"]
}

extension Color {
    /// The nearest displayable colour to a measured Lab value, in Display P3 so saturated
    /// beans aren't flattened to what sRGB can show.
    init(lab: Lab) {
        let c = ColorScience.display(lab, in: .displayP3)
        self.init(.displayP3, red: c.x, green: c.y, blue: c.z)
    }
}

/// A card on the neutral plane.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.hairline) }
    }
}

/// A flat patch of a measured colour.
struct Swatch: View {
    let lab: Lab
    var corner: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Color(lab: lab))
            .overlay { RoundedRectangle(cornerRadius: corner).strokeBorder(Theme.hairline) }
            .accessibilityHidden(true)
    }
}

/// The lettered disc that names a group, beside its text everywhere a group is mentioned.
struct GroupChip: View {
    let group: Int

    var body: some View {
        Text(Theme.letters[group])
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.groups[group].isLight ? Theme.ink : .white)
            .frame(width: 28, height: 28)
            .background(Theme.groups[group].color, in: .circle)
            .accessibilityLabel("Group \(Theme.letters[group])")
    }
}

/// Plain-language reading of a colour difference.
nonisolated enum Verdict {
    /// For a bean-versus-paper ΔE (lightness half-weighted).
    static func match(_ deltaE: Double) -> String {
        switch deltaE {
        case ...2: "near-identical"
        case ...5: "close"
        case ...10: "noticeably off"
        default: "poor"
        }
    }

    /// For the ΔE between the two closest groups of a sort.
    static func separation(_ deltaE: Double) -> String {
        switch deltaE {
        case ..<2: "too close to trust"
        case ..<4: "subtle but measurable"
        case ..<8: "clear"
        default: "obvious"
        }
    }
}
