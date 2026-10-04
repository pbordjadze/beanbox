import Foundation

/// CIELAB `(L, a, b)` relative to a D65 white.
public typealias Lab = SIMD3<Double>
/// CIE XYZ tristimulus values.
public typealias XYZ = SIMD3<Double>

/// The two encodings phones produce. Display P3 shares sRGB's transfer curve, so only the
/// primaries differ.
public enum RGBSpace: String, Sendable, Codable {
    case sRGB
    case displayP3
}

public struct Mat3: Sendable, Equatable {
    public var r0, r1, r2: SIMD3<Double>

    public init(_ r0: SIMD3<Double>, _ r1: SIMD3<Double>, _ r2: SIMD3<Double>) {
        self.r0 = r0
        self.r1 = r1
        self.r2 = r2
    }

    public static func diagonal(_ d: SIMD3<Double>) -> Mat3 {
        Mat3(SIMD3(d.x, 0, 0), SIMD3(0, d.y, 0), SIMD3(0, 0, d.z))
    }

    public static func * (m: Mat3, v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3((m.r0 * v).sum(), (m.r1 * v).sum(), (m.r2 * v).sum())
    }

    public static func * (a: Mat3, b: Mat3) -> Mat3 {
        let c0 = SIMD3(b.r0.x, b.r1.x, b.r2.x)
        let c1 = SIMD3(b.r0.y, b.r1.y, b.r2.y)
        let c2 = SIMD3(b.r0.z, b.r1.z, b.r2.z)
        func row(_ r: SIMD3<Double>) -> SIMD3<Double> { SIMD3((r * c0).sum(), (r * c1).sum(), (r * c2).sum()) }
        return Mat3(row(a.r0), row(a.r1), row(a.r2))
    }

    public var inverse: Mat3 {
        let a = r0.x, b = r0.y, c = r0.z
        let d = r1.x, e = r1.y, f = r1.z
        let g = r2.x, h = r2.y, i = r2.z
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return Mat3(
            SIMD3(e * i - f * h, c * h - b * i, b * f - c * e) / det,
            SIMD3(f * g - d * i, a * i - c * g, c * d - a * f) / det,
            SIMD3(d * h - e * g, b * g - a * h, a * e - b * d) / det)
    }
}

/// Colour maths: camera RGB → white-balanced CIELAB, and CIEDE2000.
///
/// Every Lab value the app stores is relative to the white paper of the photo it came from,
/// pinned to `whiteY`. That is what makes two photos comparable, and why changing `whiteY` or
/// the adaptation would invalidate saved measurements.
public enum ColorScience {
    /// Linear RGB → XYZ (D65). Using the Display P3 matrix directly, rather than converting P3
    /// photos to sRGB first, keeps saturated reds that fall outside sRGB from being clipped —
    /// exactly the colours the sorter has to tell apart.
    public static func toXYZ(_ space: RGBSpace) -> Mat3 {
        switch space {
        case .sRGB:
            Mat3(
                SIMD3(0.4124564, 0.3575761, 0.1804375),
                SIMD3(0.2126729, 0.7151522, 0.0721750),
                SIMD3(0.0193339, 0.1191920, 0.9503041))
        case .displayP3:
            Mat3(
                SIMD3(0.4865709, 0.2656677, 0.1982173),
                SIMD3(0.2289746, 0.6917385, 0.0792869),
                SIMD3(0.0000000, 0.0451134, 1.0439444))
        }
    }

    public static let d65 = XYZ(0.95047, 1.0, 1.08883)

    public static let bradford = Mat3(
        SIMD3(0.8951, 0.2664, -0.1614),
        SIMD3(-0.7502, 1.7135, 0.0367),
        SIMD3(0.0389, -0.0685, 1.0296))
    public static let bradfordInverse = bradford.inverse

    /// Where the white reference lands after balancing. Printer paper is not a perfect
    /// reflector, so it is pinned a little under 1 (L* ≈ 96).
    public static let whiteY = 0.90
    public static let whiteL = 116.0 * cbrt(whiteY) - 16.0

