#if DEBUG
import BeanCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic, launch-argument-driven app states for CI screenshots.
///
///     xcrun simctl launch <udid> com.pbordjadze.beanbox -demo sort
///
/// A scenario fills a scratch project with synthetic photos through the same calls a person's
/// taps make, so every screenshot also proves the real decode → measure → sort path.
///
/// Debug builds only: the demo types are compiled out of Release builds, so a shipped app has
/// no launch argument that swaps its content (`ci/check_release.sh` checks).
enum DemoMode {
    /// The requested scenario, e.g. "papers", "match", "sort-dark".
    static let scenario: String? = UserDefaults.standard.string(forKey: "demo")

    static var isActive: Bool { scenario != nil }

    static func has(_ word: String) -> Bool { scenario?.contains(word) ?? false }

    /// `tmp/demo-ready` in the app's data container. CI screenshots a scenario shortly after
    /// this file appears instead of sleeping for a worst-case delay (`ci/screenshots.sh`).
    static let readyMarker = FileManager.default.temporaryDirectory.appending(path: "demo-ready")

    /// Signals that the scenario's content is on screen; only animations are still settling.
    static func markReady() {
        guard let scenario else { return }
        try? Data(scenario.utf8).write(to: readyMarker, options: .atomic)
    }
}

/// Fills the project for a demo scenario.
enum DemoData {
    static func install(into project: Project) async {
        guard let scenario = DemoMode.scenario else { return }
        if scenario.hasPrefix("papers") || scenario.hasPrefix("match") || scenario.hasPrefix("beans") {
            if !scenario.contains("empty") { await measurePapersAndBeans(project) }
        }
        if scenario.hasPrefix("sort") && !scenario.contains("empty") {
            let dark = scenario.contains("dark")
            let photo = DemoPhotos.beans(dark ? DemoPhotos.whites : DemoPhotos.reds, sheet: dark ? DemoPhotos.blackSheet : nil)
            await project.addPhoto(photo, for: .sort)
            // SortView marks the scenario ready once its analysis is on screen.
            return
        }
        DemoMode.markReady()
    }

    private static func measurePapersAndBeans(_ project: Project) async {
        guard let photo = await project.addPhoto(DemoPhotos.fan(), for: .papers),
              let loaded = await project.loaded(photo) else { return }
        let radius = SampleSize.medium.fraction * Double(max(photo.width, photo.height))
        project.setWhite(of: photo.id, pixels: loaded.pixels, at: CGPoint(x: 450, y: 1120), radius: radius)
        guard let balanced = project.photo(photo.id) else { return }
        for i in DemoPhotos.sheets.indices {
            project.addSample(.paper, in: balanced, pixels: loaded.pixels, at: CGPoint(x: 100 + i * 62, y: 600), radius: radius, label: nil)
        }
        project.focus[.beans] = photo.id
        // Stand-in beans: tapped off the same fan, a little away from each sheet's centre.
        let named: [(String, Int)] = [("Sunkist Orange", 0), ("Green Apple", 2), ("Sunkist Lemon", 5), ("Blueberry", 7), ("Very Cherry", 8), ("Licorice", 10), ("Cotton Candy", 11)]
        for (name, sheet) in named {
            project.addSample(.bean, in: balanced, pixels: loaded.pixels, at: CGPoint(x: 96 + sheet * 62, y: 960), radius: radius, label: name)
        }
        if DemoMode.has("locked"), let row = project.matchRows.first, let paper = row.paper {
            project.setLock(flavor: row.flavor.key, paper: paper.id)
        }
    }
}

/// Synthetic photos: known colours under deliberately bad (warm, uneven) light.
enum DemoPhotos {
    typealias RGB = SIMD3<Double>

    static let paper = 0.85
    static let reds: [RGB] = [RGB(0.50, 0.030, 0.035), RGB(0.42, 0.022, 0.060), RGB(0.56, 0.060, 0.030)]
    static let whites: [RGB] = [RGB(0.84, 0.83, 0.80), RGB(0.80, 0.74, 0.58), RGB(0.70, 0.68, 0.64)]
    static let blackSheet = RGB(0.030, 0.030, 0.034)
    static let sheets: [RGB] = [
        RGB(0.80, 0.14, 0.02), RGB(0.78, 0.10, 0.03), RGB(0.16, 0.36, 0.03), RGB(0.22, 0.42, 0.10),
        RGB(0.60, 0.40, 0.02), RGB(0.75, 0.55, 0.05), RGB(0.04, 0.04, 0.09), RGB(0.03, 0.05, 0.16),
        RGB(0.50, 0.05, 0.03), RGB(0.62, 0.07, 0.05), RGB(0.012, 0.012, 0.014), RGB(0.85, 0.30, 0.25),
    ]

