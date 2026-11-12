import Foundation

/// Wakes up the moment something changes in a folder (a download finishing, a screenshot being saved),
/// instead of checking once a second. macOS tells us through a file-system event on the folder itself;
/// a slow timer stays as a safety net. Idle cost: nothing.
@MainActor
final class DirWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var waiting: CheckedContinuation<Void, Never>?
    private var changed = false

    init(_ dir: URL) {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .link],
                                                            queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.fire() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func fire() {
        changed = true
        waiting?.resume(); waiting = nil
    }

    /// Return when the folder changes, or after `timeout` at the latest.
    func next(timeout: Duration) async {
        if changed { changed = false; return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiting = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                if let w = self?.waiting { self?.waiting = nil; w.resume() }
            }
        }
        changed = false
    }
}
