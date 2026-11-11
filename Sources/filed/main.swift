import Foundation
import NamerCore

let usage = """
usage: filed [options] <file or folder>...
  Suggests short names for badly named files. Changes nothing unless --apply is given.

  --apply      rename the files
  --force      suggest even for names that already look fine (never overrides a name you chose)
  --why        show the evidence, and why files were skipped
  --watch      wait for new files in the folder and suggest names as they arrive
  --where      also suggest a folder to move each file to
  --ask        with --watch: show a dialog for each file (Save / Select place… / Leave as is)
  --timeout N  with --ask: save the suggestion after N seconds without an answer (default 5, 0 = wait)
  service install|uninstall   run "--watch ~/Downloads --ask" in the background, starting at login
  --offline    no network lookups (arXiv)
  --no-model   don't use the on-device model
  undo <file>  restore a file's original name
  keep <file>  mark a name as yours: never suggest for it again
  learn <folder>...  learn your naming style from names you already chose (reads names only)
  style        show the saved style  (style --reset to delete it)
  --version    print the version
  stats        how often you saved the suggestion unchanged, and your recent edits
"""

setvbuf(stdout, nil, _IOLBF, 0)
migrateFromOldName()   // write log lines immediately, even when not in a terminal
var args = Array(CommandLine.arguments.dropFirst())
let version = "0.1.0"
if args.isEmpty || args.contains("-h") || args.contains("--help") { print(usage); exit(0) }
if args.first == "--version" { print("filed \(version)"); exit(0) }

if args.first == "dialog" { runDialog(Array(args.dropFirst())) }   // the popup, started by the watcher

if args.first == "learn" {
    let roots = args.dropFirst().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    guard !roots.isEmpty else { print("usage: filed learn <folder>..."); exit(1) }
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
        print("Run it on the folders whose style you want for downloads, e.g.: filed learn ~/courses-fall26")
        exit(0)
    }
    try saved.save()
    print("saved to \(StyleProfile.fileURL.path.replacingOccurrences(of: home, with: "~"))")
    exit(0)
}

if args.first == "style" {
    if args.contains("--reset") { try? FileManager.default.removeItem(at: StyleProfile.fileURL); print("style reset"); exit(0) }
    if let p = StyleProfile.load() { print(String(data: try JSONEncoder().encode(p), encoding: .utf8)!) }
    else { print("no saved style — using: lowercase, '-' (run: filed learn <folder>)") }
    exit(0)
}

