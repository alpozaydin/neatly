import Foundation

/// Everything we learned about a file, gathered cheapest-first.
/// Each field is optional: the pipeline stops as soon as it has enough.
public struct Evidence: Sendable {
    public var url: URL
    public var stem: String               // filename without extension
    public var ext: String                // lowercased extension
    public var sourceURLs: [String] = []  // where it was downloaded from (newest first)
    public var date: Date?                // best guess of when the document is "from"
    public var metadataTitle: String?     // title stored inside the file
    public var headline: String?          // largest text on page 1
    public var bodySnippet: String?       // capped prefix of page 1 text / OCR
    public var linkHint: String?          // meaningful words in the download link
    public var labels: [String] = []      // what a photo shows (on-device classifier)
    public var paper: Paper?              // arXiv/DOI lookup result
    public var steps: [String] = []       // which stages contributed, for debugging

    public struct Paper: Sendable {
        public var title: String
        public var year: Int?
    }

    public init(url: URL) {
        self.url = url
        self.stem = url.deletingPathExtension().lastPathComponent
        self.ext = url.pathExtension.lowercased()
    }

    /// Host of the most specific source URL, e.g. "student.metu.edu.tr".
    public var sourceHost: String? {
        for s in sourceURLs.reversed() {
            let plain = s.hasPrefix("blob:") ? String(s.dropFirst(5)) : s   // blob:https://www.recraft.ai/…
            if let host = URL(string: plain)?.host(), !host.isEmpty { return host }
        }
        return nil
    }

    /// Human description of the source for the model ("Gmail attachment", "Google Images", "recraft.ai").
    public var sourceDescription: String? {
        guard let host = sourceHost else { return nil }
        if host.hasPrefix("mail-attachment.googleusercontent") || host == "mail.google.com" { return "Gmail attachment" }
        if host.hasSuffix("gstatic.com") { return "Google Images thumbnail" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public struct Suggestion: Sendable {
    public var name: String          // final filename stem, no extension
    public var via: String           // which stage produced it
    public var millis: Double
    public var evidence: Evidence
}
