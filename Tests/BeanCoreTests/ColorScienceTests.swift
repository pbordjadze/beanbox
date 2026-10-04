import Foundation
import Testing
@testable import BeanCore

@Suite struct ColorScienceTests {
    // Sharma, Wu & Dalal (2005) CIEDE2000 reference pairs.
    static let sharma: [(Lab, Lab, Double)] = [
        (Lab(50.0, 2.6772, -79.7751), Lab(50.0, 0.0, -82.7485), 2.0425),
        (Lab(50.0, 3.1571, -77.2803), Lab(50.0, 0.0, -82.7485), 2.8615),
        (Lab(50.0, 2.8361, -74.0200), Lab(50.0, 0.0, -82.7485), 3.4412),
        (Lab(50.0, -1.3802, -84.2814), Lab(50.0, 0.0, -82.7485), 1.0000),
        (Lab(50.0, 0.0, 0.0), Lab(50.0, -1.0, 2.0), 2.3669),
        (Lab(50.0, 2.49, -0.001), Lab(50.0, -2.49, 0.0009), 7.1792),
        (Lab(50.0, 2.49, -0.001), Lab(50.0, -2.49, 0.0011), 7.2195),
        (Lab(50.0, -0.001, 2.49), Lab(50.0, 0.0009, -2.49), 4.8045),
        (Lab(50.0, 2.5, 0.0), Lab(50.0, 0.0, -2.5), 4.3065),
        (Lab(50.0, 2.5, 0.0), Lab(73.0, 25.0, -18.0), 27.1492),
        (Lab(50.0, 2.5, 0.0), Lab(61.0, -5.0, 29.0), 22.8977),
        (Lab(50.0, 2.5, 0.0), Lab(56.0, -27.0, -3.0), 31.9030),
        (Lab(50.0, 2.5, 0.0), Lab(58.0, 24.0, 15.0), 19.4535),
        (Lab(60.2574, -34.0099, 36.2677), Lab(60.4626, -34.1751, 39.4387), 1.2644),
        (Lab(63.0109, -31.0961, -5.8663), Lab(62.8187, -29.7946, -4.0864), 1.2630),
        (Lab(2.0776, 0.0795, -1.1350), Lab(0.9033, -0.0636, -0.5514), 0.9082),
    ]

    @Test func ciede2000MatchesTheReferencePairs() {
        for (a, b, expected) in Self.sharma {
            #expect(abs(ColorScience.ciede2000(a, b) - expected) < 1e-4)
            #expect(abs(ColorScience.ciede2000(b, a) - expected) < 1e-4)
        }
    }

    @Test func kLHalvesAPureLightnessDifference() {
        let a = Lab(40, 30, 10), b = Lab(50, 30, 10)
        #expect(abs(ColorScience.ciede2000(a, b, kL: 2) - ColorScience.ciede2000(a, b) / 2) < 1e-12)
    }

    @Test func labRoundTripsThroughXYZ() {
        for lab in [Lab(53.2, 80.1, 67.2), Lab(5, 1, -3), Lab(96, 0, 0)] {
            let back = ColorScience.lab(fromXYZ: ColorScience.xyz(fromLab: lab))
            #expect(abs(back.x - lab.x) < 1e-9 && abs(back.y - lab.y) < 1e-9 && abs(back.z - lab.z) < 1e-9)
        }
    }

