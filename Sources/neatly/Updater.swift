import Foundation
import CryptoKit
import NamerCore

/// Keeps neatly up to date by itself — once the person said yes (asked once, in the welcome window).
/// Every few hours, when online: ask GitHub for the latest release; if it's newer, download it, check its SHA-256
/// against the published one, make sure the new program actually runs, update neatly.app in place, and restart.
/// Any failure (offline, bad download, mismatch) changes nothing; it simply tries again later.
enum Updater {
    /// NEATLY_UPDATE_URL / NEATLY_VERSION_OVERRIDE: tests point this at a local fake release.
    static var feed: URL {
        URL(string: ProcessInfo.processInfo.environment["NEATLY_UPDATE_URL"]
            ?? "https://api.github.com/repos/alpozaydin/neatly/releases/latest")!
    }
    static var current: String { ProcessInfo.processInfo.environment["NEATLY_VERSION_OVERRIDE"] ?? version }

    struct Release { let version: String; let archive: URL; let checksum: URL }

    /// "0.3.10" > "0.3.9"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func latest() async -> Release? {
        var req = URLRequest(url: feed, timeoutInterval: 20)
        req.setValue("neatly-updater", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        func asset(_ name: String) -> URL? {
            assets.first { ($0["name"] as? String) == name }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init) }
        }
        guard let archive = asset("neatly-macos-arm64.tar.gz"), let sum = asset("neatly-macos-arm64.tar.gz.sha256") else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, archive: archive, checksum: sum)
    }

    enum Failure: Error { case download, checksum, unpack, wontRun }

    /// Download, verify and install `r` into neatly.app. Returns the path of the updated app's program.
    static func install(_ r: Release) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appending(path: "neatly-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        guard let (tmp, _) = try? await URLSession.shared.download(from: r.archive),
              let (sumData, _) = try? await URLSession.shared.data(from: r.checksum) else { throw Failure.download }
        let tarball = work.appending(path: "neatly.tar.gz")
        try FileManager.default.moveItem(at: tmp, to: tarball)

        // The fingerprint must match the one published with the release, or nothing is touched.
        let expected = String(decoding: sumData, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let actual = SHA256.hash(data: try Data(contentsOf: tarball)).map { String(format: "%02x", $0) }.joined()
        guard !expected.isEmpty, expected.lowercased() == actual else { throw Failure.checksum }

        guard AppBundle.run("/usr/bin/tar", ["-xzf", tarball.path, "-C", work.path]) == 0 else { throw Failure.unpack }
        let program = work.appending(path: "neatly")
        // The new program must run and say it's the version we expect — before anything is replaced.
        let p = Process(); let out = Pipe()
        p.executableURL = program; p.arguments = ["--version"]; p.standardOutput = out
        guard (try? p.run()) != nil else { throw Failure.wontRun }
        p.waitUntilExit()
        let said = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0, said.contains(r.version) else { throw Failure.wontRun }

        return try AppBundle.build(from: program, version: r.version)   // in place: Launchpad keeps it
    }

    /// One check: returns the new version if neatly was updated.
    static func checkOnce() async -> String? {
        guard let r = await latest(), isNewer(r.version, than: current) else { return nil }
        do {
            _ = try await install(r)
            return r.version
        } catch {
            print("update to \(r.version) skipped: \(error) — will try again later")
            return nil
        }
    }

    /// In the background service: check a little after start, then every 6 hours, only if the person said yes.
    @MainActor static func start() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.environment["NEATLY_UPDATE_SOON"] != nil ? 2 : 120))
            while true {
                if namer.profile.autoUpdate == true, let v = await checkOnce() {
                    print("updated to neatly \(v)")
                    try? Data(v.utf8).write(to: Correction.fileURL.deletingLastPathComponent().appending(path: ".updated"))
                    // Restart into the new version once nothing is on screen (launchd starts it again right away).
                    while InApp.busy { try? await Task.sleep(for: .seconds(5)) }
                    if ProcessInfo.processInfo.environment["NEATLY_APP_DIR"] == nil { exit(0) }
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }
}
