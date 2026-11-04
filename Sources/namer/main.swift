import Foundation
import NamerCore

let usage = """
usage: namer [options] <file or folder>...
  Suggests short names for badly named files. Changes nothing unless --apply is given.

  --apply      rename the files
  --force      suggest even for names that already look fine (never overrides a name you chose)
  --why        show the evidence, and why files were skipped
  --watch      wait for new files in the folder and suggest names as they arrive
  --offline    no network lookups (arXiv)
  --no-model   don't use the on-device model
  undo <file>  restore a file's original name
  keep <file>  mark a name as yours: never suggest for it again
  learn <folder>...  learn your naming style from names you already chose (reads names only)
  style        show the saved style  (style --reset to delete it)
"""

var args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("-h") || args.contains("--help") { print(usage); exit(0) }

if args.first == "learn" {
    let roots = args.dropFirst().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    guard !roots.isEmpty else { print("usage: namer learn <folder>..."); exit(1) }
    let (overall, agreement, folders) = StyleProfile.learn(roots: roots)
    func describe(_ p: StyleProfile) -> String {
        let sep = p.separator == " " ? "spaces" : "'\(p.separator)'"
        return "\(sep), \(p.lowercase ? "lowercase" : "Title Case")" + (p.suffix.map { ", ends with \($0)" } ?? "")
            + "  → e.g. \(p.render("transcript-fall26"))"
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    for f in folders {
        print("\(f.folder.replacingOccurrences(of: home, with: "~"))  (\(f.profile.learnedFrom) names)")
        print("    \(describe(f.profile))")
    }
    let saved = overall   // separator + case only: a suffix like your initials belongs to one folder, not all
    print("\nmost folders (\(Int(agreement * 100))% of \(folders.count)): \(describe(saved))")
    if args.contains("--dry-run") { exit(0) }
    if agreement < 0.6 {
        print("\nYour folders use different styles, so nothing was saved.")
        print("Run it on the folders whose style you want for downloads, e.g.: namer learn ~/courses-fall26")
        exit(0)
    }
    try saved.save()
    print("saved to \(StyleProfile.fileURL.path.replacingOccurrences(of: home, with: "~"))")
    exit(0)
}

if args.first == "style" {
    if args.contains("--reset") { try? FileManager.default.removeItem(at: StyleProfile.fileURL); print("style reset"); exit(0) }
    if let p = StyleProfile.load() { print(String(data: try JSONEncoder().encode(p), encoding: .utf8)!) }
    else { print("no saved style — using: lowercase, '-' (run: namer learn <folder>)") }
    exit(0)
}

if args.first == "keep" {
    for p in args.dropFirst() { Decision.markKeep(URL(fileURLWithPath: p)); print("keeping: \(p)") }
    exit(0)
}

if args.first == "undo" {
    for p in args.dropFirst() {
        let url = URL(fileURLWithPath: p)
        do {
            if let back = try Rename.undo(url) { print("\(url.lastPathComponent)  →  \(back.lastPathComponent)") }
            else { print("\(url.lastPathComponent): no original name recorded") }
        } catch { print("\(url.lastPathComponent): \(error.localizedDescription)") }
    }
    exit(0)
}

@MainActor func flag(_ f: String) -> Bool {
    guard let i = args.firstIndex(of: f) else { return false }
    args.remove(at: i); return true
}
let apply = flag("--apply"), force = flag("--force"), why = flag("--why"), watch = flag("--watch")
var namer = Namer()
namer.profile = StyleProfile.load() ?? .standard
namer.useNetwork = !flag("--offline")
namer.useModel = !flag("--no-model")

// Watch mode: poll once a second; a file is "done" when its size stops changing.
if watch {
    let dir = URL(fileURLWithPath: ((args.first ?? "~/Downloads") as NSString).expandingTildeInPath)
    let skip: Set<String> = ["crdownload", "download", "part", "partial"]
    func listing() -> [String: Int] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        var out: [String: Int] = [:]
        for u in items where !skip.contains(u.pathExtension.lowercased()) {
            out[u.lastPathComponent] = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        }
        return out
    }
    var seen = Set(listing().keys)
    var pending: [String: Int] = [:]
    print("watching \(dir.path) — download something (Ctrl-C to stop)")
    while true {
        try? await Task.sleep(for: .seconds(1))
        let now = listing()
        for (name, size) in now where !seen.contains(name) {
            if pending[name] == size {           // same size two checks in a row: finished
                seen.insert(name); pending[name] = nil
                let url = dir.appending(path: name)
                switch await namer.suggest(for: url, explicit: force) {
                case .suggested(let s):
                    let new = url.pathExtension.isEmpty ? s.name : "\(s.name).\(url.pathExtension.lowercased())"
                    print("\(name)  →  \(new)   [\(s.via), \(Int(s.millis.rounded())) ms]")
                    if apply { _ = try? Rename.apply(url, to: s.name); seen.insert(new) }
                case .kept(let r): print("\(name)  keep (\(r))")
                case .unsure(let r): print("\(name)  ? (\(r))")
                }
            } else { pending[name] = size }
        }
        seen.formIntersection(now.keys)          // forget deleted files
        if apply { seen.formUnion(listing().keys) }
    }
}

// Expand folders one level (Downloads, Desktop) — skip hidden and in-progress downloads.
let partial: Set<String> = ["crdownload", "download", "part", "partial"]
var files: [URL] = []
for p in args {
    let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
        print("not found: \(p)"); continue
    }
    if isDir.boolValue {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        files += items.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    } else { files.append(url) }
}
files.removeAll { partial.contains($0.pathExtension.lowercased()) }

if namer.useModel { print("model: \(Namer.modelStatus)\n") }

let pad = min(48, files.map(\.lastPathComponent.count).max() ?? 0)
var renamed = 0, suggested = 0, kept = 0, unsure = 0
for url in files {
    let old = url.lastPathComponent
    let shown = old.count > pad ? String(old.prefix(pad - 1)) + "…" : old.padding(toLength: pad, withPad: " ", startingAt: 0)
    switch await namer.suggest(for: url, explicit: force) {
    case .kept(let r):
        kept += 1
        if why { print("\(shown)     keep   (\(r))") }
    case .unsure(let r):
        unsure += 1
        if why { print("\(shown)     ?      (\(r))") }
    case .suggested(let s):
        suggested += 1
        let new = url.pathExtension.isEmpty ? s.name : "\(s.name).\(url.pathExtension.lowercased())"
        print("\(shown)  →  \(new)   [\(s.via), \(Int(s.millis.rounded())) ms]")
        if why {
            let e = s.evidence
            if let h = e.sourceDescription { print("      source:  \(h)") }
            if let t = e.metadataTitle { print("      title:   \(t)") }
            if let h = e.headline { print("      heading: \(h)") }
            if !e.labels.isEmpty { print("      labels:  \(e.labels.joined(separator: ", "))") }
            if let p = e.paper { print("      paper:   \(p.title) (\(p.year.map(String.init) ?? "?"))") }
        }
        if apply {
            do { try Rename.apply(url, to: s.name); renamed += 1 }
            catch { print("      rename failed: \(error.localizedDescription)") }
        }
    }
}
print("\n\(files.count) file(s): \(suggested) suggested, \(kept) kept as is, \(unsure) unsure"
      + (apply ? " — \(renamed) renamed" : " — nothing changed (use --apply)"))
