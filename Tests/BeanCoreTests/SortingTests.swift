import Foundation
import Testing
@testable import BeanCore

@Suite struct SortingTests {
    /// Flavour of the placed bean nearest each detection.
    static func truth(_ beans: [Sorting.Blob], _ placed: [Synth.Placed]) -> [String] {
        beans.map { b in
            let nearest = placed.min { hypot($0.cx - b.cx, $0.cy - b.cy) < hypot($1.cx - b.cx, $1.cy - b.cy) }!
            #expect(hypot(nearest.cx - b.cx, nearest.cy - b.cy) < 12, "detection is not centred on a real bean")
            return nearest.flavor
        }
    }

    /// Every bean found, and the suggested grouping is exactly the flavours.
    @discardableResult
    static func expectSeparated(_ result: Sorting.Analysis, _ placed: [Synth.Placed]) -> Sorting.Partition? {
        let flavors = Set(placed.map(\.flavor))
        #expect(result.beans.count == placed.count)
        #expect(result.clumps.isEmpty)
        #expect(result.suggestedGroupCount == flavors.count)
        guard let partition = result.partitions.first(where: { $0.groupCount == flavors.count }) else {
            Issue.record("no partition with \(flavors.count) groups")
            return nil
        }
        let truth = truth(result.beans.map(\.shape), placed)
        for g in 0..<partition.groupCount {
            let members = Set(zip(truth, partition.assignment).filter { $0.1 == g }.map(\.0))
            #expect(members.count == 1, "group \(g) mixes flavours: \(members)")
        }
        return partition
    }

    @Test func findsEveryBeanDespiteShadowsAndUnevenLight() throws {
        let placed = Synth.grid(Synth.reds, perFlavor: 20)
        let found = try Sorting.segment(Synth.render(placed), tappedWhite: nil)
        #expect(found.beans.count == 60)
        #expect(found.clumps.isEmpty)
        _ = Self.truth(found.beans.map(\.shape), placed)
        #expect(found.sheet.isWhite && found.sheet.calibrated)
        #expect(abs(found.sheet.lab.x - ColorScience.whiteL) < 0.5)
    }

    @Test func flatFieldMakesColourIndependentOfPosition() throws {
        // One flavour, no bean-to-bean variation: any spread left in the measurements is
        // lighting the pipeline failed to remove.
        let placed = Synth.grid([Synth.reds[0]], perFlavor: 60)
        let beans = try Sorting.segment(Synth.render(placed, jitter: 0), tappedWhite: nil).beans
        for channel in 0..<3 {
            let values = beans.map { $0.lab[channel] }
            let mean = values.reduce(0, +) / Double(values.count)
            let sd = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
            #expect(sd < 1.0)
        }
    }

    @Test func threeSimilarRedsAreSeparated() throws {
        let placed = Synth.grid(Synth.reds, perFlavor: 20)
        let result = try Sorting.analyze(Synth.render(placed))
        let three = try #require(Self.expectSeparated(result, placed))
        #expect(three.counts == [20, 20, 20])
        // Groups are lettered light → dark.
        #expect(three.centroids.map(\.x) == three.centroids.map(\.x).sorted(by: >))
        #expect((three.minSeparation ?? 0) > 2)
        #expect(result.partitions.map(\.groupCount) == [1, 2, 3, 4, 5, 6])
    }

    @Test(arguments: ["yellows", "greens", "darks"])
    func otherColourFamiliesAreSeparatedOnWhitePaper(family: String) throws {
        let colours = ["yellows": Synth.yellows, "greens": Synth.greens, "darks": Synth.darks][family]!
        let placed = Synth.grid(colours, perFlavor: 14)
        let result = try Sorting.analyze(Synth.render(placed))
        Self.expectSeparated(result, placed)
        #expect(result.sheet.isWhite && result.sheet.calibrated)
    }

