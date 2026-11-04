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
        } else {
            try image(c, url, size: CGSize(width: 1600, height: 1200))
        }
        if let s = c.source { setSource(url, s) }
        let date = day(c.created ?? "2026-11-04")
        try (url as NSURL).setResourceValues([.creationDateKey: date, .contentModificationDateKey: date])
        return url
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
