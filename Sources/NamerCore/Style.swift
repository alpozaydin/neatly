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
        tokens(phrase).filter { !filler.contains($0) }
    }

    /// Like `words`, but keeps filler — for pattern matching where "final" or "of" matter.
    public static func tokens(_ phrase: String) -> [String] {
        let latin = phrase
            .replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "I")
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? phrase
        return latin.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { !$0.isEmpty }
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
        .init(word: "exam-schedule", qualifier: .term, keepIssuer: false, triggers: ["exam schedule", "final exam schedule", "sinav programi", "sinav takvimi"]),
        .init(word: "schedule", qualifier: .term, keepIssuer: false, triggers: ["course schedule", "ders programi", "weekly schedule"]),
        .init(word: "tuition", qualifier: .term, keepIssuer: false, triggers: ["tuition fee", "harc", "ogrenim ucreti", "katki payi"]),
        .init(word: "enrollment", qualifier: .term, keepIssuer: false, triggers: ["ogrenci belgesi", "enrollment certificate", "certificate of enrollment"]),
        .init(word: "invoice", qualifier: .month, keepIssuer: true, triggers: ["invoice", "fatura", "e arsiv fatura"]),
        .init(word: "receipt", qualifier: .month, keepIssuer: true, triggers: ["receipt", "dekont", "makbuz"]),
        .init(word: "statement", qualifier: .month, keepIssuer: true, triggers: ["account statement", "hesap ozeti", "ekstre"]),
        .init(word: "payslip", qualifier: .month, keepIssuer: true, triggers: ["payslip", "bordro", "pay stub"]),
        .init(word: "ticket", qualifier: .month, keepIssuer: true, triggers: ["boarding pass", "e ticket", "bilet"]),
        .init(word: "learning-agreement", qualifier: .none, keepIssuer: false, triggers: ["learning agreement"]),
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

    // MARK: Courses (students' most common files)

    /// Department prefixes that appear in course codes. Other prefixes only count on a university website.
    static let departments: Set<String> = [
        "ceng", "cs", "cse", "cmpe", "comp", "ece", "ee", "eee", "math", "phys", "chem", "bio", "biol", "stat",
        "econ", "ie", "me", "ae", "am", "mse", "chbe", "ce", "psy", "psyc", "phil", "hist", "eng", "engl", "is",
        "sts", "tur", "arch", "ba", "bus", "fin", "acc", "mgmt", "ling", "info", "inf", "ds", "ai", "ml",
    ]

    /// "CENG 334", "MATH119", "cs-101" → "ceng334". Nil if none.
    public static func courseCode(in text: String, academicSource: Bool) -> String? {
        let re = try! Regex(#"\b([A-Za-z]{2,5})[ \-]?(\d{3,4})\b"#)
        for m in text.matches(of: re) {
            guard let d = m.output[1].substring, let n = m.output[2].substring else { continue }
            let dept = d.lowercased()
            let looksLikeCode = d == d.uppercased() || departments.contains(dept)
            if departments.contains(dept) || (academicSource && looksLikeCode && d.count >= 2) {
                return dept + n
            }
        }
        return nil
    }

    /// "Homework 2" → hw2, "Lecture 5" → lecture5, "Lab 3" → lab3, "Midterm" → midterm, "Syllabus" → syllabus.
    public static func academicItem(in text: String) -> String? {
        let t = " " + tokens(text).joined(separator: " ") + " "
        // A syllabus is recognizable by its sections even when it never says "syllabus".
        let sections = ["instructor", "teaching assistant", "lecture hours", "office hours", "grading", "textbook",
                        "prerequisite", "course objectives", "attendance", "course description", "learning outcomes"]
        if sections.filter({ t.contains($0) }).count >= 3 { return "syllabus" }
        let patterns: [(String, String)] = [
            (#"\b(?:homework|hw|odev|assignment|ass)\s?(\d{1,2})\b"#, "hw"),
            (#"\b(?:lecture|lec)\s?(\d{1,2})\b"#, "lecture"),
            (#"\b(?:lab|laboratory)\s?(\d{1,2})\b"#, "lab"),
            (#"\b(?:recitation|rec)\s?(\d{1,2})\b"#, "rec"),
            (#"\b(?:quiz)\s?(\d{1,2})\b"#, "quiz"),
            (#"\b(?:week|hafta)\s?(\d{1,2})\b"#, "week"),
            (#"\b(?:project|proje)\s?(\d{1,2})\b"#, "project"),
            (#"\b(?:midterm|vize)\s?(\d?)"#, "midterm"),
            (#"\b(?:final exam|final examination|final sinavi)\b()"#, "final"),
        ]
        for (p, word) in patterns {
            if let m = t.firstMatch(of: try! Regex(p)) {
                let n = m.output[1].substring.map(String.init) ?? ""
                return word + n
            }
        }
        // An exam paper that just says "FINAL" on top.
        if t.contains(" final ") && t.contains("exam") { return "final" }
        for plain in ["syllabus", "cheat sheet", "cheatsheet"] where t.contains(plain) {
            return plain.replacingOccurrences(of: " ", with: "")
        }
        return nil
    }

    // MARK: Period ("Ekim 2026", "October 2026", "03.11.2026")

    static let months: [String: Int] = {
        let names = [
            ["january", "jan", "ocak", "januar"], ["february", "feb", "subat", "februar"],
            ["march", "mar", "mart", "marz", "maerz"], ["april", "apr", "nisan"], ["may", "mayis", "mai"],
            ["june", "jun", "haziran", "juni"], ["july", "jul", "temmuz", "juli"], ["august", "aug", "agustos"],
            ["september", "sep", "sept", "eylul"], ["october", "oct", "ekim", "oktober", "okt"],
            ["november", "nov", "kasim"], ["december", "dec", "aralik", "dezember", "dez"],
        ]
        var out: [String: Int] = [:]
        for (i, list) in names.enumerated() { for n in list { out[n] = i + 1 } }
        return out
    }()

    /// The period a document is about, if its text says so. Month name + year wins over a full date.
    public static func period(in text: String) -> Date? {
        let w = words(text)
        for (i, word) in w.enumerated() {
            guard let m = months[word] else { continue }
            for j in [i + 1, i - 1] where w.indices.contains(j) {
                if let y = Int(w[j]), (2000...2100).contains(y) {
                    return Calendar.current.date(from: DateComponents(year: y, month: m, day: 1))
                }
            }
        }
        let re = try! Regex(#"\b(0?[1-9]|[12]\d|3[01])[./](0?[1-9]|1[0-2])[./](20\d{2})\b"#)
        if let m = text.firstMatch(of: re), let mo = Int(m.output[2].substring ?? ""), let y = Int(m.output[3].substring ?? "") {
            return Calendar.current.date(from: DateComponents(year: y, month: mo, day: 1))
        }
        return nil
    }

    /// The term a document itself states: "Fall '2022-2023" → fall22, "2024 Fall" → fall24, "Bahar 2025" → spring25.
    /// In an academic year "2022-2023", fall is the first year and spring/summer the second.
    public static func termIn(_ text: String) -> String? {
        let w = tokens(text)
        let seasons = ["fall": "fall", "autumn": "fall", "guz": "fall", "spring": "spring", "bahar": "spring",
                       "summer": "summer", "yaz": "summer"]
        for (i, word) in w.enumerated() {
            guard let season = seasons[word] else { continue }
            let near = (max(0, i - 2)...min(w.count - 1, i + 3)).compactMap { Int(w[$0]) }.filter { (2000...2100).contains($0) }
            guard let first = near.min() else { continue }
            let year = (near.count >= 2 && season != "fall") ? near.max()! : first
            return season + String(year % 100)
        }
        return nil
    }
}