    @Test(arguments: ["black", "navy"])
    func paleBeansAreSeparatedOnADarkSheet(sheet: String) throws {
        // White, ivory and pale-grey beans are invisible against white paper; on a dark
        // sheet (white paper showing around it) they sort like any other colour.
        let placed = Synth.grid(Synth.whites, perFlavor: 14)
        let result = try Sorting.analyze(Synth.render(placed, sheet: sheet == "black" ? Synth.blackSheet : Synth.navySheet))
        Self.expectSeparated(result, placed)
        #expect(!result.sheet.isWhite && result.sheet.lab.x < 40)
        #expect(result.sheet.calibrated)
    }

    @Test func darkSheetWithWhiteShowingMeasuresTheSameAsWhitePaper() throws {
        // The white paper around a dark sheet is the reference, so a flavour saved from
        // either kind of shot must come out the same colour.
        let placed = Synth.grid(Synth.reds, perFlavor: 14)
        let onWhite = try #require(Self.expectSeparated(try Sorting.analyze(Synth.render(placed)), placed))
        let onBlack = try #require(Self.expectSeparated(try Sorting.analyze(Synth.render(placed, sheet: Synth.blackSheet)), placed))
        for (a, b) in zip(onWhite.centroids, onBlack.centroids) { #expect(ColorScience.ciede2000(a, b) < 1) }
    }

    @Test func darkSheetWithNoWhiteInShotStillGroupsButIsFlagged() throws {
        // Pale beans right up to the frame's edge must not be mistaken for white paper
        // showing around the sheet.
        let placed = Synth.grid(Synth.whites, perFlavor: 14)
        let result = try Sorting.analyze(Synth.render(placed, sheet: Synth.blackSheet, border: 0))
        Self.expectSeparated(result, placed)
        #expect(!result.sheet.calibrated)
    }

    @Test func tappedWhiteCalibratesADarkSheetShot() throws {
        let placed = Synth.grid(Synth.reds, perFlavor: 14)
        let white = ColorScience.toXYZ(.sRGB) * (Synth.warmLight * Synth.paper)
        let result = try Sorting.analyze(Synth.render(placed, falloff: 0, sheet: Synth.blackSheet, border: 0), tappedWhite: white)
        #expect(result.sheet.calibrated && !result.sheet.isWhite)
        let reference = try #require(Self.expectSeparated(try Sorting.analyze(Synth.render(placed, falloff: 0)), placed))
        let tapped = try #require(Self.expectSeparated(result, placed))
        for (a, b) in zip(reference.centroids, tapped.centroids) { #expect(ColorScience.ciede2000(a, b) < 1) }
    }

    @Test func beansOnAClothWithNoWhiteAnywhereAreStillSorted() throws {
        // A navy tablecloth filling the frame: no paper, nothing to calibrate against. The
        // grouping must hold, the colours must stay in a sane range, and it must say so.
        let placed = Synth.grid(Synth.reds, perFlavor: 14)
        let result = try Sorting.analyze(Synth.render(placed, sheet: Synth.navySheet, border: 0))
        let three = try #require(Self.expectSeparated(result, placed))
        #expect(!result.sheet.calibrated && !result.sheet.isWhite)
        for centroid in three.centroids {
            #expect(centroid.x > 15 && centroid.x < 80, "lightness \(centroid.x) is out of a red bean's range")
            #expect(centroid.y > 25, "a red bean stopped being red")
        }
    }

    @Test func aWhiteFromAnotherPhotoCalibratesAClothShot() throws {
        let placed = Synth.grid(Synth.reds, perFlavor: 14)
        let onPaper = Synth.render(placed, falloff: 0)
        let reference = try #require(Self.expectSeparated(try Sorting.analyze(onPaper), placed))
        let borrowed = Sampling.autoWhite(onPaper).xyz
        let result = try Sorting.analyze(Synth.render(placed, falloff: 0, sheet: Synth.navySheet, border: 0), fallbackWhite: borrowed)
        let onCloth = try #require(Self.expectSeparated(result, placed))
        // Still not a white of its own, but the colours now agree with the paper shot.
        #expect(!result.sheet.calibrated)
        for (a, b) in zip(reference.centroids, onCloth.centroids) { #expect(ColorScience.ciede2000(a, b) < 1) }
    }

    @Test func foldsAndSheenOnAClothAreNotBeans() throws {
        // Long thin highlights across the cloth stand out from it as much as a bean does.
        let placed = Synth.grid(Synth.reds, perFlavor: 14)
        let found = try Sorting.segment(Synth.render(placed, sheet: Synth.navySheet, border: 0, sheen: 6), tappedWhite: nil)
        #expect(found.beans.count == placed.count)
        #expect(found.clumps.isEmpty)
        _ = Self.truth(found.beans.map(\.shape), placed)
    }

    @Test func aGrainySurfaceStillWorks() throws {
        // A wooden table: mid-brown, banded ±12 %.
        let placed = Synth.grid(Synth.greens, perFlavor: 14)
        let result = try Sorting.analyze(Synth.render(placed, sheet: Synth.woodSheet, border: 0, grain: 0.12))
        Self.expectSeparated(result, placed)
    }

    @Test func oneFlavourIsNotSplit() throws {
        let placed = Synth.grid([Synth.reds[0]], perFlavor: 40)
        let result = try Sorting.analyze(Synth.render(placed))
        #expect(result.beans.count == 40)
        #expect(result.suggestedGroupCount == 1)
    }

    @Test func touchingBeansAreSplit() throws {
        let red = Synth.reds[0]
        func bean(_ x: Double, _ y: Double, _ angle: Double = 0) -> Synth.Placed {
            Synth.Placed(cx: x, cy: y, angle: angle, flavor: red.name, color: red.color)
        }
        let placed = [bean(300, 300), bean(300, 330), bean(600, 300), bean(650, 300)]  // stacked; end to end
            + (0..<8).map { bean(200 + 90 * Double($0), 600, 30 * Double($0)) }
        let found = try Sorting.segment(Synth.render(placed), tappedWhite: nil)
        #expect(found.beans.count == 12)
        #expect(found.clumps.isEmpty)
    }

    @Test func tableAroundTheSheetIsIgnored() throws {
        let placed = Synth.grid(Synth.reds, perFlavor: 10)
        let image = Synth.render(placed)
        var rgba = image.rgba
        for y in 0..<image.height {
            for x in 0..<40 {  // dark tablecloth showing past the paper's edge
                let i = (y * image.width + x) * 4
                rgba[i] = 40; rgba[i + 1] = 35; rgba[i + 2] = 70
            }
        }
        let found = try Sorting.segment(PixelImage(width: image.width, height: image.height, space: .sRGB, rgba: rgba), tappedWhite: nil)
        #expect(found.beans.count == 30)
        #expect(found.clumps.isEmpty)
    }

    @Test func noSheetIsAClearError() {
        var rgba = [UInt8](repeating: 255, count: 800 * 600 * 4)
        for i in 0..<(800 * 600) { rgba[i * 4] = 120; rgba[i * 4 + 1] = 40; rgba[i * 4 + 2] = 40 }
        #expect(throws: Sorting.Failure.noBeans) {
            try Sorting.analyze(PixelImage(width: 800, height: 600, space: .sRGB, rgba: rgba))
        }
    }

    @Test func exaggeratedColoursAndPlotCoordinatesAreFilledIn() throws {
        let placed = Synth.grid(Synth.reds, perFlavor: 10)
        let result = try Sorting.analyze(Synth.render(placed))
        #expect(result.beans.allSatisfy { $0.enhanced != $0.lab })
        func sd(_ v: [Double]) -> Double {
            let m = v.reduce(0, +) / Double(v.count)
            return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot()
        }
        // The first principal axis carries the most spread.
        #expect(sd(result.beans.map(\.principal.x)) >= sd(result.beans.map(\.principal.y)))
        #expect(sd(result.beans.map(\.principal.y)) > 0)
    }

    @Test func sameInputGivesTheSameAnswer() throws {
        let image = Synth.render(Synth.grid(Synth.greens, perFlavor: 8))
        #expect(try Sorting.analyze(image) == Sorting.analyze(image))
    }
}
