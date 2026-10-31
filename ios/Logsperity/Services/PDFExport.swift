import SwiftUI

/// Renders a report to a PDF on the device (design §15: print, email and share work offline).
@MainActor
enum PDFExport {
    /// US Letter, portrait, in points.
    static let pageSize = CGSize(width: 612, height: 792)

    static func render<V: View>(_ view: V, fileName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).pdf")
        let renderer = ImageRenderer(content: view.frame(width: pageSize.width - 72).padding(36).environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            // Slice the tall rendering into Letter pages.
            var offset: CGFloat = 0
            while offset < size.height {
                ctx.beginPDFPage(nil)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: pageSize.height - size.height + offset)
                draw(ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
                offset += pageSize.height
            }
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}
