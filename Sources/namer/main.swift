import Foundation
import NamerCore

let usage = """
usage: namer [options] <file or folder>...
  Suggests short names for badly named files. Changes nothing unless --apply is given.

  --apply      rename the files
  --force      suggest even for names that already look fine (never overrides a name you chose)
  --why        show the evidence, and why files were skipped
  --offline    no network lookups (arXiv)
  --no-model   don't use the on-device model
  undo <file>  restore a file's original name
  keep <file>  mark a name as yours: never suggest for it again
"""

var args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("-h") || args.contains("--help") { print(usage); exit(0) }

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
let apply = flag("--apply"), force = flag("--force"), why = flag("--why")
var namer = Namer()
namer.useNetwork = !flag("--offline")
namer.useModel = !flag("--no-model")

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
