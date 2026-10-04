import Foundation
@testable import BeanCore

/// Deterministic random numbers for synthetic photos.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * uniform() }

    mutating func normal() -> Double {
        let u = max(uniform(), 1e-12)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * uniform())
    }
}

/// Synthetic bean photos: known colours under deliberately bad lighting.
enum Synth {
    typealias Family = [(name: String, color: SIMD3<Double>)]

    static let paper = 0.85
    // Linear-sRGB reflectances of look-alike trios a person would struggle to separate, one
    // trio per colour family.
    static let reds: Family = [("cherry", SIMD3(0.50, 0.030, 0.035)), ("raspberry", SIMD3(0.42, 0.022, 0.060)), ("cinnamon", SIMD3(0.56, 0.060, 0.030))]
    static let yellows: Family = [("lemon", SIMD3(0.80, 0.60, 0.04)), ("pina", SIMD3(0.82, 0.68, 0.20)), ("banana", SIMD3(0.74, 0.58, 0.10))]
    static let greens: Family = [("apple", SIMD3(0.20, 0.45, 0.05)), ("kiwi", SIMD3(0.24, 0.40, 0.10)), ("lime", SIMD3(0.28, 0.50, 0.06))]
    static let darks: Family = [("licorice", SIMD3(0.012, 0.012, 0.014)), ("blackberry", SIMD3(0.035, 0.015, 0.050)), ("rootbeer", SIMD3(0.050, 0.025, 0.012))]
    static let whites: Family = [("coconut", SIMD3(0.84, 0.83, 0.80)), ("vanilla", SIMD3(0.80, 0.74, 0.58)), ("soda", SIMD3(0.70, 0.68, 0.64))]
    static let blackSheet = SIMD3(0.030, 0.030, 0.034)
    static let navySheet = SIMD3(0.030, 0.045, 0.130)
    static let warmLight = SIMD3(1.0, 0.88, 0.70)

    struct Placed {
        var cx, cy, angle: Double
        var flavor: String
        var color: SIMD3<Double>
    }

    /// `perFlavor` beans of each flavour, shuffled over a jittered grid.
    static func grid(_ family: Family, perFlavor: Int, columns: Int = 10, seed: UInt64 = 0) -> [Placed] {
        var rng = SplitMix64(state: seed &+ 1)
        var order = (0..<(family.count * perFlavor)).map { $0 % family.count }
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            order.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        return order.enumerated().map { i, f in
            Placed(
                cx: 110 + Double(i % columns) * 105 + rng.uniform(-8, 8),
                cy: 100 + Double(i / columns) * 90 + rng.uniform(-8, 8),
                angle: rng.uniform(0, 180), flavor: family[f].name, color: family[f].color)
        }
    }

    private static func fillEllipse(
        _ image: inout [SIMD3<Double>], width w: Int, height h: Int,
        cx: Double, cy: Double, rx: Double, ry: Double, angle: Double, _ paint: (inout SIMD3<Double>) -> Void
    ) {
        let reach = Int(max(rx, ry)) + 2
        let c = cos(angle * .pi / 180), s = sin(angle * .pi / 180)
        for y in max(0, Int(cy) - reach)...min(h - 1, Int(cy) + reach) {
            for x in max(0, Int(cx) - reach)...min(w - 1, Int(cx) + reach) {
                let dx = Double(x) - cx, dy = Double(y) - cy
                let u = (dx * c + dy * s) / rx, v = (-dx * s + dy * c) / ry
                if u * u + v * v <= 1 { paint(&image[y * w + x]) }
            }
        }
    }

    /// Beans under warm, uneven light, with shadows and glints. They lie on white paper, or —
    /// when `sheet` is given — on a coloured sheet laid on the white paper with `border` px
    /// of white showing around it (0 for none).
    static func render(
        _ placed: [Placed], width w: Int = 1200, height h: Int = 900, cast: SIMD3<Double> = warmLight,
        falloff: Double = 0.45, jitter: Double = 0.03, seed: UInt64 = 0,
        sheet: SIMD3<Double>? = nil, border: Int = 50
    ) -> PixelImage {
        var rng = SplitMix64(state: seed &+ 7)
        var image = [SIMD3<Double>](repeating: SIMD3(repeating: paper), count: w * h)
        if let sheet {
            for y in border..<(h - border) {
                for x in border..<(w - border) { image[y * w + x] = sheet }
            }
        }
        let rx = 26.0, ry = 16.0
        var shadow = [SIMD3<Double>](repeating: SIMD3(repeating: 0), count: w * h)
        for p in placed {
            fillEllipse(&shadow, width: w, height: h, cx: p.cx + 5, cy: p.cy + 6, rx: rx, ry: ry, angle: p.angle) { $0 = SIMD3(repeating: 1) }
        }
        for i in image.indices where shadow[i].x > 0 { image[i] *= 0.72 }
        for p in placed {
            let body = p.color * (1 + jitter * rng.normal())
            // Darker rim → brighter middle, like a curved surface.
            fillEllipse(&image, width: w, height: h, cx: p.cx, cy: p.cy, rx: rx, ry: ry, angle: p.angle) { $0 = body * 0.7 }
            fillEllipse(&image, width: w, height: h, cx: p.cx, cy: p.cy, rx: rx - 5, ry: ry - 4, angle: p.angle) { $0 = body }
            fillEllipse(&image, width: w, height: h, cx: p.cx - 6, cy: p.cy - 4, rx: 4, ry: 2, angle: p.angle) { $0 = SIMD3(repeating: 0.95) }
        }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let fx = Double(x) / Double(w) - 0.3, fy = Double(y) / Double(h) - 0.35
                let light = 1 - falloff * (fx * fx + fy * fy)
                let v = image[y * w + x] * light * cast
                for c in 0..<3 { rgba[(y * w + x) * 4 + c] = encode(v[c] + 0.004 * rng.normal()) }
            }
        }
        return PixelImage(width: w, height: h, space: .sRGB, rgba: rgba)
    }

    static func encode(_ linear: Double) -> UInt8 {
        let c = min(max(linear, 0), 1)
        let e = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8(e * 255 + 0.5)
    }

    /// Flat coloured squares on white paper under the given light: `(colour, centre)`.
    static func swatches(
        _ patches: [(SIMD3<Double>, (Int, Int))], width w: Int = 1000, height h: Int = 400,
        cast: SIMD3<Double>, exposure: Double, half: Int = 80
    ) -> PixelImage {
        var image = [SIMD3<Double>](repeating: SIMD3(repeating: paper), count: w * h)
        for (color, (cx, cy)) in patches {
            for y in max(0, cy - half)..<min(h, cy + half) {
                for x in max(0, cx - half)..<min(w, cx + half) { image[y * w + x] = color }
            }
        }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in image.indices {
            let v = image[i] * cast * exposure
            for c in 0..<3 { rgba[i * 4 + c] = encode(v[c]) }
        }
        return PixelImage(width: w, height: h, space: .sRGB, rgba: rgba)
    }
}
