import Foundation

/// Stage 2 — exact lookups by identifier. One small request, perfect accuracy, no guessing.
enum Papers {
    static let timeout: TimeInterval = 2.5

    /// arXiv ids look like 1909.00871 or 2406.01860v1, in the filename or the download URL.
    static func arxivID(stem: String, sources: [String]) -> String? {
        let re = try! Regex(#"(?:^|[^\d.])(\d{4}\.\d{4,5})(v\d+)?(?![\d])"#)
        if let m = stem.firstMatch(of: re), let id = m.output[1].substring { return String(id) }
        for s in sources where s.contains("arxiv.org") {
            if let m = s.firstMatch(of: re), let id = m.output[1].substring { return String(id) }
        }
        return nil
    }

    static func arxiv(_ id: String) async -> Evidence.Paper? {
        guard let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(id)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("namer/0.1 (open-source file renamer)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let xml = String(data: data, encoding: .utf8),
              let entry = xml.range(of: "<entry>") else { return nil }
        let body = String(xml[entry.upperBound...])
        guard let title = tag("title", in: body) else { return nil }
        let year = tag("published", in: body).flatMap { Int($0.prefix(4)) }
        return .init(title: title.split(whereSeparator: \.isWhitespace).joined(separator: " "), year: year)
    }

    private static func tag(_ name: String, in s: String) -> String? {
        guard let a = s.range(of: "<\(name)>"), let b = s.range(of: "</\(name)>", range: a.upperBound..<s.endIndex)
        else { return nil }
        return String(s[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
