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
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect phone rotation
            kCGImageSourceThumbnailMaxPixelSize: 2400,          // handwriting needs more pixels than print
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        // Photos get the slow, accurate recognizer: it can read handwriting; .fast cannot.
        return ocr(img, accurate: true)
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
                                    "screenshot", "text", "art", "illustrations", "graphic", "shape",
                                    "handwriting", "paper", "printed_page", "diagram"]
        return (req.results ?? [])
            .filter { $0.confidence > 0.3 && !generic.contains($0.identifier) }
            .prefix(3)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    private static func ocr(_ img: CGImage, accurate: Bool = false) -> String? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = accurate ? .accurate : .fast
        req.usesLanguageCorrection = accurate
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
}

// MARK: Office files, notebooks, archives, links — same rule: titles and the first page only.

extension Extract {
    /// Read one entry of a zip (docx/pptx are zips) without unpacking the rest. Capped at `max` bytes.
    static func zipEntry(_ url: URL, _ path: String, max: Int = 200_000) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", url.path, path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readData(ofLength: max)
        p.terminate()
        return String(data: data, encoding: .utf8)
    }

    /// Text inside XML tags like <a:t>…</a:t> (PowerPoint) or <w:t>…</w:t> (Word).
    static func xmlText(_ xml: String, tag: String) -> [String] {
        let re = try! Regex("<\(tag)(?: [^>]*)?>([^<]*)</\(tag)>")
        return xml.matches(of: re).compactMap { $0.output[1].substring.map(String.init) }.filter { !$0.isEmpty }
    }

    static func officeTitle(_ url: URL) -> String? {
        guard let core = zipEntry(url, "docProps/core.xml") else { return nil }
        return xmlText(core, tag: "dc:title").first
    }

    /// Word: title field + first ~1,200 characters. The first paragraph is usually the heading.
    static func docx(_ url: URL) -> PDFInfo? {
        guard let xml = zipEntry(url, "word/document.xml") else { return nil }
        let paragraphs = xml.components(separatedBy: "</w:p>").map { xmlText($0, tag: "w:t").joined() }.filter { !$0.isEmpty }
        let text = String(paragraphs.joined(separator: "\n").prefix(snippetBudget))
        return PDFInfo(title: officeTitle(url), headline: paragraphs.first.map { String($0.prefix(headlineMax)) },
                       snippet: text.isEmpty ? nil : text, hasText: !text.isEmpty)
    }

    /// PowerPoint: title field + slide 1 (title slide) + slide 2.
    static func pptx(_ url: URL) -> PDFInfo? {
        let s1 = zipEntry(url, "ppt/slides/slide1.xml").map { xmlText($0, tag: "a:t") } ?? []
        let s2 = zipEntry(url, "ppt/slides/slide2.xml").map { xmlText($0, tag: "a:t") } ?? []
        let text = String((s1 + s2).joined(separator: "\n").prefix(snippetBudget))
        guard !text.isEmpty || officeTitle(url) != nil else { return nil }
        return PDFInfo(title: officeTitle(url), headline: s1.first, snippet: text, hasText: !text.isEmpty)
    }

    /// Jupyter / Colab: the first markdown heading, else the first cells.
    static func notebook(_ url: URL) -> PDFInfo? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = json["cells"] as? [[String: Any]] else { return nil }
        func source(_ c: [String: Any]) -> String {
            (c["source"] as? [String])?.joined() ?? (c["source"] as? String) ?? ""
        }
        let first = cells.prefix(5).map(source).joined(separator: "\n")
        let heading = cells.lazy.filter { $0["cell_type"] as? String == "markdown" }.map(source)
            .compactMap { $0.split(separator: "\n").first { $0.hasPrefix("#") } }.first
            .map { $0.drop(while: { $0 == "#" || $0 == " " }) }.map(String.init)
        return PDFInfo(title: nil, headline: heading, snippet: String(first.prefix(snippetBudget)), hasText: !first.isEmpty)
    }

    /// Archives: list the names inside (never unpack). One top folder → that is the name.
    static func zipListing(_ url: URL) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        p.arguments = ["-1", url.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readData(ofLength: 20_000)
        p.terminate()
        return (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("__MACOSX") && !$0.hasSuffix(".DS_Store") }
            .prefix(40).map { $0 }
    }

    /// Meaningful words in the download link: kaggle.com/datasets/user/titanic → "titanic".
    static func linkHint(_ sources: [String]) -> String? {
        let skip: Set<String> = ["download", "downloads", "api", "v1", "files", "file", "datasets", "dataset", "view",
                                 "attachment", "pluginfile.php", "mod", "resource", "content", "u", "0", "raw", "zip",
                                 "refs", "heads", "main", "master", "archive", "proxy", "get.php", "main.php", "index.php"]
        for s in sources {
            guard let u = URL(string: s), let host = u.host() else { continue }
            if host.contains("googleusercontent") || host.contains("mail.") { continue }
            let parts = u.pathComponents.filter { $0 != "/" }
                .filter { !skip.contains($0.lowercased()) && Decision.junkReason($0) == nil && $0.count >= 3 }
            if let last = parts.last { return last.removingPercentEncoding ?? last }
        }
        return nil
    }
}