    /// Values computed by the Python implementation this was ported from (homelab's beanbox
    /// service): the port must measure the same colours.
    @Test func pixelsMeasureTheSameAsTheOriginalImplementation() {
        let white = XYZ(0.659726868, 0.691085816, 0.552663648)
        let cases: [(SIMD3<UInt8>, RGBSpace, Lab, String)] = [
            (SIMD3(200, 60, 50), .sRGB, Lab(51.7517, 57.5539, 31.7471), "#da4749"),
            (SIMD3(200, 60, 50), .displayP3, Lab(52.829, 69.2447, 41.0705), "#ee333c"),
            (SIMD3(30, 90, 160), .sRGB, Lab(44.1601, 16.9645, -61.961), "#0066d1"),
            (SIMD3(250, 240, 200), .displayP3, Lab(104.7761, -4.0604, 5.289), "#ffffff"),
            (SIMD3(12, 10, 14), .sRGB, Lab(3.892, 1.9414, -5.027), "#0d0d16"),
        ]
        for (pixel, space, expected, hex) in cases {
            let lab = ColorScience.lab(r: pixel.x, g: pixel.y, b: pixel.z, space: space, white: white)
            #expect(abs(lab.x - expected.x) < 1e-3 && abs(lab.y - expected.y) < 1e-3 && abs(lab.z - expected.z) < 1e-3)
            #expect(ColorScience.hex(lab) == hex)
        }
        #expect(abs(Sampling.neutralChroma(of: white) - 19.565160979) < 1e-6)
    }

    @Test func whiteBalanceNeutralisesAColourCast() {
        // A grey card and white paper under warm light: after balancing against the paper,
        // the grey must come out neutral and the paper exactly at the pinned white.
        let cast = SIMD3(1.0, 0.85, 0.6)
        let m = ColorScience.toXYZ(.sRGB)
        let white = m * (cast * 0.8)
        let adapt = ColorScience.adaptMatrix(white: white)
        let grey = ColorScience.lab(fromXYZ: adapt * (m * (cast * 0.2)))
        #expect(abs(grey.y) < 1e-9 && abs(grey.z) < 1e-9)
        let paper = ColorScience.lab(fromXYZ: adapt * white)
        #expect(abs(paper.x - ColorScience.whiteL) < 1e-9 && abs(paper.y) < 1e-9 && abs(paper.z) < 1e-9)
    }

    @Test func displayP3RedIsMoreSaturatedThanSRGBRed() {
        let srgb = ColorScience.lab(r: 255, g: 0, b: 0, space: .sRGB, white: ColorScience.d65)
        let p3 = ColorScience.lab(r: 255, g: 0, b: 0, space: .displayP3, white: ColorScience.d65)
        #expect(hypot(p3.y, p3.z) > hypot(srgb.y, srgb.z) + 5)
    }

    @Test func hexOfKnownColours() {
        #expect(ColorScience.hex(Lab(100, 0, 0)) == "#ffffff")
        #expect(ColorScience.hex(Lab(0, 0, 0)) == "#000000")
        #expect(ColorScience.hex(Lab(53.2408, 80.0925, 67.2032)) == "#ff0000")
    }

    @Test func displayP3ComponentsStayInRangeForASaturatedBean() {
        // A red outside sRGB: clipped there, representable in P3.
        let lab = ColorScience.lab(r: 255, g: 20, b: 20, space: .displayP3, white: ColorScience.d65 * ColorScience.whiteY)
        let p3 = ColorScience.display(lab, in: .displayP3)
        #expect(abs(p3.x - 1) < 0.01 && abs(p3.y - 20.0 / 255) < 0.01 && abs(p3.z - 20.0 / 255) < 0.01)
        #expect(ColorScience.display(lab, in: .sRGB).y == 0)
    }

    @Test func matrixInverse() {
        let m = ColorScience.bradford
        let identity = m * m.inverse
        for (row, expected) in [(identity.r0, SIMD3(1.0, 0, 0)), (identity.r1, SIMD3(0, 1.0, 0)), (identity.r2, SIMD3(0, 0, 1.0))] {
            #expect(abs(row.x - expected.x) < 1e-12 && abs(row.y - expected.y) < 1e-12 && abs(row.z - expected.z) < 1e-12)
        }
    }

    @Test func percentileInterpolatesLikeNumpy() {
        #expect(Stats.percentile([1, 2, 3, 4], 50) == 2.5)
        #expect(Stats.percentile([1, 2, 3, 4], 0) == 1)
        #expect(Stats.percentile([1, 2, 3, 4], 100) == 4)
        #expect(abs(Stats.percentile([10, 20, 30, 40, 50], 15) - 16) < 1e-12)
        #expect(Stats.median([5, 1, 3]) == 3)
    }
}
