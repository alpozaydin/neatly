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
    public var suggestedFolder: String?   // where namer proposed to put it (nil = Downloads)
    public var chosenFolder: String?      // where you actually put it
    public var auto: Bool?                // saved by the countdown, not by you: not a signal of what you want
    public var context: String?           // one line on what the file was about, for finding similar files later

    public init(original: String, suggested: String, chosen: String, via: String, source: String?, title: String?,
                suggestedFolder: String? = nil, chosenFolder: String? = nil, auto: Bool? = nil, context: String? = nil) {
        self.original = original; self.suggested = suggested; self.chosen = chosen
        self.via = via; self.source = source; self.title = title
        self.suggestedFolder = suggestedFolder; self.chosenFolder = chosenFolder
        self.auto = auto; self.context = context
    }

    /// What the file was about. Older entries have no context: fall back to the title and namer's guess.
    var about: String {
        context ?? [title, suggested.replacingOccurrences(of: "-", with: " "), source.map { "from \($0)" }]
            .compactMap { $0 }.joined(separator: ". ")
    }

    var suggestedFirstWord: String { suggested.split(separator: "-").first.map(String.init) ?? suggested }

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
