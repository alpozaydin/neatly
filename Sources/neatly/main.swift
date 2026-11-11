import Foundation
import AppKit
import NamerCore

let usage = """
usage: neatly [options] <file or folder>...
  Suggests short names for badly named files. Changes nothing unless --apply is given.

  --apply      rename the files
  --force      suggest even for names that already look fine (never overrides a name you chose)
  --why        show the evidence, and why files were skipped
  --watch      wait for new files in the folder and suggest names as they arrive
  --where      also suggest a folder to move each file to
  --ask        with --watch: show a dialog for each file (Save / Select place… / Leave as is)
  --menubar    with --watch: show the menu-bar icon (Tidy, options, Pause; drop files or folders on it)
  --screenshots  with --watch: also name new screenshots where macOS saves them, with an Undo pill
  --timeout N  with --ask: save the suggestion after N seconds without an answer (default 5, 0 = wait)
  service install|uninstall   run "--watch ~/Downloads --ask" in the background, starting at login
  --offline    no network lookups (arXiv)
  --no-model   don't use the on-device model
  tidy [folder]  review window: name every badly named file in a folder (Desktop by default), then Rename
  undo <file>  restore a file's original name  (undo --last: the last tidy)
  keep <file>  mark a name as yours: never suggest for it again
  learn <folder>...  learn your naming style from names you already chose (reads names only)
  style        show or set the naming style: --length short|standard|detailed, --case lower|title,
               --sep dash|underscore|space, --date none|prefix|suffix, --app on|off  (--reset to delete)
  --version    print the version
  stats        how often you saved the suggestion unchanged, and your recent edits
"""

setvbuf(stdout, nil, _IOLBF, 0)
migrateFromOldName()   // write log lines immediately, even when not in a terminal
var args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }   // Finder's process id
let version = "0.2.1"
if (args.isEmpty && !AppBundle.isRunningInside) || args.contains("-h") || args.contains("--help") { print(usage); exit(0) }
if args.first == "--version" { print("neatly \(version)"); exit(0) }

if args.first == "dialog" { runDialog(Array(args.dropFirst())) }   // the popup, started by the watcher
if args.first == "toast" { runToast(Array(args.dropFirst())) }     // the screenshot pill

if args.first == "learn" {
    let roots = args.dropFirst().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    guard !roots.isEmpty else { print("usage: neatly learn <folder>..."); exit(1) }
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
        print("Run it on the folders whose style you want for downloads, e.g.: neatly learn ~/courses-fall26")
        exit(0)
    }
    try saved.save()
    print("saved to \(StyleProfile.fileURL.path.replacingOccurrences(of: home, with: "~"))")
    exit(0)
}

if args.first == "style" {
    if args.contains("--reset") { try? FileManager.default.removeItem(at: StyleProfile.fileURL); print("style reset"); exit(0) }
    var p = StyleProfile.load() ?? .standard
    var changed = false
    func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        changed = true; return args[i + 1].lowercased()
    }
    if let v = value("--length") {
        guard let l = StyleProfile.Length(rawValue: v) else { print("--length short|standard|detailed"); exit(1) }
        p.length = l
    }
    if let v = value("--date") {
        guard v == "none" || StyleProfile.DatePosition(rawValue: v) != nil else { print("--date none|prefix|suffix"); exit(1) }
        p.date = StyleProfile.DatePosition(rawValue: v)
    }
    if let v = value("--case") {
        guard ["lower", "title"].contains(v) else { print("--case lower|title"); exit(1) }
        p.lowercase = v == "lower"
    }
    if let v = value("--sep") {
        guard let sep = ["dash": "-", "underscore": "_", "space": " "][v] else { print("--sep dash|underscore|space"); exit(1) }
        p.separator = sep
    }
    if let v = value("--app") { p.appName = v == "on" }
    if let v = value("--copy") { p.copyScreenshots = v == "on" }
    if changed { try p.save() }
    let sep = ["-": "dash", "_": "underscore", " ": "space"][p.separator] ?? p.separator
    print("""
    length  \(p.len.rawValue)        (--length short|standard|detailed)
    case    \(p.lowercase ? "lower" : "title")          (--case lower|title)
    sep     \(sep)           (--sep dash|underscore|space)
    date    \(p.date?.rawValue ?? "none")           (--date none|prefix|suffix)
    app     \(p.appName == true ? "on" : "off")            (--app on|off: screenshots end with the app they were taken in)
    copy    \(p.copyScreenshots == true ? "on" : "off")            (--copy on|off: new screenshots also go to the clipboard)
    """ + (p.suffix.map { "\nsuffix  \($0)" } ?? ""))
    print("\nexample: \(p.render(p.len == .short ? "hot-honey-cornbread" : p.len == .standard ? "hot-honey-cornbread-recipe" : "hot-honey-cornbread-recipe-10-inch-skillet", date: Date(), app: "Safari"))")
    exit(0)
}

