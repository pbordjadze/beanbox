import Foundation

/// Measuring colours at points of a photo.
public enum Sampling {
    /// A white reference this close to 255 has lost its colour cast to clipping, so balancing
    /// against it under-corrects.
    static let clipLevel = 250.0
    /// Unbalanced chroma below which a bright pixel could plausibly be white paper. Warm
    /// indoor light puts real white around 10–25; coloured paper is 50 and up.
    static let neutralChromaLimit = 30.0
    /// Pixels further than this (Lab units) from the tap's centre colour belong to something
    /// else — the table, a neighbouring bean — and are ignored.
    static let sameObjectRadius = 30.0

    public struct White: Sendable, Equatable {
        public var xyz: XYZ
        /// The reference was overexposed; colours measured against it read too pale.
        public var clipped: Bool
        /// False when nothing in the photo could pass for white. `xyz` is then the camera's own
        /// idea of white (`cameraWhite`), and colours are only as good as its balance.
        public var found: Bool

        public init(xyz: XYZ, clipped: Bool, found: Bool = true) {
            self.xyz = xyz
            self.clipped = clipped
            self.found = found
        }
    }

    /// Where a camera puts white paper in a normally exposed photo, in linear light (the
    /// one real iPhone shot measured had it at 0.79). The camera's white is never taken to be
    /// dimmer than this, or the brightest thing in a scene of dark beans would read as white.
    static let cameraWhiteFloor = 0.75

    /// Chroma with brightness divided out: how far from neutral a colour's hue is, regardless
    /// of how light it is.
    static func neutralChroma(of xyz: XYZ) -> Double {
        let lab = ColorScience.lab(fromXYZ: xyz / max(xyz.y, 1e-4))
        return hypot(lab.y, lab.z)
    }

    private static func white(from pixels: [SIMD3<UInt8>], space: RGBSpace) -> White {
        let m = ColorScience.toXYZ(space)
        let t = ColorScience.decodeTable
        let xyz = pixels.map { m * SIMD3(t[Int($0.x)], t[Int($0.y)], t[Int($0.z)]) }
        let brightest = [
            Stats.median(pixels.map { Double($0.x) }),
            Stats.median(pixels.map { Double($0.y) }),
            Stats.median(pixels.map { Double($0.z) }),
        ].max()!
        return White(xyz: Stats.median(xyz), clipped: brightest >= clipLevel)
    }

