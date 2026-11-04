import Foundation

public enum Outcome: Sendable {
    case suggested(Suggestion)
    case kept(why: String)        // step 0 decided not to touch it
    case unsure(why: String)      // looked, but not confident enough to suggest anything
}

public struct Namer: Sendable {
    public var useNetwork = true
    public var useModel = true
    /// Wall-clock budgets. Past these we give up rather than make the user wait.
    /// Images get more: looking at a picture is the expensive, high-value step.
    public var documentBudget: Duration = .seconds(3)
    public var imageBudget: Duration = .seconds(8)

    public init() {}

    public static var modelStatus: String { Model.status }

    public static let pdfLike: Set<String> = ["pdf"]
    public static let imageLike: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "webp"]

    /// `explicit`: the user pointed at this file (Finder hotkey, CLI --force), so skip the
    /// "name already meaningful" check — but never override a name they chose themselves.
    public func suggest(for url: URL, explicit: Bool = false) async -> Outcome {
        let clock = ContinuousClock()
        let start = clock.now
        var e = Evidence(url: url)

        // 0. Binary decision first. Costs ~0 ms and reads no content.
        let decision = Decision.make(for: url, explicit: explicit)
        guard decision.shouldRename else {
            if case .keep(let why) = decision { return .kept(why: why) }
            return .kept(why: "")
        }

        func done(_ stem: String?, _ via: String) -> Outcome {
            guard let stem, stem.count >= 2, stem != e.stem.lowercased() else {
                return .unsure(why: "no better name found")
            }
            let c = (clock.now - start).components
            let ms = Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
            return .suggested(Suggestion(name: stem, via: via, millis: ms, evidence: e))
        }
        var trail: String { e.steps.joined(separator: "+") }

        // 1. Where it came from + date
        e.sourceURLs = Extract.sourceURLs(url)
        e.date = Extract.date(url, stem: e.stem)
        if !e.sourceURLs.isEmpty { e.steps.append("source") }

        // 2. Exact identifier lookup (arXiv)
        if useNetwork, let id = Papers.arxivID(stem: e.stem, sources: e.sourceURLs),
           let paper = await Papers.arxiv(id) {
            e.paper = paper
            e.steps.append("arxiv")
            return done(Style.paperName(title: paper.title, year: paper.year), "arxiv")
        }

        let isImage = Self.imageLike.contains(e.ext)
        if Self.pdfLike.contains(e.ext), let info = Extract.pdf(url) {
            // 3. Embedded title. If it already names a known kind, stop before reading the page.
            if !Extract.isJunkTitle(info.title, stem: e.stem) { e.metadataTitle = info.title; e.steps.append("meta") }
            if e.metadataTitle != nil, let n = ruleName(e) { return done(n, "rules[\(trail)]") }
            // 4. Page 1 only
            e.headline = info.headline
            e.bodySnippet = info.snippet
            if info.hasText { e.steps.append("page1") }
            // 5. Scanned PDF: OCR page 1
            if !info.hasText, e.metadataTitle == nil, let text = Extract.ocr(pdfFirstPage: url) {
                e.bodySnippet = text; e.steps.append("ocr")
            }
        } else if isImage {
            // 5. Cheap image signals first: text in the image, and Apple's label classifier.
            if let text = Extract.ocr(image: url) { e.bodySnippet = text; e.steps.append("ocr") }
            e.labels = Extract.labels(image: url)
            if !e.labels.isEmpty { e.steps.append("labels") }
        }

        // Known document kinds are decided by rules: fast and predictable.
        if let n = ruleName(e) { return done(n, "rules[\(trail)]") }

        // 6. On-device model. For images it looks at the picture itself (when the OS supports it).
        let budget = isImage ? imageBudget : documentBudget
        if useModel, clock.now - start < budget {
            let remaining = budget - (clock.now - start)
            let snapshot = e
            let look = isImage && Model.canSeeImages
            if look { e.steps.append("vision") }
            if let w = await withTimeout(remaining, { await Model.name(for: snapshot, lookAtImage: look) }) ?? nil {
                if let course = courseCode(e) {
                    return done(Style.join([course] + w.filter { $0 != course }), "model[\(trail)]")
                }
                return done(Style.join(w + [qualifierFor(e)].compactMap { $0 }), "model[\(trail)]")
            }
        }

        // Fallback: a clean title is still better than a junk name.
        if let t = e.metadataTitle ?? e.headline {
            return done(Style.join(Array(Style.words(t).prefix(3)) + [qualifierFor(e)].compactMap { $0 }), "title")
        }
        return .unsure(why: "not enough evidence")
    }

    /// Rules: known document kinds and course files are named directly — fast and predictable.
    func ruleName(_ e: Evidence) -> String? {
        let strong = [e.metadataTitle, e.headline].compactMap { $0 }.joined(separator: " ")
        let weak = String((e.bodySnippet ?? "").prefix(400))
        let kind = Style.kind(in: strong) ?? Style.kind(in: weak)

        // Course files: course code first, then what it is. ceng213-hw2, ceng499-lecture5, ceng334-syllabus.
        let personal: Set<String> = ["transcript", "enrollment", "cv"]   // full of course codes, but not about one
        if !(kind.map { personal.contains($0.word) } ?? false), let course = courseCode(e) {
            // A syllabus mentions "midterms"; a midterm never mentions "syllabus" — so the document kind wins.
            let kindItem = kind.flatMap { ["syllabus", "schedule"].contains($0.word) ? $0.word : nil }
            if let item = kindItem ?? Style.academicItem(in: strong) ?? Style.academicItem(in: weak) {
                return Style.join([course, item])
            }
        }

        // "LuMon: Lunar Monocular Depth Estimation Benchmark" → lumon. Papers and projects name themselves.
        if kind == nil, let t = e.metadataTitle ?? e.headline, let colon = t.firstIndex(of: ":"),
           t.distance(from: colon, to: t.endIndex) > 15 {
            let head = Style.words(String(t[..<colon]))
            if (1...2).contains(head.count), head.joined().count >= 3 { return Style.join(head) }
        }

        guard let kind else { return nil }
        if kind.word == "cv" { return cvName(e) }
        let issuer = kind.keepIssuer ? Style.issuer(host: e.sourceHost) : nil
        // Bills and payslips: the month they are FOR, not the day they arrived.
        let date = kind.qualifier == .month ? (Style.period(in: strong + " " + weak) ?? e.date) : e.date
        return Style.join([kind.word, issuer, Style.qualifier(kind.qualifier, date)].compactMap { $0 })
    }

    /// Someone else's CV: cv-john-smith. Your own: just cv.
    func cvName(_ e: Evidence) -> String {
        let candidates = [e.headline, e.metadataTitle].compactMap { $0 }
        let person = candidates.lazy.map { Style.words($0).filter { !["cv", "resume", "curriculum", "vitae"].contains($0) } }
            .first { (2...3).contains($0.count) && $0.allSatisfy { $0.allSatisfy(\.isLetter) } }
        guard let person else { return "cv" }
        let me = Set(Style.words(NSFullUserName()))
        return Set(person).isSubset(of: me) ? "cv" : Style.join(["cv"] + person)
    }

    func courseCode(_ e: Evidence) -> String? {
        let text = [e.metadataTitle, e.headline, e.bodySnippet.map { String($0.prefix(400)) }].compactMap { $0 }
            .joined(separator: "\n")
        return Style.courseCode(in: text, academicSource: isAcademic(e))
    }

    func isAcademic(_ e: Evidence) -> Bool {
        guard let host = e.sourceHost else { return false }
        let lms = ["odtuclass", "moodle", "canvas", "blackboard", "classroom.google", "edu"]
        return lms.contains { host.contains($0) }
    }

    /// Qualifier for model-named files: academic sources get a term, others nothing (keep it short).
    func qualifierFor(_ e: Evidence) -> String? {
        guard isAcademic(e), let date = e.date else { return nil }
        return Style.term(date)
    }
}

func withTimeout<T: Sendable>(_ d: Duration, _ op: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { g in
        g.addTask { await op() }
        g.addTask { try? await Task.sleep(for: d); return nil }
        let first = await g.next() ?? nil
        g.cancelAll()
        return first
    }
}