let serviceLabel = "dev.neatly.watch"
var servicePlist: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(serviceLabel).plist") }

func launchctl(_ a: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = a
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
}

/// Build neatly.app from this binary, link the `neatly` command to it, and run it at login.
/// The service runs the app's own binary: macOS shows "neatly" (with its icon) when it asks for folder
/// access, and asks again only when the app is updated.
@MainActor func installService() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let uid = getuid()
    let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let exe = try AppBundle.build(from: me, version: version)
    // The command line: ~/.local/bin/neatly → the app's binary (replaces an older copied binary).
    let link = home.appending(path: ".local/bin/neatly")
    try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: exe)

    let log = home.appending(path: "Library/Logs/neatly.log").path
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>Label</key><string>\(serviceLabel)</string>
      <key>ProgramArguments</key><array><string>\(exe.path)</string><string>--watch</string>
        <string>\(home.path)/Downloads</string><string>--ask</string><string>--screenshots</string><string>--menubar</string></array>
      <key>RunAtLoad</key><true/>
      <key>KeepAlive</key><true/>
      <key>StandardOutPath</key><string>\(log)</string>
      <key>StandardErrorPath</key><string>/dev/null</string>
    </dict></plist>
    """
    try FileManager.default.createDirectory(at: servicePlist.deletingLastPathComponent(), withIntermediateDirectories: true)
    try xml.write(to: servicePlist, atomically: true, encoding: .utf8)
    for oldName in ["namer", "filed"] {   // earlier names of this project: stop and remove their service and binary
        launchctl(["bootout", "gui/\(uid)/dev.\(oldName).watch"])
        try? FileManager.default.removeItem(at: servicePlist.deletingLastPathComponent().appending(path: "dev.\(oldName).watch.plist"))
        try? FileManager.default.removeItem(at: home.appending(path: ".local/bin/\(oldName)"))
    }
    migrateFromOldName()   // again: the old service may have written while it was still running
    launchctl(["bootout", "gui/\(uid)/\(serviceLabel)"])
    launchctl(["bootstrap", "gui/\(uid)", servicePlist.path])
}

// Opened from Finder, Spotlight or Launchpad (no arguments): make sure it's running, then get out of the way.
// The service is the one copy that shows the menu-bar icon; opening the app never starts a second one.
if args.isEmpty && AppBundle.isRunningInside {
    if FileManager.default.fileExists(atPath: servicePlist.path) {
        launchctl(["bootstrap", "gui/\(getuid())", servicePlist.path])          // no-op if already loaded
        launchctl(["kickstart", "gui/\(getuid())/\(serviceLabel)"])           // starts it only if not running
    } else {
        try? installService()
    }
    // Ask the running copy to show its window (it may need a moment to start).
    for _ in 0..<2 {
        DistributedNotificationCenter.default().postNotificationName(HomeWindow.showNotification, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
        usleep(1_500_000)
    }
    exit(0)
}

// Tests: build the app into NEATLY_APP_DIR without touching the login item.
if args.first == "app-bundle" {
    let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    print(try AppBundle.build(from: me, version: version).path)
    exit(0)
}

if args.first == "service" {
    switch args.dropFirst().first {
    case "install":
        try installService()
        print("neatly is in \(AppBundle.location.path) and in your menu bar.")
        print("It watches ~/Downloads (asks before filing) and names new screenshots. Log: ~/Library/Logs/neatly.log")
        print("Stop it any time: neatly service uninstall")
    case "uninstall":
        launchctl(["bootout", "gui/\(getuid())/\(serviceLabel)"])
        try? FileManager.default.removeItem(at: servicePlist)
        let link = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/neatly")
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))?.contains("neatly.app") == true {
            try? FileManager.default.removeItem(at: link)
        }
        AppBundle.remove()
        print("stopped and removed (the app, the login item and the neatly command)")
    default: print("usage: neatly service install|uninstall")
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

if args.first == "undo", args.dropFirst().first == "--last" {
    print("put back \(Tidy.undoLast()) name(s) from the last tidy"); exit(0)
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
let screenshots = flag("--screenshots")
let menuBar = flag("--menubar")
let apply = flag("--apply"), force = flag("--force"), why = flag("--why"), watch = flag("--watch"), ask = flag("--ask"), whereTo = flag("--where")
var namer = Namer()
namer.profile = StyleProfile.load() ?? .standard
namer.useNetwork = !flag("--offline")
namer.useModel = !flag("--no-model")
var timeout = namer.profile.countdown ?? 5   // set in the neatly window, or --timeout N
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
@MainActor func askUser(file: String, suggestion: String, folder: URL?) async -> Answer {
    // Runs as its own process and is awaited, so the menu-bar icon stays responsive while it's open.
    let reply = await helper(["dialog", String(timeout), file, suggestion, folder?.path ?? ""])
    let parts = reply.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
    if parts.first == "keep" { return .keep }
    guard parts.first == "save", parts.count >= 3 else { return .noAnswer }
    let typed = parts[1].trimmingCharacters(in: .whitespaces)
    let shown: URL? = parts[2].isEmpty ? nil : URL(fileURLWithPath: parts[2])

    // Power users can still type a path: "~/somewhere/name".
    let expanded = (typed as NSString).expandingTildeInPath
    let name = (expanded as NSString).lastPathComponent
    var chosenFolder: URL? = typed.contains("/") ? URL(fileURLWithPath: (expanded as NSString).deletingLastPathComponent) : shown
    // Compare real paths: /tmp and /private/tmp (or a symlinked home) are the same place.
    let home = Destination.homeRoot.resolvingSymlinksInPath()
    if let f = chosenFolder?.resolvingSymlinksInPath(), !(f.path + "/").hasPrefix(home.path + "/") { chosenFolder = nil }          // only inside your home
    if let f = chosenFolder?.resolvingSymlinksInPath(), f == home.appending(path: "Downloads").resolvingSymlinksInPath() {
        chosenFolder = nil                                                                 // picked Downloads = stay
    }
    return .save(name: name, folder: chosenFolder, auto: parts.count > 3 && parts[3] == "auto")
}

if args.first == "tidy" {
    let targets = args.count > 1 ? args.dropFirst().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                                 : [screenshotFolder()]
    TidyWindow(paths: targets, namer: namer).run()
}

/// Run `neatly <args>` (popup, pill) without blocking the watchers; returns what it printed.
func helper(_ a: [String]) async -> String {
    await withCheckedContinuation { (done: CheckedContinuation<String, Never>) in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        p.arguments = a
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        p.terminationHandler = { _ in
            done.resume(returning: String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        if (try? p.run()) == nil { done.resume(returning: "") }
    }
}

/// Where macOS saves screenshots (System Settings or Cmd-Shift-5 → Options), Desktop by default.
func screenshotFolder() -> URL {
    if let d = ProcessInfo.processInfo.environment["NEATLY_SCREENSHOT_DIR"] { return URL(fileURLWithPath: d) }   // tests
    let home = FileManager.default.homeDirectoryForCurrentUser
    if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !loc.isEmpty {
        let u = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: u.path) { return u }
    }
    return home.appending(path: "Desktop")
}

/// "Screenshot 2026-…", "Screen Shot …" and the same in other languages and tools.
func isScreenshot(_ name: String) -> Bool {
    ["Screenshot ", "Screen Shot ", "CleanShot ", "Ekran Resmi ", "Bildschirmfoto ", "Capture d’écran ", "Captura de pantalla ",
     "Schermafbeelding ", "Istantanea schermo "].contains { name.hasPrefix($0) }
}

/// Screenshots are named the moment they're taken, in place: no popup, no folder question. A pill shows the
/// new name with Undo. The app you were in when you took it is remembered (for the optional "… in Safari").
@MainActor func watchScreenshots(_ dir: URL) async {
    func listing() -> [String: Int] {
        var out: [String: Int] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where isScreenshot(name) {
            out[name] = (try? FileManager.default.attributesOfItem(atPath: dir.appending(path: name).path)[.size] as? Int) ?? -1
        }
        return out
    }
    var seen = Set(listing().keys)
    var pending: [String: (size: Int, app: String?)] = [:]
    print("watching \(dir.path) for screenshots")
    while true {
        try? await Task.sleep(for: .seconds(1))
        let now = listing()
        for (name, size) in now where !seen.contains(name) {
            guard let p = pending[name], p.size == size else {
                // First sight: the app in front is the one being captured (not the screenshot tool itself).
                let front = ProcessInfo.processInfo.environment["NEATLY_FRONT_APP"]   // tests: don't depend on the screen
                    ?? NSWorkspace.shared.frontmostApplication?.localizedName
                let app = ["screencaptureui", "Screenshot", "neatly", "loginwindow"].contains(front ?? "") ? nil : front
                pending[name] = (size, pending[name]?.app ?? app)
                continue
            }
            seen.insert(name); pending[name] = nil
            if paused || namer.profile.watchScreenshots == false { continue }
            let url = dir.appending(path: name)
            guard case .suggested(let s) = await namer.suggest(for: url, app: p.app),
                  let renamed = try? Rename.apply(url, to: s.name) else { print("\(name)  screenshot: no better name"); continue }
            seen.insert(renamed.lastPathComponent)
            print("\(name)  →  \(renamed.lastPathComponent)   [screenshot, \(s.via)]")
            if namer.profile.copyScreenshots == true, let img = NSImage(contentsOf: renamed) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([img])
            }
            // The pill: keep, change the name, ask for another one (up to 3 times), or undo.
            var file = renamed, shown = s.name, rejected: [String] = []
            var chosen: String? = s.name, byYou = false
            pill: while true {
                let reply = await helper(["toast", String(max(timeout, 4)), shown, file.path])
                switch reply {
                case "undo":
                    if let back = try? Rename.undo(file) { Decision.markKeep(back); seen.insert(back.lastPathComponent) }
                    chosen = nil; byYou = true
                    print("   undone")
                    break pill
                case "redo" where rejected.count < 3:
                    rejected.append(shown)
                    var alt = namer; alt.avoid = rejected
                    guard case .suggested(let s2) = await alt.suggest(for: file, explicit: true, app: p.app),
                          let moved = try? Rename.apply(file, to: s2.name) else { print("   no other name found"); byYou = true; break pill }
                    seen.insert(moved.lastPathComponent)
                    file = moved; shown = s2.name; chosen = s2.name
                    print("   another name: \(moved.lastPathComponent)")
                case let r where r.hasPrefix("rename\t"):
                    let typed = String(r.dropFirst(7))
                    if let moved = try? Rename.apply(file, to: typed) { seen.insert(moved.lastPathComponent); file = moved }
                    Decision.markKeep(file)
                    chosen = typed; byYou = true
                    print("   you named it: \(file.lastPathComponent)")
                    break pill
                default:
                    if !rejected.isEmpty { byYou = true }   // you asked for another name and kept it
                    break pill
                }
            }
            let ev = s.evidence
            // Your edits (and undos) teach future names; a pill that just timed out doesn't.
            Correction(original: name, suggested: s.name, chosen: chosen ?? "", via: s.via, source: nil, title: ev.headline,
                       auto: byYou ? nil : true, context: String(gist(ev).prefix(300))).save()
        }
        seen.formIntersection(now.keys)
    }
}

// Watch mode: poll once a second; a file is "done" when its size stops changing.
/// Menu bar → Pause: new files are noticed but left alone until you resume.
var paused = false

@MainActor func watchDownloads() async {
    let dir = URL(fileURLWithPath: ((args.first ?? "~/Downloads") as NSString).expandingTildeInPath)
    let skip: Set<String> = ["crdownload", "download", "part", "partial"]
    let installers: Set<String> = ["dmg", "pkg", "app", "iso"]   // nothing to file
    func listing() -> [String: Int] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        var out: [String: Int] = [:]
        for u in items where !skip.contains(u.pathExtension.lowercased())
            && !(screenshots && isScreenshot(u.lastPathComponent) && dir.standardizedFileURL == screenshotFolder().standardizedFileURL)
            && (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {   // files only
            out[u.lastPathComponent] = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        }
        return out
    }
    var seen = Set(listing().keys)
    var pending: [String: Int] = [:]
    var warmed = Date.distantPast
    if namer.useModel { Task.detached { Namer.prewarm() } }
    let shotDir = screenshotFolder()
    if screenshots { Task { await watchScreenshots(shotDir) } }
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
                if paused || namer.profile.watchDownloads == false { print("\(name)  skip (paused)"); continue }
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
                if nameIdea != original, var local = Destination.style(of: target) {
                    local.length = namer.profile.length; local.date = namer.profile.date; local.appName = namer.profile.appName
                    let styled = local.render(kebab)
                    if styled != nameIdea { print("   styled like its folder: \(styled)"); nameIdea = styled }
                }
                // Downloaded the same file twice? Say so instead of making a "-2" copy.
                // Same bytes already in the suggested folder, or still sitting in Downloads?
                if let twin = Destination.duplicate(of: url, in: target) ?? Destination.duplicate(of: url, in: dir) {
                    // Headless tests: no AppleScript window; behave as if nobody answered.
                    let r = headless ? (ok: true, out: "gave up:true") : osascript("""
                    display dialog "\(name.replacingOccurrences(of: "\"", with: "'"))\\n\\nYou already have this file:\\n\(Destination.short(twin.deletingLastPathComponent())) › \(twin.lastPathComponent.replacingOccurrences(of: "\"", with: "'"))\(timeout > 0 ? "\\n\\nMoves to Trash in \(timeout) s if you don’t answer." : "")" ¬
                      with title "neatly" buttons {"Keep both", "Move to Trash"} default button "Move to Trash" giving up after \(timeout > 0 ? timeout : 300)
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
                switch await askUser(file: name, suggestion: nameIdea, folder: target) {
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

if watch {
    // One process: the menu-bar icon, the Downloads watcher and the screenshot watcher, all on the main run loop.
    NSApplication.shared.setActivationPolicy(.accessory)
    if menuBar { MenuBar.shared.start() }
    Task { await watchDownloads() }
    NSApp.run()
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