    /// Guesses the white reference: the brightest sizeable near-neutral surface in the shot.
    ///
    /// Near-neutral, so a sheet of yellow paper that happens to be brighter than the white one
    /// isn't taken for white. "Brightest" runs from the 98th percentile (skipping specular
    /// glints) down to 20 % below it, rather than being a fixed share of the pixels, so a strip
    /// of white paper beside a large dark sheet is still found.
    ///
    /// A photo doesn't have to contain anything white. The neutral surface must be among the
    /// brightest things in the frame (a grey table under bright paper is not white), and
    /// cover enough of it; otherwise the result is the camera's own white, marked not `found`.
    public static func autoWhite(_ image: PixelImage) -> White {
        let m = ColorScience.toXYZ(image.space)
        let t = ColorScience.decodeTable
        var pixels: [SIMD3<UInt8>] = []
        var luminance: [Double] = []
        var neutral: [Bool] = []
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let i = (y * image.width + x) * 4
                let p = SIMD3(image.rgba[i], image.rgba[i + 1], image.rgba[i + 2])
                let xyz = m * SIMD3(t[Int(p.x)], t[Int(p.y)], t[Int(p.z)])
                pixels.append(p)
                luminance.append(xyz.y)
                neutral.append(neutralChroma(of: xyz) < neutralChromaLimit)
            }
        }
        let brightest = Stats.percentile(luminance.sorted(), 98)
        let candidates = luminance.indices.filter { neutral[$0] && luminance[$0] >= 0.5 * brightest }
        guard Double(candidates.count) >= 0.03 * Double(luminance.count) else {
            return White(xyz: cameraWhite(brightest: brightest), clipped: false, found: false)
        }
        let top = Stats.percentile(candidates.map { luminance[$0] }.sorted(), 98)
        let band = candidates.filter { luminance[$0] >= 0.8 * top && luminance[$0] <= top }
        return white(from: band.map { pixels[$0] }, space: image.space)
    }

    /// White as the camera rendered the scene: its own colour balance, at the level of the
    /// brightest thing in the frame (`brightest`, linear luminance) or of a normally exposed
    /// white if the scene is dimmer than that.
    static func cameraWhite(brightest: Double) -> XYZ {
        ColorScience.d65 * min(max(brightest, cameraWhiteFloor), 1)
    }

    /// For a photo with no white of its own: the white of another photo taken just before
    /// under the same light, raised if this photo has something brighter than it.
    public static func borrowedWhite(for image: PixelImage, from reference: XYZ) -> XYZ {
        let m = ColorScience.toXYZ(image.space)
        let t = ColorScience.decodeTable
        var luminance: [Double] = []
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let i = (y * image.width + x) * 4
                luminance.append((m * SIMD3(t[Int(image.rgba[i])], t[Int(image.rgba[i + 1])], t[Int(image.rgba[i + 2])])).y)
            }
        }
        let brightest = min(Stats.percentile(luminance.sorted(), 98), 1)
        return reference * (max(reference.y, brightest) / reference.y)
    }

    /// Pixels within `r` of `(x, y)` and their distances from that centre.
    private static func disc(_ image: PixelImage, x: Double, y: Double, r: Double) -> [(pixel: SIMD3<UInt8>, distance: Double)] {
        let x0 = max(0, Int(x - r)), x1 = min(image.width, Int(x + r) + 1)
        let y0 = max(0, Int(y - r)), y1 = min(image.height, Int(y + r) + 1)
        var out: [(SIMD3<UInt8>, Double)] = []
        guard x0 < x1, y0 < y1 else { return out }
        for yy in y0..<y1 {
            for xx in x0..<x1 {
                let d = hypot(Double(xx) - x, Double(yy) - y)
                guard d <= r else { continue }
                let i = (yy * image.width + xx) * 4
                out.append((SIMD3(image.rgba[i], image.rgba[i + 1], image.rgba[i + 2]), d))
            }
        }
        return out
    }

    /// The white reference under a tap. Nil when the tap is outside the photo.
    public static func white(in image: PixelImage, x: Double, y: Double, r: Double) -> White? {
        let pixels = disc(image, x: x, y: y, r: r).map(\.pixel)
        return pixels.isEmpty ? nil : white(from: pixels, space: image.space)
    }

    /// Representative colour of a glossy object's pixels: drops the brightest and darkest 15 %
    /// (specular glints, contact shadow) and takes the per-channel median of the rest.
    static func bodyColor(_ lab: [Lab]) -> Lab {
        guard lab.count >= 8 else { return Stats.median(lab) }
        let lightness = lab.map(\.x).sorted()
        let lo = Stats.percentile(lightness, 15), hi = Stats.percentile(lightness, 85)
        return Stats.median(lab.filter { $0.x >= lo && $0.x <= hi })
    }

    /// Lab colour of whatever is under a tap at `(x, y)`, measured against `white`. Nil when
    /// the tap is outside the photo.
    public static func sample(_ image: PixelImage, white: XYZ, x: Double, y: Double, r: Double) -> Lab? {
        let pixels = disc(image, x: x, y: y, r: r)
        guard !pixels.isEmpty else { return nil }
        let m = ColorScience.adaptMatrix(white: white) * ColorScience.toXYZ(image.space)
        let t = ColorScience.decodeTable
        let lab = pixels.map { ColorScience.lab(fromXYZ: m * SIMD3(t[Int($0.pixel.x)], t[Int($0.pixel.y)], t[Int($0.pixel.z)])) }
        let coreRadius = max(1.5, r * 0.4)
        let core = zip(lab, pixels).filter { $0.1.distance <= coreRadius }.map(\.0)
        guard !core.isEmpty else { return bodyColor(lab) }
        let centre = Stats.median(core)
        let same = lab.filter {
            let d = $0 - centre
            return (d * d).sum().squareRoot() < sameObjectRadius
        }
        return bodyColor(same.count >= 8 ? same : lab)
    }
}
