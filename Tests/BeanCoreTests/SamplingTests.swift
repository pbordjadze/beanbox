import Foundation
import Testing
@testable import BeanCore

@Suite struct SamplingTests {
    static let patches: [(SIMD3<Double>, (Int, Int))] = [
        (SIMD3(0.50, 0.03, 0.035), (200, 200)),
        (SIMD3(0.10, 0.45, 0.12), (500, 200)),
        (SIMD3(0.05, 0.12, 0.50), (800, 200)),
    ]

    @Test func sameColoursMeasureAlikeUnderDifferentLight() throws {
        // One shot under warm dim light, one under cool bright light. Once each photo is
        // balanced against its own white paper, a patch must measure the same in both.
        let warm = Synth.swatches(Self.patches, cast: SIMD3(1.0, 0.82, 0.60), exposure: 0.8)
        let cool = Synth.swatches(Self.patches, cast: SIMD3(0.85, 0.95, 1.0), exposure: 1.0)
        let warmWhite = Sampling.autoWhite(warm), coolWhite = Sampling.autoWhite(cool)
        for (_, (x, y)) in Self.patches {
            let a = try #require(Sampling.sample(warm, white: warmWhite.xyz, x: Double(x), y: Double(y), r: 20))
            let b = try #require(Sampling.sample(cool, white: coolWhite.xyz, x: Double(x), y: Double(y), r: 20))
            // Not ~0: the fake light tints linear RGB while the balance works in Bradford
            // cone space. Unbalanced, these pairs are 15–30 apart.
            #expect(ColorScience.ciede2000(a, b, kL: Matching.kL) < 3)
        }
        let paper = try #require(Sampling.sample(warm, white: warmWhite.xyz, x: 950, y: 30, r: 20))
        #expect(abs(paper.x - ColorScience.whiteL) < 1.5 && hypot(paper.y, paper.z) < 1)
    }

    @Test func autoWhitePrefersNeutralPaperOverBrightYellow() throws {
        // Half white paper, half yellow paper of the same brightness, warm light. Without a
        // tap the white half must still be chosen as the reference.
        let yellow: [(SIMD3<Double>, (Int, Int))] = [(SIMD3(0.95, 0.90, 0.10), (600, 200))]
        let image = Synth.swatches(yellow, width: 800, cast: SIMD3(1.0, 0.85, 0.65), exposure: 1, half: 200)
        let white = Sampling.autoWhite(image)
        let paper = try #require(Sampling.sample(image, white: white.xyz, x: 200, y: 200, r: 20))
        let yellowLab = try #require(Sampling.sample(image, white: white.xyz, x: 600, y: 200, r: 20))
        #expect(abs(paper.y) < 2 && abs(paper.z) < 2)
        #expect(yellowLab.z > 60)
    }

    @Test func overexposedWhiteIsFlagged() {
        let blown = PixelImage(width: 64, height: 64, space: .sRGB, rgba: [UInt8](repeating: 255, count: 64 * 64 * 4))
        #expect(Sampling.autoWhite(blown).clipped)
        #expect(!Sampling.autoWhite(Synth.swatches(Self.patches, cast: SIMD3(1, 1, 1), exposure: 1)).clipped)
    }

    @Test func tapOutsideThePhotoMeasuresNothing() {
        let image = Synth.swatches(Self.patches, cast: SIMD3(1, 1, 1), exposure: 1)
        #expect(Sampling.sample(image, white: ColorScience.d65, x: 5000, y: 10, r: 20) == nil)
        #expect(Sampling.white(in: image, x: -500, y: 10, r: 20) == nil)
    }

    @Test func tappedWhiteOnAColouredPatchShiftsEverything() throws {
        let image = Synth.swatches(Self.patches, cast: SIMD3(1.0, 0.82, 0.60), exposure: 0.8)
        let auto = Sampling.autoWhite(image)
        let wrong = try #require(Sampling.white(in: image, x: 500, y: 200, r: 20))
        let before = try #require(Sampling.sample(image, white: auto.xyz, x: 200, y: 200, r: 20))
        let after = try #require(Sampling.sample(image, white: wrong.xyz, x: 200, y: 200, r: 20))
        #expect(abs(after.y - before.y) > 10)
    }

    @Test func bodyColorIgnoresGlintsAndShadow() {
        var lab = [Lab](repeating: Lab(45, 55, 30), count: 70)
        lab += [Lab](repeating: Lab(95, 0, 0), count: 10)   // specular glint
        lab += [Lab](repeating: Lab(20, 30, 15), count: 10)  // contact shadow
        #expect(Sampling.bodyColor(lab) == Lab(45, 55, 30))
    }

    @Test func aTapThatSpillsOntoThePaperStillReadsTheObject() throws {
        // Radius twice the patch's half-width reaches well onto the paper around it.
        let small: [(SIMD3<Double>, (Int, Int))] = [(SIMD3(0.50, 0.03, 0.035), (200, 200))]
        let image = Synth.swatches(small, cast: SIMD3(1, 1, 1), exposure: 1, half: 12)
        let white = Sampling.autoWhite(image)
        let tight = try #require(Sampling.sample(image, white: white.xyz, x: 200, y: 200, r: 6))
        let loose = try #require(Sampling.sample(image, white: white.xyz, x: 200, y: 200, r: 24))
        #expect(ColorScience.ciede2000(tight, loose) < 1)
    }
}
