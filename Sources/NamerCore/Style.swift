import Foundation

/// The naming convention: lowercase kebab-case, most distinctive word first,
/// qualifier (term / year / month) last, as few words as possible.
///   transcript-fall26   unidepth-2024   invoice-turkcell-nov26
public enum Style {
    public static let maxWords = 4
    public static let maxLength = 40

    /// Words that never carry meaning in a filename.
    static let filler: Set<String> = [
        "a", "an", "the", "of", "for", "and", "or", "to", "in", "on", "at", "by", "with", "from", "via",
        "student", "official", "document", "file", "copy", "final", "new", "version", "page", "pdf",
        "ve", "ile", "icin", "bir", "belgesi", "belge",
    ]

    /// Turn any phrase into slug words: ASCII (Turkish-safe), lowercase, filler removed.
    public static func words(_ phrase: String) -> [String] {
        let latin = phrase
            .replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "I")
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? phrase
        return latin.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { !filler.contains($0) && !$0.isEmpty }
    }

    public static func join(_ parts: [String]) -> String {
        var out: [String] = []
        for p in parts where !p.isEmpty && !out.contains(p) {
            if out.count == maxWords { break }
            if (out + [p]).joined(separator: "-").count > maxLength { break }
            out.append(p)
        }
        return out.joined(separator: "-")
    }

    // MARK: Qualifiers

    /// Academic term: Sep–Jan fall, Feb–Jun spring, Jul–Aug summer. January belongs to the previous fall.
    public static func term(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        let m = c.month!, y = c.year!
        switch m {
        case 2...6: return "spring\(y % 100)"
        case 7...8: return "summer\(y % 100)"
        case 1:     return "fall\((y - 1) % 100)"
        default:    return "fall\(y % 100)"
        }
    }

    public static func month(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMyy"
        return f.string(from: date).lowercased()   // nov26
    }

    // MARK: Known document kinds

    public enum Qualifier: Sendable { case term, month, year, none }

    public struct Kind: Sendable {
        public let word: String
        public let qualifier: Qualifier
        public let keepIssuer: Bool      // invoice-turkcell-nov26 vs transcript-fall26
        let triggers: [String]
    }

    /// First match wins, so more specific kinds come first. Triggers are matched as whole slug words/phrases.
    public static let kinds: [Kind] = [
        .init(word: "transcript", qualifier: .term, keepIssuer: false, triggers: ["transcript", "transkript", "not dokumu"]),
        .init(word: "syllabus", qualifier: .term, keepIssuer: false, triggers: ["syllabus", "course outline", "ders plani"]),
        .init(word: "schedule", qualifier: .term, keepIssuer: false, triggers: ["course schedule", "ders programi", "weekly schedule"]),
        .init(word: "enrollment", qualifier: .term, keepIssuer: false, triggers: ["ogrenci belgesi", "enrollment certificate", "certificate of enrollment"]),
        .init(word: "invoice", qualifier: .month, keepIssuer: true, triggers: ["invoice", "fatura", "e arsiv fatura"]),
        .init(word: "receipt", qualifier: .month, keepIssuer: true, triggers: ["receipt", "dekont", "makbuz"]),
        .init(word: "statement", qualifier: .month, keepIssuer: true, triggers: ["account statement", "hesap ozeti", "ekstre"]),
        .init(word: "payslip", qualifier: .month, keepIssuer: true, triggers: ["payslip", "bordro", "pay stub"]),
        .init(word: "ticket", qualifier: .month, keepIssuer: true, triggers: ["boarding pass", "e ticket", "bilet"]),
        .init(word: "contract", qualifier: .year, keepIssuer: true, triggers: ["contract", "agreement", "sozlesme"]),
        .init(word: "cv", qualifier: .none, keepIssuer: false, triggers: ["curriculum vitae", "resume", "ozgecmis"]),
    ]

    public static func kind(in text: String) -> Kind? {
        let hay = " " + words(text).joined(separator: " ") + " "
        return kinds.first { k in k.triggers.contains { hay.contains(" " + words($0).joined(separator: " ") + " ") } }
    }

    public static func qualifier(_ q: Qualifier, _ date: Date?) -> String? {
        guard let date else { return nil }
        switch q {
        case .term: return term(date)
        case .month: return month(date)
        case .year: return String(Calendar.current.component(.year, from: date))
        case .none: return nil
        }
    }

    /// Short issuer word from the download host: student.metu.edu.tr → metu.
    public static func issuer(host: String?) -> String? {
        guard let host else { return nil }
        let generic: Set<String> = ["www", "com", "org", "net", "edu", "gov", "tr", "co", "uk", "student", "mail",
                                    "app", "portal", "secure", "online", "my", "web", "cdn", "files", "download", "static"]
        let known = ["turkiye.gov.tr": "edevlet", "mail.google.com": "gmail", "drive.google.com": "gdrive"]
        if let k = known.first(where: { host.hasSuffix($0.key) }) { return k.value }
        return host.split(separator: ".").map(String.init).last { !generic.contains($0) }
    }

    // MARK: Papers

    /// "UniDepth: Universal Monocular Metric Depth Estimation" → unidepth-2024.
    /// Without a short name before the colon, keep the first few meaningful words.
    public static func paperName(title: String, year: Int?) -> String {
        let y = year.map(String.init)
        if let colon = title.firstIndex(of: ":") {
            let head = words(String(title[..<colon]))
            if (1...2).contains(head.count) { return join(head + [y].compactMap { $0 }) }
        }
        return join(Array(words(title).prefix(3)) + [y].compactMap { $0 })
    }
}
