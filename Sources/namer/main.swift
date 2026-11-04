import Foundation
import NamerCore

let usage = """
usage: namer [options] <file or folder>...
  Suggests short names for badly named files. Changes nothing unless --apply is given.

  --apply      rename the files
  --force      suggest even for names that already look fine (never overrides a name you chose)
  --why        show the evidence, and why files were skipped
  --watch      wait for new files in the folder and suggest names as they arrive
  --where      also suggest a folder to move each file to
  --ask        with --watch: show a dialog for each file (Rename / edit the name / Keep name)
  service install|uninstall   run "--watch ~/Downloads --ask" in the background, starting at login
  --offline    no network lookups (arXiv)
  --no-model   don't use the on-device model
  undo <file>  restore a file's original name
  keep <file>  mark a name as yours: never suggest for it again
  learn <folder>...  learn your naming style from names you already chose (reads names only)
  style        show the saved style  (style --reset to delete it)
"""

setvbuf(stdout, nil, _IOLBF, 0)   // write log lines immediately, even when not in a terminal
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

if args.first == "service" {
    let label = "dev.namer.watch"
    let plist = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(label).plist")
    let uid = getuid()
    func launchctl(_ a: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = a
        p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit()
    }
    switch args.dropFirst().first {
    case "install":
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        let log = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/namer.log").path
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key><array><string>\(exe)</string><string>--watch</string>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/Downloads</string><string>--ask</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardOutPath</key><string>\(log)</string>
          <key>StandardErrorPath</key><string>/dev/null</string>
        </dict></plist>
        """
        try xml.write(to: plist, atomically: true, encoding: .utf8)
        launchctl(["bootout", "gui/\(uid)/\(label)"])
        launchctl(["bootstrap", "gui/\(uid)", plist.path])
        print("namer now watches ~/Downloads and asks before renaming. Log: ~/Library/Logs/namer.log")
        print("Stop it any time: namer service uninstall")
    case "uninstall":
        launchctl(["bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(at: plist)
        print("stopped and removed")
    default: print("usage: namer service install|uninstall")
    }
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
let apply = flag("--apply"), force = flag("--force"), why = flag("--why"), watch = flag("--watch"), ask = flag("--ask"), whereTo = flag("--where")
var namer = Namer()
namer.profile = StyleProfile.load() ?? .standard
namer.useNetwork = !flag("--offline")
namer.useModel = !flag("--no-model")

enum Answer { case save(name: String, folder: URL?), keep, noAnswer }

func osascript(_ script: String) -> (ok: Bool, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return (false, "") }
    p.waitUntilExit()
    return (p.terminationStatus == 0, String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
}

/// The dialog: the name in the field (edit it to name the file yourself), the folder as one short word above.
/// Rename = this name, in this folder. Folder… = pick another folder. Keep name = leave the file alone.
func askUser(file: String, suggestion: String, folder: URL?) -> Answer {
    func q(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    let original = (file as NSString).deletingPathExtension
    let action = suggestion == original ? "Move" : "Rename"
    let r = osascript("""
    display dialog "New download:\\n\(q(file))\\n\\nFolder: \(q(folder?.lastPathComponent ?? "Downloads"))\\n\(action == "Move" ? "Name:" : "Rename to:")" ¬
      default answer "\(q(suggestion))" with title "namer" buttons {"Keep name", "Folder…", "\(action)"} ¬
      default button "\(action)" cancel button "Keep name" giving up after 300
    """)
    if !r.ok { return .keep }                                        // "Keep name" = cancel button
    if r.out.contains("gave up:true") { return .noAnswer }
    guard let t = r.out.range(of: "text returned:") else { return .noAnswer }
    let typed = (String(r.out[t.upperBound...]).components(separatedBy: ", gave up:").first ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else { return .noAnswer }

    // Power users can still type a path: "~/somewhere/name".
    let expanded = (typed as NSString).expandingTildeInPath
    let name = (expanded as NSString).lastPathComponent
    var chosenFolder: URL? = typed.contains("/") ? URL(fileURLWithPath: (expanded as NSString).deletingLastPathComponent) : folder

    if r.out.contains("button returned:Folder") {
        let start = chosenFolder ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        let pick = osascript("""
        POSIX path of (choose folder with prompt "Save “\(q(name))” in:" default location (POSIX file "\(q(start.path))"))
        """)
        guard pick.ok else { return .noAnswer }
        chosenFolder = URL(fileURLWithPath: pick.out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    if let f = chosenFolder, !f.path.hasPrefix(home.path) { chosenFolder = nil }          // only inside your home
    if let f = chosenFolder, f.standardizedFileURL == home.appending(path: "Downloads").standardizedFileURL {
        chosenFolder = nil                                                                 // picked Downloads = stay
    }
    return .save(name: name, folder: chosenFolder)
}

// Watch mode: poll once a second; a file is "done" when its size stops changing.
if watch {
    let dir = URL(fileURLWithPath: ((args.first ?? "~/Downloads") as NSString).expandingTildeInPath)
    let skip: Set<String> = ["crdownload", "download", "part", "partial"]
    func listing() -> [String: Int] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        var out: [String: Int] = [:]
        for u in items where !skip.contains(u.pathExtension.lowercased())
            && (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {   // files only
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
                    if ask {
                        let folders = Destination.index()
                        let target = Destination.suggest(name: s.name, evidence: s.evidence, folders: folders)
                        let answer = askUser(file: name, suggestion: s.name, folder: target)
                        let ev = s.evidence
                        let log = { (chosen: String, folder: URL?) in
                            Correction(original: name, suggested: s.name, chosen: chosen, via: s.via,
                                       source: ev.sourceHost, title: ev.metadataTitle ?? ev.headline,
                                       suggestedFolder: target?.path, chosenFolder: folder?.path).save()
                        }
                        switch answer {
                        case .save(let chosen, let folder):
                            let done = try? Rename.apply(url, to: chosen, in: folder)
                            if let done, done.deletingLastPathComponent() == dir { seen.insert(done.lastPathComponent) }
                            let edited = chosen != s.name || folder?.path != target?.path
                            if edited || folder != nil { log(chosen, folder) }   // moves teach where things go
                            if edited, let done { Decision.markKeep(done) }
                            let place = folder.map { Destination.pretty($0) } ?? "Downloads"
                            print("   saved as \(place)/\(done?.lastPathComponent ?? chosen)\(edited ? " (your edit, saved)" : "")")
                        case .keep:
                            Decision.markKeep(url); log("", nil)
                            print("   kept as is")
                        case .noAnswer: print("   no answer, left as is")
                        }
                    } else if apply { _ = try? Rename.apply(url, to: s.name); seen.insert(new) }
                case .kept(let r):
                    print("\(name)  keep (\(r))")
                    // Good name, but it may still belong somewhere. Ask only if there's a clear folder.
                    if ask, r == "name already meaningful",
                       let target = Destination.suggest(forKept: url, folders: Destination.index()) {
                        let stem = url.deletingPathExtension().lastPathComponent
                        print("   folder suggestion: \(Destination.pretty(target))")
                        switch askUser(file: name, suggestion: stem, folder: target) {
                        case .save(let chosen, let folder):
                            let done = try? Rename.apply(url, to: chosen, in: folder)
                            if folder?.path != target.path || chosen != stem {
                                Correction(original: name, suggested: Style.join(Style.tokens(stem)), chosen: chosen,
                                           via: "move", source: nil, title: nil,
                                           suggestedFolder: target.path, chosenFolder: folder?.path).save()
                            }
                            if let done { Decision.markKeep(done); if done.deletingLastPathComponent() == dir { seen.insert(done.lastPathComponent) } }
                            print("   saved as \(folder.map(Destination.pretty) ?? "Downloads")/\(done?.lastPathComponent ?? chosen)")
                        case .keep: Decision.markKeep(url); print("   kept as is")
                        case .noAnswer: print("   no answer, left as is")
                        }
                    }
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
let folderIndex = whereTo ? Destination.index() : []
var renamed = 0, suggested = 0, kept = 0, unsure = 0
for url in files {
    let old = url.lastPathComponent
    let shown = old.count > pad ? String(old.prefix(pad - 1)) + "…" : old.padding(toLength: pad, withPad: " ", startingAt: 0)
    switch await namer.suggest(for: url, explicit: force) {
    case .kept(let r):
        kept += 1
        if why || whereTo { print("\(shown)     keep   (\(r))") }
        if whereTo, let f = Destination.suggest(forKept: url, folders: folderIndex) {
            print("      folder:  \(Destination.pretty(f))")
        }
    case .unsure(let r):
        unsure += 1
        if why { print("\(shown)     ?      (\(r))") }
    case .suggested(let s):
        suggested += 1
        let new = url.pathExtension.isEmpty ? s.name : "\(s.name).\(url.pathExtension.lowercased())"
        print("\(shown)  →  \(new)   [\(s.via), \(Int(s.millis.rounded())) ms]")
        if whereTo {
            let f = Destination.suggest(name: s.name, evidence: s.evidence, folders: folderIndex)
            print("      folder:  \(f.map(Destination.pretty) ?? "(stay in Downloads)")")
        }
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
