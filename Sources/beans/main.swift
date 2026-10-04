import BeanCore
import Foundation

// Headless access to the core, for trying it on real photos without a phone.
//
//   beans white  <photo.ppm> [--p3]
//   beans sample <photo.ppm> [--p3] [--white X,Y,Z] x,y,r [x,y,r ...]
//   beans sort   <photo.ppm> [--p3] [--white X,Y,Z] [--fallback X,Y,Z]
//
// Photos are binary PPM (P6, 8-bit): `magick photo.jpg photo.ppm`, or Pillow's `save`. Pass
// `--p3` when the pixel values are Display P3, as an iPhone's are. Coordinates are pixels.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func readPPM(_ path: String, space: RGBSpace) -> PixelImage {
    guard let data = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
    var position = 0
    func token() -> String {
        while position < data.count, data[position] == 0x23 || data[position] <= 0x20 {
            if data[position] == 0x23 { while position < data.count, data[position] != 0x0A { position += 1 } } else { position += 1 }
        }
        let start = position
        while position < data.count, data[position] > 0x20 { position += 1 }
        return String(decoding: data[start..<position], as: UTF8.self)
    }
    guard token() == "P6", let w = Int(token()), let h = Int(token()), token() == "255" else { fail("\(path) is not an 8-bit binary PPM") }
    position += 1
    guard data.count - position >= w * h * 3 else { fail("\(path) is truncated") }
    var rgba = [UInt8](repeating: 255, count: w * h * 4)
    for i in 0..<(w * h) {
        rgba[i * 4] = data[position + i * 3]
        rgba[i * 4 + 1] = data[position + i * 3 + 1]
        rgba[i * 4 + 2] = data[position + i * 3 + 2]
    }
    return PixelImage(width: w, height: h, space: space, rgba: rgba)
}

func triple(_ text: String) -> SIMD3<Double> {
    let parts = text.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 3 else { fail("expected three comma-separated numbers, got \(text)") }
    return SIMD3(parts[0], parts[1], parts[2])
}

func show(_ lab: Lab) -> String {
    String(format: "L %5.1f  a %6.1f  b %6.1f  %@", lab.x, lab.y, lab.z, ColorScience.hex(lab))
}

var arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    let value = arguments[i + 1]
    arguments.removeSubrange(i...(i + 1))
    return value
}
let space: RGBSpace = arguments.contains("--p3") ? .displayP3 : .sRGB
arguments.removeAll { $0 == "--p3" }
let givenWhite = option("--white").map(triple)
let fallback = option("--fallback").map(triple)
guard arguments.count >= 2 else { fail("usage: beans white|sample|sort <photo.ppm> [--p3] …") }
let image = readPPM(arguments[1], space: space)

switch arguments[0] {
case "white":
    let white = Sampling.autoWhite(image)
    print(String(format: "white %.4f,%.4f,%.4f  found=%@ clipped=%@", white.xyz.x, white.xyz.y, white.xyz.z, "\(white.found)", "\(white.clipped)"))
case "sample":
    let auto = Sampling.autoWhite(image)
    let white = givenWhite ?? auto.xyz
    print(String(format: "white %.4f,%.4f,%.4f%@", white.x, white.y, white.z, givenWhite == nil ? "  (automatic, found=\(auto.found))" : "  (given)"))
    for spot in arguments.dropFirst(2) {
        let t = triple(spot)
        guard let lab = Sampling.sample(image, white: white, x: t.x, y: t.y, r: t.z) else { print("\(spot): outside the photo"); continue }
        print("\(spot.padding(toLength: 16, withPad: " ", startingAt: 0)) \(show(lab))")
    }
case "sort":
    do {
        let result = try Sorting.analyze(image, tappedWhite: givenWhite, fallbackWhite: fallback)
        print("\(result.beans.count) beans, \(result.clumps.count) clumps, suggested groups: \(result.suggestedGroupCount)")
        print("sheet: \(show(result.sheet.lab))  white paper=\(result.sheet.isWhite) calibrated=\(result.sheet.calibrated)")
        for partition in result.partitions {
            let separation = partition.minSeparation.map { String(format: "%.1f", $0) } ?? "-"
            print("k=\(partition.groupCount)  counts \(partition.counts)  closest ΔE \(separation)")
            if partition.groupCount == result.suggestedGroupCount {
                for (g, centroid) in partition.centroids.enumerated() { print("   group \(g): \(show(centroid))") }
            }
        }
    } catch {
        fail("no beans found on a plain surface")
    }
default:
    fail("unknown command \(arguments[0])")
}
