import Foundation

/// How a person names files, learned from names they already chose. Only names are read, never contents.
public struct StyleProfile: Codable, Sendable, Equatable {
    public var separator = "-"       // "-", "_", " "
    public var lowercase = true      // false → Title Case
    public var suffix: String?       // e.g. initials: "MAO" in "CivCore AI Model - MAO"
    public var learnedFrom = 0       // how many names this is based on
    public var examples: [String] = []

    public static let standard = StyleProfile()

    public init() {}

    /// Turn a canonical name (lowercase-kebab) into this person's style.
    public func render(_ kebab: String) -> String {
        var parts = kebab.split(separator: "-").map(String.init)
        if !lowercase {
            parts = parts.map { $0.first?.isLetter == true ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
        }
        var out = parts.joined(separator: separator)
        if let suffix { out += (separator == " " ? " - " : separator) + suffix }
        return out
    }

    // MARK: Learning

    public struct FolderStyle: Sendable {
        public let folder: String
        public let profile: StyleProfile
    }

    /// Learn one profile per folder, plus an overall one: each folder gets one vote, so one big folder can't win alone.
    /// `agreement` is the winning style's share of folders; below ~0.6 the person uses different styles in different places.
    public static func learn(roots: [URL], maxDepth: Int = 3)
        -> (overall: StyleProfile, agreement: Double, folders: [FolderStyle]) {
        var byFolder: [String: [String]] = [:]
        for root in roots {
            walk(root, depth: 0, maxDepth: maxDepth) { url in
                guard let name = chosenName(url) else { return }
                byFolder[url.deletingLastPathComponent().path, default: []].append(name)
            }
        }
        let folders = byFolder.filter { $0.value.count >= 3 }
            .map { FolderStyle(folder: $0.key, profile: learn(names: $0.value)) }
            .sorted { $0.folder < $1.folder }
        var overall = learn(names: byFolder.values.flatMap { $0 })
        var votes: [String: Int] = [:]
        for f in folders { votes["\(f.profile.separator)|\(f.profile.lowercase)", default: 0] += 1 }
        guard let (key, n) = votes.max(by: { $0.value < $1.value }) else { return (overall, 0, folders) }
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        overall.separator = String(parts[0]); overall.lowercase = parts[1] == "true"; overall.suffix = nil
        return (overall, Double(n) / Double(folders.count), folders)
    }

    public static func learn(names: [String]) -> StyleProfile {
        var p = StyleProfile()
        p.learnedFrom = names.count
        p.examples = Array(names.prefix(5))
        guard !names.isEmpty else { return p }

        // Separator: vote among names that have more than one word.
        var votes: [String: Int] = [:]
        for n in names {
            let counts = ["-": n.filter { $0 == "-" }.count, "_": n.filter { $0 == "_" }.count,
                          " ": n.filter { $0 == " " }.count]
            if let best = counts.max(by: { $0.value < $1.value }), best.value > 0 { votes[best.key, default: 0] += 1 }
        }
        p.separator = votes.max(by: { $0.value < $1.value })?.key ?? "-"

        // Case: Title Case only counts words like "Model"; acronyms (CENG315, MAO, AI) say nothing.
        let words = names.flatMap { $0.split(whereSeparator: { "-_ ".contains($0) }) }
            .filter { $0.first?.isLetter == true && $0 != $0.uppercased() }
        let titled = words.filter { $0.first!.isUppercase }.count
        p.lowercase = words.isEmpty || Double(titled) / Double(words.count) < 0.5

        // Suffix: the same initials (2–4 capitals) ending at least 2 names and 40% of them. "CivCore Model - MAO"
        var last: [String: Int] = [:]
        for n in names {
            if let t = n.split(whereSeparator: { "-_ ".contains($0) }).last, (2...4).contains(t.count),
               t.allSatisfy({ $0.isUppercase }) {
                last[String(t), default: 0] += 1
            }
        }
        if let (t, c) = last.max(by: { $0.value < $1.value }), c >= 2, Double(c) / Double(names.count) >= 0.4 {
            p.suffix = t
        }
        return p
    }

    // MARK: Which names count as "chosen by the user"

    static let skipDirs: Set<String> = ["node_modules", "venv", ".venv", "__pycache__", "build", "dist", "Library",
                                        "Applications", "site-packages", "DerivedData"]
    static let codeExts: Set<String> = ["py", "c", "h", "cpp", "swift", "js", "ts", "java", "go", "rs", "sh", "json",
                                        "toml", "yaml", "yml", "lock", "txt", "md", "o", "pyc", "ipynb", "html", "css"]
    static let boring: Set<String> = ["readme", "license", "requirements", "pyproject", "makefile", "data", "tests",
                                      "test", "examples", "common", "code", "src", "docs", "assets", "output", "logs"]

    /// The name's stem if it looks like something a person typed; nil for code, generated and long titles.
    static func chosenName(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if codeExts.contains(ext) { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        if boring.contains(stem.lowercased()) || Decision.junkReason(stem) != nil { return nil }
        let words = stem.split(whereSeparator: { "-_ ".contains($0) })
        guard (1...6).contains(words.count) else { return nil }   // 10-word textbook titles weren't typed by you
        return stem
    }

    static func walk(_ dir: URL, depth: Int, maxDepth: Int, _ visit: (URL) -> Void) {
        guard depth <= maxDepth,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return }
        for u in items {
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // Inside a code repo, names follow code conventions, not how you name documents.
            if isDir, FileManager.default.fileExists(atPath: u.appending(path: ".git").path) { continue }
            visit(u)
            if isDir, !skipDirs.contains(u.lastPathComponent) { walk(u, depth: depth + 1, maxDepth: maxDepth, visit) }
        }
    }

    // MARK: Storage — one small JSON file the user can read, edit or delete.

    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/namer/style.json")
    }

    public static func load() -> StyleProfile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(StyleProfile.self, from: data)
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Self.fileURL)
    }
}
