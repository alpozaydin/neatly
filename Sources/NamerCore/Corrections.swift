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

    /// Kept small: only the most recent answers matter for learning.
    static let keep = 2000

    public func save() {
        var entry = self
        if auto == true { entry.context = nil }   // nobody looked: nothing to learn, so don't keep what the file said
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard var line = try? enc.encode(entry) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: url) }
        trim(url, lines: Self.keep)
    }

    public static func all() -> [Correction] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? dec.decode(Correction.self, from: Data($0.utf8)) }
    }
}

/// Keep only the last `lines` lines of a log-like file (checked cheaply: only when it's grown past ~1.5× that).
public func trim(_ url: URL, lines: Int) {
    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size > lines * 300,
          let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    let all = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard all.count > lines * 3 / 2 else { return }
    try? (all.suffix(lines).joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
}

/// What neatly did, for the History window: every rename and move, newest last, so any of them can be reverted.
public struct HistoryEntry: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case download, screenshot, tidy }
    public var id = UUID()
    public var date = Date()
    public var kind: Kind
    public var from: String          // full path before
    public var to: String            // full path after
    public var host: String?         // where a download came from (for "Always do this")
    public var auto: Bool?           // done by the countdown, not by you
    public var reverted: Bool?

    public init(kind: Kind, from: URL, to: URL, host: String? = nil, auto: Bool = false) {
        self.kind = kind; self.from = from.path; self.to = to.path; self.host = host; self.auto = auto ? true : nil
    }
}

public enum History {
    public static var fileURL: URL { Correction.fileURL.deletingLastPathComponent().appending(path: "history.jsonl") }
    static let keep = 500

    public static func add(_ e: HistoryEntry) {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard var line = try? enc.encode(e) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: url) }
        trim(url, lines: keep)
    }

    public static func all() -> [HistoryEntry] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? dec.decode(HistoryEntry.self, from: Data($0.utf8)) }
    }

    static func save(_ list: [HistoryEntry]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let text = list.compactMap { (try? enc.encode($0)).map { String(decoding: $0, as: UTF8.self) } }.joined(separator: "\n")
        try? (text.isEmpty ? "" : text + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public enum RevertError: Error { case gone, nameTaken }

    /// Put the file back where and how it was. The file must still be where neatly left it.
    @discardableResult
    public static func revert(_ id: UUID) throws -> URL {
        var list = all()
        guard let i = list.firstIndex(where: { $0.id == id }) else { throw RevertError.gone }
        let now = URL(fileURLWithPath: list[i].to)
        guard FileManager.default.fileExists(atPath: now.path) else { throw RevertError.gone }
        guard let back = try? Rename.undo(now) else { throw RevertError.nameTaken }
        Decision.markKeep(back)   // put back on purpose: never handle it again
        list[i].reverted = true
        save(list)
        return back
    }

    /// Undone some other way (the review window's Undo): mark it so History doesn't offer it again.
    public static func markReverted(_ urls: [URL]) {
        let paths = Set(urls.map(\.path))
        var list = all()
        var changed = false
        for i in list.indices where paths.contains(list[i].to) && list[i].reverted != true { list[i].reverted = true; changed = true }
        if changed { save(list) }
    }

    /// The most recent download neatly handled that's still undoable (for the menu's "Undo Last Download").
    public static func lastDownload() -> HistoryEntry? {
        all().last { $0.kind == .download && $0.reverted != true && FileManager.default.fileExists(atPath: $0.to) }
    }

    /// "Forget my history": the learning log, this list and the last tidy. Settings and rules stay.
    public static func forgetAll() {
        let dir = fileURL.deletingLastPathComponent()
        for f in ["history.jsonl", "corrections.jsonl", "last-tidy.json"] { try? FileManager.default.removeItem(at: dir.appending(path: f)) }
    }
}
