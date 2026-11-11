import Foundation
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// One test file described in Tests/eval/cases.json.
struct NamingCase: Decodable {
    let id: String
    let file: String
    var source: [String]? = nil
    var created: String? = nil
    var title: String? = nil
    var lines: [[Line]]? = nil      // [[text, fontSize]]
    var scanned: Bool? = nil
    var network: Bool? = nil
    var zipFiles: [String]? = nil   // for .zip cases: names inside the archive
    let expect: [String]

    enum Line: Decodable {
        case text(String), size(Double)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .text(s) } else { self = .size(try c.decode(Double.self)) }
        }
    }

    var textLines: [(String, CGFloat)] {
        (lines ?? []).compactMap { pair in
            guard pair.count == 2, case .text(let t) = pair[0], case .size(let s) = pair[1] else { return nil }
            return (t, CGFloat(s))
        }
    }
}

/// Builds realistic test files: PDFs (with or without a text layer), images, download-source data, dates.
enum Fixtures {
    static func make(_ c: NamingCase, in dir: URL) throws -> URL {
        let url = dir.appending(path: c.file)
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            if c.scanned == true { try scannedPDF(c, url) } else { try pdf(c, url) }
        } else if ext == "docx" {
            let body = c.textLines.map { "<w:p><w:r><w:t>\(xmlEscape($0.0))</w:t></w:r></w:p>" }.joined()
            try zip(url, ["word/document.xml": "<w:document><w:body>\(body)</w:body></w:document>",
                          "docProps/core.xml": coreXML(c.title)])
        } else if ext == "pptx" {
            let lines = c.textLines.map { "<a:p><a:r><a:t>\(xmlEscape($0.0))</a:t></a:r></a:p>" }
            try zip(url, ["ppt/slides/slide1.xml": "<p:sld>\(lines.prefix(2).joined())</p:sld>",
                          "ppt/slides/slide2.xml": "<p:sld>\(lines.dropFirst(2).joined())</p:sld>",
                          "docProps/core.xml": coreXML(c.title)])
        } else if ext == "ipynb" {
            let t = c.textLines.map(\.0)
            let cells: [[String: Any]] = [["cell_type": "markdown", "source": ["# " + (t.first ?? "")]]]
                + t.dropFirst().map { ["cell_type": "code", "source": [$0]] }
            try JSONSerialization.data(withJSONObject: ["cells": cells, "nbformat": 4]).write(to: url)
        } else if ext == "zip" {
            try zip(url, Dictionary(uniqueKeysWithValues: (c.zipFiles ?? []).map { ($0, "x") }))
        } else {
            try image(c, url, size: CGSize(width: 1600, height: 1200))
        }
        if let s = c.source { setSource(url, s) }
        let date = day(c.created ?? "2026-11-04")
        try (url as NSURL).setResourceValues([.creationDateKey: date, .contentModificationDateKey: date])
        return url
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func coreXML(_ title: String?) -> String {
        "<cp:coreProperties>" + (title.map { "<dc:title>\(xmlEscape($0))</dc:title>" } ?? "") + "</cp:coreProperties>"
    }

    /// Build a zip from {path inside zip: content} using the system zip tool.
    static func zip(_ url: URL, _ files: [String: String]) throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "filed-zip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        for (path, content) in files {
            let f = tmp.appending(path: path)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: f, atomically: true, encoding: .utf8)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.arguments = ["-qr", url.path, "."]
        p.currentDirectoryURL = tmp
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Err("zip") }
    }

    static func day(_ s: String) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)!
    }

    /// What browsers write when you download a file.
    static func setSource(_ url: URL, _ sources: [String]) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: sources, format: .binary, options: 0)
        else { return }
        _ = data.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, data.count, 0, 0) }
    }

    static func text(_ c: NamingCase) -> NSAttributedString {
        let s = NSMutableAttributedString()
        for (t, size) in c.textLines {
            let style = NSMutableParagraphStyle(); style.paragraphSpacing = size * 0.6
            s.append(NSAttributedString(string: t + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: size >= 18 ? .bold : .regular),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style,
            ]))
        }
        return s
    }

    static func draw(_ s: NSAttributedString, in ctx: CGContext, rect: CGRect) {
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(s), CFRange(),
                                             CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
    }

    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter

    static func pdf(_ c: NamingCase, _ url: URL) throws {
        var box = page
        var info: [CFString: Any] = [:]
        if let t = c.title { info[kCGPDFContextTitle] = t }
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { throw Err("pdf") }
        ctx.beginPDFPage(nil)
        draw(text(c), in: ctx, rect: page.insetBy(dx: 60, dy: 60))
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// A PDF that is just a picture of text, like a phone scan. No text layer.
    static func scannedPDF(_ c: NamingCase, _ url: URL) throws {
        let img = try bitmap(c, size: CGSize(width: 1224, height: 1584))
        var box = page
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Err("pdf") }
        ctx.beginPDFPage(nil)
        ctx.draw(img, in: page)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    static func image(_ c: NamingCase, _ url: URL, size: CGSize) throws {
        let img = try bitmap(c, size: size)
        let type: UTType = switch url.pathExtension.lowercased() {
            case "jpg", "jpeg": .jpeg
            case "heic": .heic
            default: .png
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw Err("image") }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw Err("image write") }
    }

    static func bitmap(_ c: NamingCase, size: CGSize) throws -> CGImage {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Err("bitmap") }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(origin: .zero, size: size))
        let scale = size.width / 612
        ctx.scaleBy(x: scale, y: scale)
        draw(text(c), in: ctx, rect: CGRect(x: 0, y: 0, width: 612, height: size.height / scale).insetBy(dx: 40, dy: 40))
        guard let img = ctx.makeImage() else { throw Err("bitmap") }
        return img
    }

    struct Err: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = "could not create \(d)" }
    }
}
