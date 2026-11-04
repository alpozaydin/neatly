import Foundation

/// Renaming with an undo trail: the original name is kept in an extended attribute on the file itself,
/// so undo works even after the app restarts or the file moves.
public enum Rename {
    static let attr = "dev.namer.original-name"
    static let folderAttr = "dev.namer.original-folder"

    /// Rename (and optionally move to `folder`). Never overwrites: adds -2, -3… instead.
    @discardableResult
    public static func apply(_ url: URL, to stem: String, in folder: URL? = nil) throws -> URL {
        let ext = url.pathExtension
        let dir = folder ?? url.deletingLastPathComponent()
        if folder != nil { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        var target = dir.appending(path: ext.isEmpty ? stem : "\(stem).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {   // never overwrite
            target = dir.appending(path: ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)")
            n += 1
        }
        let original = Array(url.lastPathComponent.utf8)
        if originalName(url) == nil {   // keep the very first name and folder across repeated renames
            _ = setxattr(url.path, attr, original, original.count, 0, 0)
            let from = Array(url.deletingLastPathComponent().path.utf8)
            _ = setxattr(url.path, folderAttr, from, from.count, 0, 0)
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    public static func originalName(_ url: URL) -> String? { read(url, attr) }

    static func read(_ url: URL, _ name: String) -> String? {
        let len = getxattr(url.path, name, nil, 0, 0, 0)
        guard len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard getxattr(url.path, name, &buf, len, 0, 0) == len else { return nil }
        return String(decoding: buf, as: UTF8.self)
    }

    @discardableResult
    public static func undo(_ url: URL) throws -> URL? {
        guard let name = originalName(url) else { return nil }
        let folder = read(url, folderAttr).map { URL(fileURLWithPath: $0) } ?? url.deletingLastPathComponent()
        let target = folder.appending(path: name)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: target.path])
        }
        try FileManager.default.moveItem(at: url, to: target)
        removexattr(target.path, attr, 0)
        removexattr(target.path, folderAttr, 0)
        return target
    }
}
