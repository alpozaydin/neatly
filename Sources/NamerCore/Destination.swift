import Foundation

/// Where should a file go? Only ever suggests folders that already exist (or that you chose before).
public enum Destination {
    public struct Folder: Sendable {
        public let url: URL
        public let name: String          // lowercased last component
        public let modified: Date
    }

    /// Folders a person organises files in: home folders except system ones, 3 levels deep, no code repos.
    /// Your home folder — or NEATLY_HOME in tests, so they never suggest (or move files into) your real folders.
    public static var homeRoot: URL {
        if let h = ProcessInfo.processInfo.environment["NEATLY_HOME"] { return URL(fileURLWithPath: h) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func index(home: URL = homeRoot) -> [Folder] {
        // Desktop and Documents are privacy-protected: scanning them from the background would pop macOS prompts.
        let skipTop: Set<String> = ["Library", "Applications", "Downloads", "Movies", "Music", "Pictures", "Public", "Desktop", "Documents",
                                    "src", "miniconda3", "anaconda3", "venvs", "node_modules", "go", "opt"]
        var out: [Folder] = []
        func walk(_ dir: URL, _ depth: Int) {
            guard depth <= 3, let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
            for u in items {
                let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard v?.isDirectory == true else { continue }
                if depth == 0, skipTop.contains(u.lastPathComponent) { continue }
                if FileManager.default.fileExists(atPath: u.appending(path: ".git").path) { continue }   // code repo
                if StyleProfile.skipDirs.contains(u.lastPathComponent) { continue }
                out.append(Folder(url: u, name: u.lastPathComponent.lowercased(), modified: v?.contentModificationDate ?? .distantPast))
                walk(u, depth + 1)
            }
        }
        walk(home, 0)
        return out
    }

    /// Best folder for a file named `name` (lowercase-kebab) with this evidence, or nil to stay in Downloads.
    public static func suggest(name: String, evidence e: Evidence, folders: [Folder],
                               history: [Correction] = Correction.all()) -> URL? {
        let first = name.split(separator: "-").first.map(String.init) ?? name

        // 1. Course files → the course's folder (newest one if there are several semesters).
        if first.range(of: #"^[a-z]{2,5}\d{3,4}$"#, options: .regularExpression) != nil {
            let matches = folders.filter { $0.name == first || $0.name.hasPrefix(first + "-") || $0.name.hasPrefix(first + "_") }
            if let best = matches.max(by: { $0.modified < $1.modified }) { return best.url }
        }

        // 2. You moved this kind of file somewhere before → same place.
        //    Same first word (transcript, invoice…) from the same website, or the same first word alone.
        let moved = history.reversed().filter { $0.chosenFolder != nil }
        if let c = moved.first(where: { $0.suggestedFirstWord == first && $0.source == e.sourceHost && e.sourceHost != nil })
            ?? moved.first(where: { $0.suggestedFirstWord == first }),
           let path = c.chosenFolder, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        // 3. A folder whose own name appears in the file: a "CivCore" deck → …/Companies/CivCore AI.
        let text = " " + Style.tokens([e.stem, e.metadataTitle, e.headline, e.bodySnippet.map { String($0.prefix(1200)) },
                                       e.sourceHost, name].compactMap { $0 }.joined(separator: " ")).joined(separator: " ") + " "
        let generic: Set<String> = ["companies", "documents", "desktop", "notes", "files", "data", "figures", "code",
                                    "papers", "paper", "presentation", "meetings", "misc", "other", "old", "new", "archive",
                                    "dataroom", "data room", "downloads", "drafts", "backup", "temp", "work", "school"]
        let scored = folders.compactMap { f -> (Folder, Int)? in
            let key = Style.tokens(f.name).filter { $0.count >= 4 && !generic.contains($0) && !Style.filler.contains($0) }
            guard let k = key.first else { return nil }
            // Score = how often the folder's word appears in the file. A CivCore call mentions CivCore a lot.
            let hits = text.components(separatedBy: " " + k + " ").count - 1
            return hits >= 2 ? (f, hits) : nil   // one passing mention is not enough
        }
        if let top = scored.max(by: { $0.1 < $1.1 }),
           scored.filter({ $0.1 == top.1 && $0.0.url != top.0.url }).isEmpty {   // only if one clear winner
            return top.0.url
        }
        return nil
    }

    /// For a file whose name is already good: is there a clear folder for it?
    public static func suggest(forKept url: URL, folders: [Folder]) -> URL? {
        let (e, kebab) = keptEvidence(url)
        return suggest(name: kebab, evidence: e, folders: folders)
    }

    /// Cheap evidence for a file we are not renaming: link, title, first page. Plus its name in kebab form.
    public static func keptEvidence(_ url: URL) -> (Evidence, String) {
        var e = Evidence(url: url)
        e.sourceURLs = Extract.sourceURLs(url)
        // First page / paragraph only — enough to find "CENG 491" in a well-named file.
        let info: Extract.PDFInfo? = switch url.pathExtension.lowercased() {
            case "pdf": Extract.pdf(url)
            case "docx": Extract.docx(url)
            case "pptx": Extract.pptx(url)
            case "ipynb": Extract.notebook(url)
            default: nil
        }
        if let info {
            if !Extract.isJunkTitle(info.title, stem: e.stem) { e.metadataTitle = info.title }
            e.headline = info.headline
            e.bodySnippet = info.snippet
        }
        var kebab = Style.join(Style.tokens(e.stem))   // "CENG331-05-machinebasics…" → "ceng331-05-…"
        // Course code in the content but not in the name → still the course's folder.
        let academic = e.sourceHost.map { h in ["odtuclass", "moodle", "canvas", "edu"].contains { h.contains($0) } } ?? false
        let text = [e.metadataTitle, e.headline, e.bodySnippet.map { String($0.prefix(400)) }].compactMap { $0 }.joined(separator: "\n")
        if let course = Style.courseCode(in: text, academicSource: academic), !kebab.hasPrefix(course) {
            kebab = course + "-" + kebab
        }
        return (e, kebab)
    }

    /// Rules first; if they have no clear answer, the on-device model picks from your folders. nil = Downloads.
    public static func best(name: String, evidence e: Evidence, folders: [Folder], useModel: Bool = true) async -> URL? {
        if let f = suggest(name: name, evidence: e, folders: folders) { return f }
        guard useModel else { return nil }
        let home = homeRoot.path + "/"
        let options = shortlist(name: name, evidence: e, folders: folders)
            .map { $0.url.path.replacingOccurrences(of: home, with: "") }
        guard let pick = await Model.pickFolder(for: e, name: name, options: options) else { return nil }
        // Safety: the file must share a real word with the folder path. A refund letter has nothing to do
        // with a startup's folder, however "travel-ish" both look to a small model.
        var words = Set(Style.tokens([e.stem, name, e.metadataTitle, e.headline, e.sourceHost,
                                      e.bodySnippet.map { String($0.prefix(800)) }].compactMap { $0 }.joined(separator: " ")))
        let list = Style.tokens(e.stem)
        for i in list.indices.dropLast() { words.insert(list[i] + list[i + 1]) }   // "data room" → "dataroom"
        let folderWords = Style.tokens(pick).filter { $0.count >= 4 && !Style.filler.contains($0) }
        guard folderWords.contains(where: { words.contains($0) }) else { return nil }
        return URL(fileURLWithPath: home + pick)
    }

    /// The folders the model gets to choose from: the closest by meaning (folder path + the names of the files
    /// inside it, compared with what this file is about). A small model picks far better from 12 relevant
    /// options than from 80 recent ones. Falls back to the most recently used folders.
    public static func shortlist(name: String, evidence e: Evidence, folders: [Folder], k: Int = 12) -> [Folder] {
        let recent = Array(folders.sorted { $0.modified > $1.modified }.prefix(80))
        let query = name.replacingOccurrences(of: "-", with: " ") + ". " + gist(e)
        let ranked = Embedder.shared.rank(query, folders.map(describe))
        guard !ranked.isEmpty else { return recent }
        return ranked.prefix(k).map { folders[$0.index] }
    }

    /// "courses-fall26 ceng331: ceng331-midterm1-fall19-solutions, CENG331-02-03-bits-ints, …" — what a folder holds.
    static func describe(_ f: Folder) -> String {
        let key = "\(f.url.path)|\(f.modified.timeIntervalSince1970)"
        return FolderText.shared.get(key) {
            let path = f.url.pathComponents.suffix(2).joined(separator: " ")
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: f.url.path)) ?? [])
                .filter { !$0.hasPrefix(".") }.sorted().prefix(15)
                .map { ($0 as NSString).deletingPathExtension }
            return path + (names.isEmpty ? "" : ": " + names.joined(separator: ", "))
        }
    }

    /// Folder list, rebuilt at most every few minutes: scanning ~/ for every download is wasted work.
    public static func cachedIndex(maxAge: TimeInterval = 600) -> [Folder] { IndexCache.shared.get(maxAge: maxAge) }

    /// The naming style of the files already in `folder` (separator, case, suffix), if at least 3 of them
    /// look hand-named. New files then match their neighbours instead of a global default.
    public static func style(of folder: URL?) -> StyleProfile? {
        guard let folder, let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                                    options: [.skipsHiddenFiles]) else { return nil }
        let names = items.compactMap(StyleProfile.chosenName)
        return names.count >= 3 ? StyleProfile.learn(names: names) : nil
    }

    /// A file with the same bytes already in `folder`? (Downloaded twice.) Compares size first, then content.
    public static func duplicate(of url: URL, in folder: URL?) -> URL? {
        guard let folder, let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        else { return nil }
        for other in items where other.pathExtension.lowercased() == url.pathExtension.lowercased()
            && other.resolvingSymlinksInPath() != url.resolvingSymlinksInPath() {   // not itself
            guard (try? other.resourceValues(forKeys: [.fileSizeKey]))?.fileSize == size else { continue }
            if FileManager.default.contentsEqual(atPath: url.path, andPath: other.path) { return other }
        }
        return nil
    }

    /// "courses-fall26 › ceng491" — short, but enough to tell same-named folders apart.
    public static func short(_ url: URL?) -> String {
        guard let url else { return "Downloads" }
        let parts = url.pathComponents
        return parts.suffix(2).joined(separator: " › ")
    }

    /// "~/courses-fall26/ceng315" for display.
    public static func pretty(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

final class FolderText: @unchecked Sendable {
    static let shared = FolderText()
    private let lock = NSLock()
    private var memo: [String: String] = [:]
    func get(_ key: String, _ make: () -> String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let v = memo[key] { return v }
        let v = make(); memo[key] = v; return v
    }
}

final class IndexCache: @unchecked Sendable {
    static let shared = IndexCache()
    private let lock = NSLock()
    private var folders: [Destination.Folder] = []
    private var built = Date.distantPast
    func get(maxAge: TimeInterval) -> [Destination.Folder] {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(built) > maxAge { folders = Destination.index(); built = Date() }
        return folders
    }
}
