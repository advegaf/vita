import UIKit
import PDFKit

/// Prepares a captured/imported lab source for both the Claude request and local
/// storage. Re-encoding through UIImage → JPEG inherently DROPS EXIF/GPS metadata
/// (only pixels are redrawn) and downscales to keep the request + the on-device
/// external store modest. PDFs pass through unchanged.
enum LabImageEncoder {
    static func prepare(data: Data, mediaTypeHint: String?) -> (data: Data, mediaType: String) {
        // PDF passthrough (by hint or %PDF magic bytes).
        if mediaTypeHint == "application/pdf" || data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return (data, "application/pdf")
        }
        if let img = UIImage(data: data) {
            let scaled = downscaled(img, maxLongEdge: 2000)
            if let jpeg = scaled.jpegData(compressionQuality: 0.8) {
                return (jpeg, "image/jpeg")          // EXIF/GPS gone
            }
        }
        return (data, mediaTypeHint ?? "image/jpeg")
    }

    static func pdfPageCount(_ data: Data) -> Int { PDFDocument(data: data)?.pageCount ?? 0 }

    /// True if the PDF has a real selectable text layer (sampled over the first few pages).
    /// Text PDFs read fastest + most accurately as a native `document` block; only scans
    /// (no text) need rasterizing. The >20-char threshold ignores a stray watermark.
    static func pdfHasTextLayer(_ data: Data, sample: Int = 3) -> Bool {
        guard let doc = PDFDocument(data: data) else { return false }
        for i in 0..<min(doc.pageCount, sample) {
            if let s = doc.page(at: i)?.string,
               s.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 { return true }
        }
        return false
    }

    /// Renders the first `maxPages` PDF pages to downscaled white-background JPEGs so a
    /// scanned / image-only PDF can be read through the proven image path. Uses PDFKit's
    /// `thumbnail(of:for:)`, which correctly handles non-zero mediaBox origins and page
    /// rotation (the previous manual CGContext transform drew rotated/offset pages
    /// off-canvas → blank images → "no values found"). Empty if the PDF can't be opened.
    // maxPages 20 (was 8): real lab reports run past 8 pages, and the old cap
    // silently dropped every marker on pages 9+ while the UI claimed a full read.
    static func imagesFromPDF(_ data: Data, maxPages: Int = 20, maxLongEdge: CGFloat = 2000) -> [Data] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var out: [Data] = []
        for i in 0..<min(doc.pageCount, maxPages) {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            let rotated = page.rotation == 90 || page.rotation == 270
            let w = rotated ? b.height : b.width
            let h = rotated ? b.width : b.height
            let longest = max(w, h)
            guard longest > 0 else { continue }
            let scale = min(2.0, maxLongEdge / longest)
            let px = CGSize(width: w * scale, height: h * scale)
            let thumb = page.thumbnail(of: px, for: .mediaBox)   // handles origin + rotation
            // Redraw at scale 1 to bound the uploaded pixel size (thumbnail is screen-scale).
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let bounded = UIGraphicsImageRenderer(size: px, format: fmt).image { ctx in
                UIColor.white.set(); ctx.fill(CGRect(origin: .zero, size: px))
                thumb.draw(in: CGRect(origin: .zero, size: px))
            }
            if let jpeg = bounded.jpegData(compressionQuality: 0.8) { out.append(jpeg) }
        }
        return out
    }

    static func downscaled(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }
        let scale = maxLongEdge / longEdge
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
