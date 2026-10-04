import BeanCore
import CoreGraphics
import Foundation
import ImageIO

/// A photo decoded for work: the pixels the colour maths reads and the image the screen shows.
nonisolated struct LoadedPhoto: Sendable {
    var pixels: PixelImage
    var image: CGImage
}

/// Decodes photos into the measuring format.
///
/// Uses ImageIO's thumbnail path so a 48 MP HEIC is decoded straight to the working size
/// (orientation applied, no full-resolution bitmap), and renders into Display P3 so the
/// wide-gamut reds of iPhone photos reach the colour maths unclipped.
nonisolated enum PhotoLoader {
    /// Long edge of the working image. A bean is then a few dozen pixels across, plenty for a
    /// median, and the sorter's full-frame passes stay well under a second.
    static let maxPixelSize = 1600

    enum LoadError: Error {
        case undecodable, contextFailed
    }

    static func load(data: Data) throws -> LoadedPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw LoadError.undecodable }
        return try load(source: source)
    }

    static func load(url: URL) throws -> LoadedPhoto {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw LoadError.undecodable }
        return try load(source: source)
    }

    static func thumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source: source, maxPixelSize: maxPixelSize)
    }

    private static func thumbnail(source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func load(source: CGImageSource) throws -> LoadedPhoto {
        guard let image = thumbnail(source: source, maxPixelSize: maxPixelSize) else { throw LoadError.undecodable }
        return LoadedPhoto(pixels: try pixels(from: image), image: image)
    }

    /// Renders any CGImage into 8-bit RGBX in Display P3.
    static func pixels(from image: CGImage) throws -> PixelImage {
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let ok = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw LoadError.contextFailed }
        return PixelImage(width: w, height: h, space: .displayP3, rgba: rgba)
    }
}