if args.first == "service" {
    let label = "dev.filed.watch"
    let plist = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(label).plist")
    let uid = getuid()
    func launchctl(_ a: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = a
        p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit()
    }
    switch args.dropFirst().first {
    case "install":
        // Run a stable copy, not the build output: macOS asks for folder access again whenever the
        // program file changes, so developer rebuilds must not touch the one the service runs.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installed = home.appending(path: ".local/bin/filed")
        let built = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        if built.path != installed.path {
            try FileManager.default.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: installed)
            try FileManager.default.copyItem(at: built, to: installed)
        }
        let exe = installed.path
        let log = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/filed.log").path
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
        // Before 0.1.0 this was "namer": stop and remove the old service and binary.
        launchctl(["bootout", "gui/\(uid)/dev.namer.watch"])
        try? FileManager.default.removeItem(at: plist.deletingLastPathComponent().appending(path: "dev.namer.watch.plist"))
        try? FileManager.default.removeItem(at: home.appending(path: ".local/bin/namer"))
        migrateFromOldName()   // again: the old service may have written while it was still running
        launchctl(["bootout", "gui/\(uid)/\(label)"])
        launchctl(["bootstrap", "gui/\(uid)", plist.path])
        print("filed now watches ~/Downloads and asks before renaming. Log: ~/Library/Logs/filed.log")
        print("Installed at ~/.local/bin/filed. After updating filed, run 'filed service install' again.")
        print("Stop it any time: filed service uninstall")
    case "uninstall":
        launchctl(["bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(at: plist)
        print("stopped and removed")
    default: print("usage: filed service install|uninstall")
    }
    exit(0)
}

// How often are the suggestions right? The honest metric: popups you saved without changing anything.
if args.first == "stats" {
    let all = Correction.all()
    let answered = all.filter { $0.auto != true }
    guard !all.isEmpty else { print("no popups answered yet"); exit(0) }
    func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : "\(Int((Double(a) / Double(b) * 100).rounded()))%" }
    let left = answered.filter { $0.chosen.isEmpty }
    let saved = answered.filter { !$0.chosen.isEmpty }
    let nameOK = saved.filter { $0.chosen == $0.suggested }
    let withFolder = saved.filter { $0.suggestedFolder != nil || $0.chosenFolder != nil }
    let folderOK = withFolder.filter { $0.chosenFolder == $0.suggestedFolder }
    let both = saved.filter { $0.chosen == $0.suggested && $0.chosenFolder == $0.suggestedFolder }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
    print("\(all.count) popups since \(f.string(from: all.map(\.date).min()!))  (\(all.count - answered.count) auto-saved, not counted)\n")
    print("ACCEPTED  \(pct(both.count, answered.count))  saved without any change: \(both.count) of \(answered.count) answered")
    print("  name    \(pct(nameOK.count, saved.count))  kept the suggested name (\(nameOK.count)/\(saved.count) saves)")
    print("  folder  \(pct(folderOK.count, withFolder.count))  kept the suggested folder (\(folderOK.count)/\(withFolder.count))")
    print("  left as is: \(left.count)\n")
    print("BY PATH   saves  name kept")
    func bucket(_ v: String) -> String { v.hasPrefix("rules") ? "rules" : v.hasPrefix("model") ? "model" : v == "kept" ? "name ok" : "other" }
    for b in ["rules", "model", "name ok", "other"] {
        let g = saved.filter { bucket($0.via) == b }
        guard !g.isEmpty else { continue }
        let ok = g.filter { $0.chosen == $0.suggested }.count
        print("  \(b.padding(toLength: 8, withPad: " ", startingAt: 0))  \(String(g.count).padding(toLength: 5, withPad: " ", startingAt: 0))  \(pct(ok, g.count))")
    }
    let edits = saved.filter { $0.chosen != $0.suggested }.suffix(8)
    if !edits.isEmpty {
        print("\nRECENT EDITS (what to fix next)")
        for c in edits { print("  \(c.suggested)  →  \(c.chosen)   [\(bucket(c.via))]") }
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
var timeout = 5
if let i = args.firstIndex(of: "--timeout"), i + 1 < args.count, let n = Int(args[i + 1]) {
    timeout = max(0, n); args.removeSubrange(i...(i + 1))
}

enum Answer { case save(name: String, folder: URL?, auto: Bool), keep, noAnswer }

func osascript(_ script: String) -> (ok: Bool, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return (false, "") }
    p.waitUntilExit()
    return (p.terminationStatus == 0, String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
}

/// The dialog (see Dialog.swift). Save = the name in the field, in the shown folder. Select place… = pick a folder.
/// Leave as is = no change. No answer within `timeout` seconds = Save, so agents downloading files never wait on a click.
@MainActor func askUser(file: String, suggestion: String, folder: URL?) -> Answer {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    p.arguments = ["dialog", String(timeout), file, suggestion, folder?.path ?? ""]
    let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return .noAnswer }
    let reply = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    p.waitUntilExit()
    let parts = reply.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
    if parts.first == "keep" { return .keep }
    guard parts.first == "save", parts.count >= 3 else { return .noAnswer }
    let typed = parts[1].trimmingCharacters(in: .whitespaces)
    let shown: URL? = parts[2].isEmpty ? nil : URL(fileURLWithPath: parts[2])

    // Power users can still type a path: "~/somewhere/name".
    let expanded = (typed as NSString).expandingTildeInPath
    let name = (expanded as NSString).lastPathComponent
    var chosenFolder: URL? = typed.contains("/") ? URL(fileURLWithPath: (expanded as NSString).deletingLastPathComponent) : shown
    let home = FileManager.default.homeDirectoryForCurrentUser
    if let f = chosenFolder, !f.path.hasPrefix(home.path) { chosenFolder = nil }          // only inside your home
    if let f = chosenFolder, f.standardizedFileURL == home.appending(path: "Downloads").standardizedFileURL {
        chosenFolder = nil                                                                 // picked Downloads = stay
    }
    return .save(name: name, folder: chosenFolder, auto: parts.count > 3 && parts[3] == "auto")
}

// Watch mode: poll once a second; a file is "done" when its size stops changing.
if watch {
    let dir = URL(fileURLWithPath: ((args.first ?? "~/Downloads") as NSString).expandingTildeInPath)
    let skip: Set<String> = ["crdownload", "download", "part", "partial"]
    let installers: Set<String> = ["dmg", "pkg", "app", "iso"]   // nothing to file
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
    var warmed = Date.distantPast
    if namer.useModel { Task.detached { Namer.prewarm() } }
    print("watching \(dir.path) — download something (Ctrl-C to stop)")
    while true {
        try? await Task.sleep(for: .seconds(1))
        // A download in progress: load the model now, so it's ready when the file lands.
        if namer.useModel, Date().timeIntervalSince(warmed) > 120,
           ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).contains(where: {
               skip.contains(($0 as NSString).pathExtension.lowercased()) }) {
            warmed = Date(); Task.detached { Namer.prewarm() }
        }
        let now = listing()
        for (name, size) in now where !seen.contains(name) {
            if pending[name] == size {           // same size two checks in a row: finished
                seen.insert(name); pending[name] = nil
                let url = dir.appending(path: name)
                let original = url.deletingPathExtension().lastPathComponent
                // Every new download gets a name and a folder — except installers and files already handled.
                var nameIdea = original, via = "kept", evidence: Evidence
                switch await namer.suggest(for: url, explicit: force) {
                case .suggested(let s):
                    nameIdea = s.name; via = s.via; evidence = s.evidence
                    print("\(name)  →  \(s.name)   [\(s.via), \(Int(s.millis.rounded())) ms]")
                case .kept(let r) where r != "name already meaningful":
                    print("\(name)  skip (\(r))"); continue
                case .kept, .unsure:
                    evidence = Destination.keptEvidence(url).0
                    // The name looks fine, but rules may know a more specific one (Sample-MT → ceng331-midterm1-fall19-solutions).
                    // Only rules: a model guess shouldn't replace a name a person may have chosen.
                    var rulesOnly = namer; rulesOnly.useModel = false
                    if case .suggested(let s) = await rulesOnly.suggest(for: url, explicit: true), s.via.hasPrefix("rules") {
                        nameIdea = s.name; via = s.via; evidence = s.evidence
                        print("\(name)  name ok, but rules suggest \(s.name)")
                    } else {
                        print("\(name)  name ok")
                    }
                }
                guard ask else {
                    if apply, nameIdea != original { _ = try? Rename.apply(url, to: nameIdea) }
                    continue
                }
                if installers.contains(url.pathExtension.lowercased()) { continue }
                let kebab = nameIdea == original ? Destination.keptEvidence(url).1
                    : nameIdea.lowercased().split(whereSeparator: { "-_ ".contains($0) }).joined(separator: "-")
                let target = await Destination.best(name: kebab, evidence: evidence, folders: Destination.cachedIndex(),
                                                    useModel: namer.useModel)
                print("   folder: \(Destination.short(target))")
                // Match the neighbours: in a folder of "Lab Report - MAO" files, a new one is styled the same way.
                if nameIdea != original, let local = Destination.style(of: target) {
                    let styled = local.render(kebab)
                    if styled != nameIdea { print("   styled like its folder: \(styled)"); nameIdea = styled }
                }
                // Downloaded the same file twice? Say so instead of making a "-2" copy.
                if let twin = Destination.duplicate(of: url, in: target) {
                    let r = osascript("""
                    display dialog "\(name.replacingOccurrences(of: "\"", with: "'"))\\n\\nYou already have this file:\\n\(Destination.short(target)) › \(twin.lastPathComponent.replacingOccurrences(of: "\"", with: "'"))\(timeout > 0 ? "\\n\\nMoves to Trash in \(timeout) s if you don’t answer." : "")" ¬
                      with title "filed" buttons {"Keep both", "Move to Trash"} default button "Move to Trash" giving up after \(timeout > 0 ? timeout : 300)
                    """)
                    // No answer: an exact copy already exists, so trashing this one loses nothing (and it's in the Trash).
                    if r.ok, r.out.contains("Move to Trash") || (timeout > 0 && r.out.contains("gave up:true")) {
                        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        print("   duplicate of \(twin.lastPathComponent) — moved to Trash")
                        continue
                    }
                }
                let ev = evidence, suggestedName = nameIdea, how = via
                let log = { (chosen: String, folder: URL?, auto: Bool) in
                    Correction(original: name, suggested: suggestedName, chosen: chosen, via: how,
                               source: ev.sourceHost, title: ev.metadataTitle ?? ev.headline,
                               suggestedFolder: target?.path, chosenFolder: folder?.path,
                               auto: auto ? true : nil, context: String(gist(ev).prefix(300))).save()
                }
                switch askUser(file: name, suggestion: nameIdea, folder: target) {
                case .save(let chosen, let folder, let auto):
                    let done = (chosen == original && folder == nil) ? url : (try? Rename.apply(url, to: chosen, in: folder))
                    if let done, done.deletingLastPathComponent() == dir { seen.insert(done.lastPathComponent) }
                    let edited = chosen != nameIdea || folder?.path != target?.path
                    log(chosen, folder, auto)                 // every answer teaches names and folders (auto ones don't)
                    if let done { Decision.markKeep(done) }   // handled: never ask again
                    print("   saved as \(Destination.short(folder))/\(done?.lastPathComponent ?? chosen)\(auto ? " (no answer, auto-saved)" : edited ? " (your edit)" : "")")
                case .keep:
                    Decision.markKeep(url); log("", nil, false)
                    print("   left as is")
                case .noAnswer: print("   no answer, left as is")
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
let folderIndex = whereTo ? Destination.cachedIndex() : []
/// --where --why: the folders the model chose from, closest first.
func showShortlist(_ name: String, _ e: Evidence) {
    guard why else { return }
    let t0 = Date()
    let list = Destination.shortlist(name: name, evidence: e, folders: folderIndex, k: 5)
    print("      closest: \(list.map { Destination.short($0.url) }.joined(separator: " | "))  (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)")
}
var renamed = 0, suggested = 0, kept = 0, unsure = 0
for url in files {
    let old = url.lastPathComponent
    let shown = old.count > pad ? String(old.prefix(pad - 1)) + "…" : old.padding(toLength: pad, withPad: " ", startingAt: 0)
    switch await namer.suggest(for: url, explicit: force) {
    case .kept(let r):
        kept += 1
        if why || whereTo { print("\(shown)     keep   (\(r))") }
        if whereTo {
            let (ev, kebab) = Destination.keptEvidence(url)
            let f = await Destination.best(name: kebab, evidence: ev, folders: folderIndex, useModel: namer.useModel)
            print("      folder:  \(Destination.short(f))")
            showShortlist(kebab, ev)
        }
    case .unsure(let r):
        unsure += 1
        if why { print("\(shown)     ?      (\(r))") }
    case .suggested(let s):
        suggested += 1
        let new = url.pathExtension.isEmpty ? s.name : "\(s.name).\(url.pathExtension.lowercased())"
        print("\(shown)  →  \(new)   [\(s.via), \(Int(s.millis.rounded())) ms]")
        if whereTo {
            let f = await Destination.best(name: s.name, evidence: s.evidence, folders: folderIndex, useModel: namer.useModel)
            print("      folder:  \(Destination.short(f))")
            showShortlist(s.name, s.evidence)
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
