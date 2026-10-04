import SwiftUI
import UIKit

/// A printable sorting mat: a dark panel with a white border, for the beans that don't show
/// up against white paper.
struct MatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // The page in miniature.
                    Rectangle()
                        .fill(.white)
                        .aspectRatio(SortingMat.page.width / SortingMat.page.height, contentMode: .fit)
                        .overlay {
                            GeometryReader { proxy in
                                Rectangle()
                                    .fill(Color(white: 0.08))
                                    .padding(proxy.size.width * SortingMat.margin / SortingMat.page.width)
                            }
                        }
                        .frame(maxHeight: 280)
                        .frame(maxWidth: .infinity)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .accessibilityLabel("A page with a large dark panel and a white border")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("White, cream and very pale beans don’t show up against white paper. Print this page, spread those beans on the dark panel, and keep some of the white border in the shot — that border is what their colours are measured against.")
                        Text("Coloured and dark beans don’t need it: plain white paper is their mat.")
                        Text("A printed colour chart wouldn’t help. Your printer’s colours aren’t known precisely, and nothing here needs absolute colour — only that paper and beans are measured the same way, against the same white.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)

                    HStack {
                        Button("Print", systemImage: "printer") { SortingMat.print() }
                            .buttonStyle(.borderedProminent)
                        if let file {
                            ShareLink("Share PDF", item: file)
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.plane)
            .navigationTitle("Sorting Mat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                let url = FileManager.default.temporaryDirectory.appending(path: "Beanbox sorting mat.pdf")
                if (try? SortingMat.pdf().write(to: url, options: .atomic)) != nil { file = url }
            }
        }
    }
}

enum SortingMat {
    /// US Letter where that is the paper people have, A4 everywhere else; in points.
    static var page: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
    }

    /// The white border, in points. Wider than any printer's unprintable edge, and wide enough
    /// to still be in a photo framed on the dark panel.
    static let margin: CGFloat = 60

    static func pdf() -> Data {
        let bounds = CGRect(origin: .zero, size: page)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let panel = bounds.insetBy(dx: margin, dy: margin)
            // Not full black: a little less toner glares less under a lamp.
            UIColor(white: 0.08, alpha: 1).setFill()
            UIBezierPath(rect: panel).fill()
            let caption = "Beanbox sorting mat — pale beans go on the dark panel. Keep some of this white border in the photo."
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor(white: 0.45, alpha: 1),
            ]
            (caption as NSString).draw(at: CGPoint(x: margin, y: bounds.height - margin + 14), withAttributes: attributes)
        }
    }

    static func print() {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "Beanbox sorting mat"
        info.outputType = .grayscale
        controller.printInfo = info
        controller.printingItem = pdf()
        _ = controller.present(animated: true, completionHandler: nil)
    }
}
