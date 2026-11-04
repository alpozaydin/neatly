import Foundation

/// Every time you change a suggestion, we keep (what we saw, what we suggested, what you chose).
/// This is the data the "learn my style" features use. One JSON object per line, readable, deletable.
public struct Correction: Codable, Sendable {
    public var date = Date()
    public var original: String     // filename before
    public var suggested: String    // what namer proposed
    public var chosen: String       // what you typed ("" = you kept the original name)
    public var via: String
    public var source: String?
    public var title: String?

    public init(original: String, suggested: String, chosen: String, via: String, source: String?, title: String?) {
        self.original = original; self.suggested = suggested; self.chosen = chosen
        self.via = via; self.source = source; self.title = title
    }

    public static var fileURL: URL {
        StyleProfile.fileURL.deletingLastPathComponent().appending(path: "corrections.jsonl")
    }

    public func save() {
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard var line = try? enc.encode(self) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: url) }
    }

    public static func all() -> [Correction] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? dec.decode(Correction.self, from: Data($0.utf8)) }
    }
}
