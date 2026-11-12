import Foundation

/// Step 0: should this file be renamed at all? Decided before any content is read.
/// The rule is conservative: a human-chosen or already-good name is never touched.
public enum Decision: Sendable, Equatable {
    case rename(why: String)
    case keep(why: String)

    public var shouldRename: Bool { if case .rename = self { true } else { false } }

    /// Set on a file when the user renames it themselves or dismisses a suggestion.
    /// From then on the file is theirs: no automatic suggestion ever again.
    static let keepAttr = "dev.neatly.keep"

    public static func markKeep(_ url: URL) {
        let v: [UInt8] = [49]   // "1"
        _ = setxattr(url.path, keepAttr, v, v.count, 0, 0)
    }

    static func hasKeepMark(_ url: URL) -> Bool {
        ([keepAttr] + ["dev.filed.keep", "dev.namer.keep"]).contains { getxattr(url.path, $0, nil, 0, 0, 0) > 0 }   // + old names
    }

    /// `explicit` = the user asked for this file (hotkey / CLI --force): only their own keep mark stops us.
    public static func make(for url: URL, explicit: Bool = false) -> Decision {
        let stem = url.deletingPathExtension().lastPathComponent
        if hasKeepMark(url) { return .keep(why: "you chose this name") }
        if Rename.originalName(url) != nil, !explicit { return .keep(why: "already renamed by namer") }
        if explicit { return .rename(why: "requested") }
        if let junk = junkReason(stem) { return .rename(why: junk) }
        return .keep(why: "name already meaningful")
    }

    /// Words that say nothing about a file on their own.
    static let fillerWords: Set<String> = [
        "main", "paper", "final", "draft", "new", "old", "copy", "version", "rev", "edit", "edited", "output", "out",
        "temp", "tmp", "test", "doc", "docs", "pdf", "file", "files", "untitled", "document", "download", "downloads",
        "image", "images", "img", "photo", "pic", "screenshot", "screen", "shot", "at", "am", "pm", "scan", "export",
        "print", "unknown", "unnamed", "attachment", "view", "get", "the", "of", "and", "my", "kopya", "yeni", "son",
        "archive", "slides", "notes", "recording", "gmt", "zoom", "untitled", "presentation", "spreadsheet", "belge",
        "sample", "example", "kb", "mb", "gb", "url", "index", "page", "content", "default", "data",
    ]

    /// Why a filename is meaningless, or nil if it looks like a real name.
    static func junkReason(_ stem: String) -> String? {
        let l = stem.lowercased()
        let letters = stem.filter(\.isLetter).count
        let digits = stem.filter(\.isNumber).count

        if letters == 0 { return "only numbers/symbols" }

        // Names cameras, phones, browsers and web apps generate.
        let generated = ["download", "document", "untitled", "unknown", "unnamed", "file", "scan", "img_", "img-",
                         "image", "images", "photo", "screenshot", "screen shot", "pxl_", "dsc", "dcim", "export",
                         "print", "attachment", "view", "get", "whatsapp image", "whatsapp video", "telegram",
                         "signal-", "fatura", "invoice", "receipt", "blob", "camscanner", "scanned", "genius scan", "adobe scan"]
        if let g = generated.first(where: { l.hasPrefix($0) }) {
            // "IMG_4009" / "WhatsApp Image … at 13.45" are junk; "imagenet-results", "invoice-turkcell" are not.
            let rest = l.dropFirst(g.count).filter(\.isLetter)
            if rest.count < 4 { return "generated name (\(g)…)" }
        }

        // An id is a long run of digits (2633477_2026-11-04, 1730987654321) or a name with hardly any letters.
        // A short word + number is a person's convention ("egg-001", "lab-02"), and "v1.6.1457" is a version.
        let noVersion = stem.replacing(try! Regex(#"[vV]\d+(\.\d+)+"#), with: "")   // "v1.6.1457" is a version
        let dateOrTime = noVersion.contains(try! Regex(#"\d{1,4}[-._]\d{1,2}[-._]\d{2,4}|\b\d{1,2}[.:]\d{2}([.:]\d{2})?\b"#))
        let longRun = dateOrTime || noVersion.split { !$0.isNumber }.contains { $0.count >= 5 }
        if digits >= letters && (longRun || letters <= 2) { return "mostly numbers / ids" }

        // Every word is filler: main.pdf, paper_final_v3 (1), Screen Shot … at 1.00.00 PM
        let words = l.split { !$0.isLetter }.map(String.init)
        if !words.isEmpty, words.allSatisfy({ fillerWords.contains($0) || $0.count == 1 }) {
            return "only generic words"
        }

        // Hex strings (md5, sha, uuids): letters a–f and digits only, long.
        if l.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { t in
            t.count >= 16 && t.allSatisfy({ $0.isHexDigit }) && t.contains(where: \.isNumber) }) {
            return "random-looking id (hash)"
        }
        // Long tokens with almost no vowels: hashes, uuids, tracking ids.
        let tokens = l.split { !$0.isLetter && !$0.isNumber }
        if let t = tokens.first(where: { $0.count >= 12 && $0.filter { "aeiou".contains($0) }.count * 5 < $0.count }) {
            return "random-looking id (\(t.prefix(8))…)"
        }
        return nil
    }
}
