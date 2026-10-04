import CoreGraphics
import SwiftUI

/// A photo with annotations drawn over it in photo-pixel coordinates. Taps report photo pixels
/// whatever the zoom.
struct PhotoCanvas: View {
    let image: CGImage
    /// 1 fits the photo to the width; more scrolls.
    var zoom: CGFloat = 1
    var onTap: ((CGPoint) -> Void)?
    /// Draws the annotations. `scale` is screen points per photo pixel.
    var annotate: (_ context: inout GraphicsContext, _ scale: Double) -> Void = { _, _ in }

    private var aspect: CGFloat { CGFloat(image.width) / CGFloat(image.height) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * zoom
            ScrollView([.horizontal, .vertical]) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: width, height: width / aspect)
                    .overlay {
                        Canvas { context, size in
                            annotate(&context, Double(size.width) / Double(image.width))
                        }
                        .allowsHitTesting(false)
                    }
                    .contentShape(.rect)
                    .onTapGesture { location in
                        let scale = CGFloat(image.width) / width
                        onTap?(CGPoint(x: location.x * scale, y: location.y * scale))
                    }
            }
            .scrollDisabled(zoom <= 1)
            .scrollBounceBehavior(.basedOnSize)
        }
        // At 1× the frame is exactly the photo; zoomed, the same frame becomes a window onto it.
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 10))
    }
}

/// Annotation drawing shared by the tabs. Photos can be any colour underneath, so every mark
/// is drawn twice: a casing under a lighter or coloured line.
enum Marks {
    static func ring(_ context: inout GraphicsContext, _ path: Path, color: Color, casing: Color = Theme.ink.opacity(0.65), width: CGFloat = 2.5) {
        context.stroke(path, with: .color(casing), lineWidth: width + 2)
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    /// A small label on a dark chip, centred at `point`.
    static func tag(_ context: inout GraphicsContext, _ text: String, at point: CGPoint, size: CGFloat = 11, emphasized: Bool = false) {
        let resolved = context.resolve(
            Text(text).font(.system(size: emphasized ? size + 2 : size, weight: .bold)).foregroundStyle(.white))
        let measured = resolved.measure(in: CGSize(width: 240, height: 40))
        let chip = CGRect(
            x: point.x - measured.width / 2 - 4, y: point.y - measured.height / 2 - 1,
            width: measured.width + 8, height: measured.height + 2)
        context.fill(Path(roundedRect: chip, cornerRadius: 4), with: .color(Theme.ink.opacity(emphasized ? 0.9 : 0.7)))
        context.draw(resolved, at: point, anchor: .center)
    }

    /// An ellipse rotated about its centre, in screen points.
    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, degrees: Double, scale: Double) -> Path {
        let rect = CGRect(x: -rx * scale, y: -ry * scale, width: 2 * rx * scale, height: 2 * ry * scale)
        let transform = CGAffineTransform(translationX: cx * scale, y: cy * scale).rotated(by: degrees * .pi / 180)
        return Path(ellipseIn: rect).applying(transform)
    }
}
