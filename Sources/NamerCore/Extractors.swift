import Foundation
import PDFKit
import Vision
import ImageIO

/// Cheap, bounded readers. None of them ever looks past page 2 or a fixed text budget.
enum Extract {
    static let snippetBudget = 1_200   // characters of body text we ever keep
    static let headlineMax = 160

    // MARK: Stage 1 — where it came from (extended attribute macOS writes on download)

    static func sourceURLs(_ url: URL) -> [String] {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let len = getxattr(url.path, name, nil, 0, 0, 0)
        guard len > 0 else { return [] }
        var data = Data(count: len)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, len, 0, 0) }
        guard read == len,
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
        else { return [] }
        return list
    }

    // MARK: Dates

    /// Date embedded in the filename (2026-11-04, 20261104, 2026_11_04), else file creation date.
    static func date(_ url: URL, stem: String) -> Date? {
        let pattern = #"(20\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])"#
        if let m = stem.firstMatch(of: try! Regex(pattern)),
           let y = Int(m.output[1].substring ?? ""), let mo = Int(m.output[2].substring ?? ""),
           let d = Int(m.output[3].substring ?? "") {
            return Calendar.current.date(from: DateComponents(year: y, month: mo, day: d))
        }
        return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    // MARK: Stage 3 + 4 — PDF metadata, then page 1 only

    struct PDFInfo { var title: String?; var headline: String?; var snippet: String?; var hasText: Bool }

    static func pdf(_ url: URL) -> PDFInfo? {
        guard let doc = PDFDocument(url: url) else { return nil }
        let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        guard let page = doc.page(at: 0) else { return PDFInfo(title: title, hasText: false) }

        var snippet = String((page.string ?? "").prefix(snippetBudget))
        if snippet.count < 200, doc.pageCount > 1, let p2 = doc.page(at: 1)?.string {
            snippet += "\n" + p2.prefix(snippetBudget - snippet.count)
        }
        let hasText = snippet.trimmingCharacters(in: .whitespacesAndNewlines).count > 20
        return PDFInfo(title: title,
                       headline: hasText ? largestText(page.attributedString) : nil,
                       snippet: hasText ? snippet : nil,
                       hasText: hasText)
    }

    /// The title of a document is almost always its biggest text. No ML needed.
    static func largestText(_ s: NSAttributedString?) -> String? {
        guard let s, s.length > 0 else { return nil }
        // Only scan the top part of the page — titles are not at the bottom.
        let range = NSRange(location: 0, length: min(s.length, 3_000))
        var runs: [(size: CGFloat, text: String)] = []
        s.enumerateAttribute(.font, in: range) { value, r, _ in
            guard let font = value as? NSFont else { return }
            runs.append((font.pointSize, (s.string as NSString).substring(with: r)))
        }
        guard let maxSize = runs.map(\.size).max() else { return nil }
        // Body-text-sized "largest" means there is no real headline.
        let sizes = runs.map(\.size).sorted()
        let median = sizes[sizes.count / 2]
        guard maxSize >= median * 1.15 else { return nil }

        let text = runs.filter { $0.size >= maxSize * 0.95 }.map(\.text).joined(separator: " ")
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return clean.isEmpty ? nil : String(clean.prefix(headlineMax))
    }

    // MARK: Stage 5 — OCR, only for images and scanned PDFs (page 1)

    static func ocr(image url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,   // downsample: faster, still readable
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return ocr(img)
    }

    static func ocr(pdfFirstPage url: URL) -> String? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let thumb = page.thumbnail(of: CGSize(width: 1600, height: 1600), for: .mediaBox)
        guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return ocr(cg)
    }

    /// What a photo shows, from Apple's built-in on-device classifier. Fast (~20 ms) and needs no text.
    static func labels(image url: URL) -> [String] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 600,
              ] as CFDictionary) else { return [] }
        let req = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: img).perform([req])
        // Very broad labels say nothing a filename needs.
        let generic: Set<String> = ["structure", "indoor", "outdoor", "material", "people", "adult", "document",
                                    "screenshot", "text", "art", "illustrations", "graphic", "shape"]
        return (req.results ?? [])
            .filter { $0.confidence > 0.3 && !generic.contains($0.identifier) }
            .prefix(3)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    private static func ocr(_ img: CGImage) -> String? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: img).perform([req])
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : String(text.prefix(snippetBudget))
    }

    // MARK: Junk detection

    /// Titles that tools stamp on documents and that say nothing about the content.
    static func isJunkTitle(_ t: String?, stem: String) -> Bool {
        guard let t = t?.trimmingCharacters(in: .whitespacesAndNewlines), t.count >= 3 else { return true }
        let l = t.lowercased()
        let junkPrefixes = ["microsoft word", "microsoft powerpoint", "untitled", "document", "slide 1", "print", "pdf"]
        if junkPrefixes.contains(where: { l.hasPrefix($0) }) { return true }
        if [".doc", ".docx", ".pdf", ".ppt", ".pptx", ".tex", ".dvi"].contains(where: { l.hasSuffix($0) }) { return true }
        if l == stem.lowercased() { return true }
        if t.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace }) { return true }
        return false
    }

    /// Is the current filename already meaningful? Then we leave the file alone.
    static func isJunkName(_ stem: String) -> Bool {
        let letters = stem.filter(\.isLetter).count
        let digits = stem.filter(\.isNumber).count
        if letters == 0 { return true }
        if digits >= letters { return true }                       // 1234567_2026-11-04_124701
        let l = stem.lowercased()
        let junk = ["download", "document", "file", "untitled", "scan", "img_", "img-", "image", "screenshot",
                    "screen shot", "export", "print", "attachment", "unnamed", "unknown", "view", "get", "fatura",
                    "invoice", "whatsapp image", "whatsapp video", "photo", "pxl_", "dsc", "dcim", "anfrage"]
        if junk.contains(where: { l.hasPrefix($0) }) { return true }
        // Long random-looking tokens (hashes, uuids)
        if stem.count >= 16, !stem.contains(" "),
           stem.filter({ "aeiou".contains($0.lowercased()) }).count * 6 < letters { return true }
        return false
    }
}
