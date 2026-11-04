import Foundation
import NamerCore

// Runs Tests/eval/cases.json and prints a score. Usage: swift run namer-eval [--offline] [--no-model]

struct Cases: Decodable {
    struct DecisionCases: Decodable { let rename: [String]; let keep: [String] }
    let decision: DecisionCases
    let naming: [NamingCase]
}

let args = CommandLine.arguments
let offline = args.contains("--offline")
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let cases = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: root.appending(path: "Tests/eval/cases.json")))

// MARK: 1. Rename-or-keep decision (filenames only)

var decisionMisses: [String] = []
let decisionCases = cases.decision.rename.map { ($0, true) } + cases.decision.keep.map { ($0, false) }
for (name, wantRename) in decisionCases {
    let got = Decision.make(for: URL(fileURLWithPath: "/nonexistent/\(name)"))
    if got.shouldRename != wantRename {
        decisionMisses.append("\(name): expected \(wantRename ? "rename" : "keep"), got \(got)")
    }
}
let decisionOK = decisionCases.count - decisionMisses.count
print("DECISION  \(decisionOK)/\(decisionCases.count) correct")
for m in decisionMisses { print("  ✗ \(m)") }

// MARK: 2. Naming (generated files)

let dir = FileManager.default.temporaryDirectory.appending(path: "namer-eval-\(ProcessInfo.processInfo.processIdentifier)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }

var namer = Namer()
namer.useNetwork = !offline
namer.useModel = !args.contains("--no-model")
print("\nNAMING    model: \(namer.useModel ? Namer.modelStatus : "off")\n")

var exact = 0, head = 0, none = 0, run = 0
var times: [Double] = []
for c in cases.naming {
    if offline && c.network == true { continue }
    run += 1
    let sub = dir.appending(path: c.id)   // own folder per case: some cases share a filename
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let url = try Fixtures.make(c, in: sub)

    let got: String?
    var via = ""
    // Naming is tested on its own: the decision step was scored above.
    switch await namer.suggest(for: url, explicit: true) {
    case .suggested(let s): got = s.name; via = s.via; times.append(s.millis)
    default: got = nil
    }

    let mark: String
    if let got, c.expect.contains(got) { exact += 1; mark = "✓" }
    else if let got, c.expect.contains(where: { $0.split(separator: "-").first == got.split(separator: "-").first }) {
        head += 1; mark = "~"     // right first word: the most important one
    } else if got == nil { none += 1; mark = "∅" }
    else { mark = "✗" }

    let pad = c.id.padding(toLength: 22, withPad: " ", startingAt: 0)
    let gotStr = (got ?? "(none)").padding(toLength: 28, withPad: " ", startingAt: 0)
    print("\(mark) \(pad) \(gotStr) want \(c.expect.first!)\(c.expect.count > 1 ? " (+\(c.expect.count - 1))" : "")   \(via)")
}

times.sort()
@MainActor func pct(_ n: Int) -> String { run == 0 ? "-" : "\(Int((Double(n) / Double(run) * 100).rounded()))%" }
let median = times.isEmpty ? 0 : times[times.count / 2]
let p90 = times.isEmpty ? 0 : times[min(times.count - 1, Int(Double(times.count) * 0.9))]
print("""

SCORE     exact \(exact)/\(run) (\(pct(exact)))   right first word +\(head) (\(pct(exact + head)) total)   no answer \(none)
SPEED     median \(Int(median)) ms   p90 \(Int(p90)) ms
          ✓ exact   ~ first word right   ✗ wrong   ∅ no suggestion
""")
