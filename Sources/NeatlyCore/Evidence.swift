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
    public var imageURL: URL?             // the picture to read and look at: the file itself, or a Quick Look rendering
    public var place: String?             // where a photo was taken ("Galata Tower, Istanbul, Türkiye"), from its GPS
    public var placeName: String?         // the short form that can go in a name ("Galata Tower", "Istanbul")

    /// A screen capture (macOS, CleanShot, other languages' default names): named by what's on screen, not as a photo.
    public var isScreenshot: Bool {
        let pattern = #"(?i)^(screenshot|screen shot|cleanshot|bildschirmfoto|ekran resmi|capture d.écran|captura de pantalla|schermafbeelding|istantanea|skärmavbild|snímek|zrzut ekranu|screen recording|ekran kaydı|bildschirmaufnahme|enregistrement de l.écran|grabación de pantalla|schermopname|registrazione schermo)"#
        if stem.range(of: pattern, options: .regularExpression) != nil { return true }
        // Already renamed by neatly ("↻ another name"): its first name says what it was.
        return Rename.originalName(url)?.range(of: pattern, options: .regularExpression) != nil
    }

    public struct Paper: Sendable {
        public var title: String
        public var year: Int?
    }

    public init(url: URL) {
        self.url = url
        self.stem = url.deletingPathExtension().lastPathComponent
        self.ext = url.pathExtension.lowercased()
    }

    /// Host of the most specific source URL, e.g. "student.northfield.edu".
    public var sourceHost: String? {
        for s in sourceURLs.reversed() {
            let plain = s.hasPrefix("blob:") ? String(s.dropFirst(5)) : s   // blob:https://www.recraft.ai/…
            if let host = URL(string: plain)?.host(), !host.isEmpty { return host }
        }
        return nil
    }

    /// Where a downloaded file came from, read straight from the file (nothing else is read).
    public static func sourceHost(of url: URL) -> String? {
        var e = Evidence(url: url)
        e.sourceURLs = Extract.sourceURLs(url)
        return e.sourceHost
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