    /// 8-bit sRGB-curve value → linear light.
    public static let decodeTable: [Double] = (0..<256).map { i in
        let v = Double(i) / 255.0
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// Bradford adaptation taking the measured white to `whiteY · D65`.
    public static func adaptMatrix(white: XYZ) -> Mat3 {
        let source = bradford * white
        let target = bradford * (d65 * whiteY)
        return bradfordInverse * Mat3.diagonal(target / source) * bradford
    }

    public static func lab(fromXYZ xyz: XYZ) -> Lab {
        let t = xyz / d65
        let fx = labF(t.x), fy = labF(t.y), fz = labF(t.z)
        return Lab(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
    }

    @inline(__always)
    static func labF(_ t: Double) -> Double {
        let d = 6.0 / 29.0
        return t > d * d * d ? cbrt(t) : t / (3 * d * d) + 4.0 / 29.0
    }

    public static func xyz(fromLab lab: Lab) -> XYZ {
        let fy = (lab.x + 16.0) / 116.0
        let f = SIMD3(fy + lab.y / 500.0, fy, fy - lab.z / 200.0)
        let d = 6.0 / 29.0
        func inv(_ v: Double) -> Double { v > d ? v * v * v : 3 * d * d * (v - 4.0 / 29.0) }
        return XYZ(inv(f.x), inv(f.y), inv(f.z)) * d65
    }

    /// One pixel → Lab, balanced so `white` reads as neutral white.
    public static func lab(r: UInt8, g: UInt8, b: UInt8, space: RGBSpace, white: XYZ) -> Lab {
        let linear = SIMD3<Double>(decodeTable[Int(r)], decodeTable[Int(g)], decodeTable[Int(b)])
        let toBalanced: Mat3 = adaptMatrix(white: white) * toXYZ(space)
        return lab(fromXYZ: toBalanced * linear)
    }

    /// The nearest displayable colour for a Lab value, as gamma-encoded components in `space`
    /// (out-of-gamut colours are clipped). Display P3 shows saturated beans more faithfully on
    /// a phone screen than sRGB can.
    public static func display(_ lab: Lab, in space: RGBSpace = .sRGB) -> SIMD3<Double> {
        let linear = toXYZ(space).inverse * xyz(fromLab: lab)
        func encode(_ v: Double) -> Double {
            let c = min(max(v, 0), 1)
            return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return SIMD3(encode(linear.x), encode(linear.y), encode(linear.z))
    }

    /// `#rrggbb` for a Lab colour, in sRGB.
    public static func hex(_ lab: Lab) -> String {
        let c = display(lab, in: .sRGB)
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.x), byte(c.y), byte(c.z))
    }

    /// CIEDE2000 colour difference. `kL` > 1 de-emphasises lightness (the textile convention
    /// is 2).
    public static func ciede2000(_ lab1: Lab, _ lab2: Lab, kL: Double = 1) -> Double {
        func degrees(_ r: Double) -> Double { r * 180 / .pi }
        func radians(_ d: Double) -> Double { d * .pi / 180 }
        func hueAngle(_ b: Double, _ a: Double) -> Double {
            let h = degrees(atan2(b, a)).truncatingRemainder(dividingBy: 360)
            return h < 0 ? h + 360 : h
        }
        let (l1, a1, b1) = (lab1.x, lab1.y, lab1.z)
        let (l2, a2, b2) = (lab2.x, lab2.y, lab2.z)
        let cBar7 = pow((hypot(a1, b1) + hypot(a2, b2)) / 2, 7)
        let g = 0.5 * (1 - sqrt(cBar7 / (cBar7 + pow(25.0, 7))))
        let a1p = (1 + g) * a1, a2p = (1 + g) * a2
        let c1p = hypot(a1p, b1), c2p = hypot(a2p, b2)
        let h1p = hueAngle(b1, a1p), h2p = hueAngle(b2, a2p)
        let achromatic = c1p * c2p == 0

        let dLp = l2 - l1
        let dCp = c2p - c1p
        var dh = h2p - h1p
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        if achromatic { dh = 0 }
        let dHp = 2 * sqrt(c1p * c2p) * sin(radians(dh) / 2)

        let lBar = (l1 + l2) / 2
        let cBarp = (c1p + c2p) / 2
        let hSum = h1p + h2p
        var hBar: Double
        if achromatic {
            hBar = hSum
        } else if abs(h1p - h2p) <= 180 {
            hBar = hSum / 2
        } else {
            hBar = hSum < 360 ? (hSum + 360) / 2 : (hSum - 360) / 2
        }

        let t = 1 - 0.17 * cos(radians(hBar - 30)) + 0.24 * cos(radians(2 * hBar))
            + 0.32 * cos(radians(3 * hBar + 6)) - 0.20 * cos(radians(4 * hBar - 63))
        let dTheta = 30 * exp(-pow((hBar - 275) / 25, 2))
        let rC = 2 * sqrt(pow(cBarp, 7) / (pow(cBarp, 7) + pow(25.0, 7)))
        let sL = 1 + 0.015 * pow(lBar - 50, 2) / sqrt(20 + pow(lBar - 50, 2))
        let sC = 1 + 0.045 * cBarp
        let sH = 1 + 0.015 * cBarp * t
        let rT = -sin(radians(2 * dTheta)) * rC

        let tl = dLp / (kL * sL), tc = dCp / sC, th = dHp / sH
        return sqrt(tl * tl + tc * tc + th * th + rT * tc * th)
    }
}

/// An 8-bit photo in memory: `width × height` RGBA pixels (alpha ignored), rows top to bottom.
public struct PixelImage: Sendable {
    public let width: Int
    public let height: Int
    public let space: RGBSpace
    public let rgba: [UInt8]

    public init(width: Int, height: Int, space: RGBSpace, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4)
        self.width = width
        self.height = height
        self.space = space
        self.rgba = rgba
    }
}

enum Stats {
    /// numpy's default percentile: linear interpolation between the two nearest ranks.
    /// `sorted` must be ascending and non-empty.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let rank = p / 100 * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
    }

    static func median(_ values: [Double]) -> Double {
        percentile(values.sorted(), 50)
    }

    /// Per-channel median of a list of triples.
    static func median(_ values: [SIMD3<Double>]) -> SIMD3<Double> {
        SIMD3(median(values.map(\.x)), median(values.map(\.y)), median(values.map(\.z)))
    }
}