    private struct Generator {
        var state: UInt64

        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }

        /// Zero-mean noise of unit variance. Uniform rather than Gaussian: this runs three
        /// times per pixel in an unoptimised build.
        mutating func noise() -> Double { (next() - 0.5) * 3.4641 }
    }

    /// A fan of coloured sheets on white paper, 900 × 1200.
    static func fan() -> Data {
        let w = 900, h = 1200
        var image = [RGB](repeating: RGB(repeating: paper), count: w * h)
        for (i, color) in sheets.enumerated() {
            let x0 = 70 + i * 62
            for y in (180 + i * 18)..<(1000 + i * 6) {
                for x in x0..<min(w, x0 + 200) { image[y * w + x] = color }
            }
        }
        return jpeg(lit(image, w, h, seed: 1), w, h)
    }

    /// Thirty-six beans of three look-alike flavours, on white paper or on a dark sheet with
    /// white paper showing around it, 900 × 1200.
    static func beans(_ flavors: [RGB], sheet: RGB?) -> Data {
        let w = 900, h = 1200
        var rng = Generator(state: 11)
        var image = [RGB](repeating: RGB(repeating: paper), count: w * h)
        if let sheet {
            for y in 45..<(h - 45) {
                for x in 45..<(w - 45) { image[y * w + x] = sheet }
            }
        }
        func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ angle: Double, _ paint: (inout RGB) -> Void) {
            let c = cos(angle), s = sin(angle)
            for y in max(0, Int(cy) - 30)...min(h - 1, Int(cy) + 30) {
                for x in max(0, Int(cx) - 30)...min(w - 1, Int(cx) + 30) {
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    let u = (dx * c + dy * s) / rx, v = (-dx * s + dy * c) / ry
                    if u * u + v * v <= 1 { paint(&image[y * w + x]) }
                }
            }
        }
        var order = (0..<36).map { $0 % flavors.count }
        for i in stride(from: order.count - 1, to: 0, by: -1) { order.swapAt(i, Int(rng.next() * Double(i + 1))) }
        var placed: [(Double, Double, Double, RGB)] = []
        for (i, flavor) in order.enumerated() {
            let cx = 135 + Double(i % 6) * 126 + (rng.next() - 0.5) * 16
            let cy = 150 + Double(i / 6) * 126 + (rng.next() - 0.5) * 16
            placed.append((cx, cy, rng.next() * .pi, flavors[flavor] * (1 + 0.03 * rng.noise())))
        }
        for (cx, cy, angle, _) in placed { ellipse(cx + 5, cy + 6, 26, 16, angle) { $0 *= 0.72 } }
        for (cx, cy, angle, body) in placed {
            ellipse(cx, cy, 26, 16, angle) { $0 = body * 0.7 }
            ellipse(cx, cy, 21, 12, angle) { $0 = body }
            ellipse(cx - 6, cy - 4, 4, 2, angle) { $0 = RGB(repeating: 0.95) }
        }
        return jpeg(lit(image, w, h, seed: 3), w, h)
    }

    /// Applies warm light that falls off towards the corners, sensor noise and the sRGB curve.
    private static func lit(_ image: [RGB], _ w: Int, _ h: Int, seed: UInt64) -> [UInt8] {
        var rng = Generator(state: seed)
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let cast = RGB(1.0, 0.9, 0.74)
        for y in 0..<h {
            for x in 0..<w {
                let fx = Double(x) / Double(w) - 0.4, fy = Double(y) / Double(h) - 0.3
                let v = image[y * w + x] * (1 - 0.4 * (fx * fx + fy * fy)) * cast
                for c in 0..<3 {
                    let linear = min(max(v[c] + 0.004 * rng.noise(), 0), 1)
                    let encoded = linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
                    rgba[(y * w + x) * 4 + c] = UInt8(encoded * 255 + 0.5)
                }
            }
        }
        return rgba
    }

    private static func jpeg(_ rgba: [UInt8], _ w: Int, _ h: Int) -> Data {
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return out as Data
    }
}
#endif
