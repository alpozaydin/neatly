import Foundation

/// Where should a file go? Only ever suggests folders that already exist (or that you chose before).
public enum Destination {
    public struct Folder: Sendable {
        public let url: URL
        public let name: String          // lowercased last component
        public let modified: Date
    }

    /// Folders a person organises files in: home folders except system ones, 3 levels deep, no code repos.
    public static func index(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Folder] {
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

    /// For a file whose name is already good: is there a clear folder for it? Uses the name and download link only.
    public static func suggest(forKept url: URL, folders: [Folder]) -> URL? {
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
        return suggest(name: kebab, evidence: e, folders: folders)
    }

    /// "~/courses-fall26/ceng315" for display.
    public static func pretty(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
