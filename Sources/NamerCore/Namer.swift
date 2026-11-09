import Foundation

public enum Outcome: Sendable {
    case suggested(Suggestion)
    case kept(why: String)        // step 0 decided not to touch it
    case unsure(why: String)      // looked, but not confident enough to suggest anything
}

public struct Namer: Sendable {
    public var useNetwork = true
    public var useModel = true
    /// The person's naming style. Names are built as lowercase-kebab, then rendered in this style.
    public var profile = StyleProfile.standard
    /// Experimental: ask the model to double-check names made by rules. Measured in namer-eval --verify.
    public var verifyRules = false
    /// Wall-clock budgets. Past these we give up rather than make the user wait.
    /// Images get more: looking at a picture is the expensive, high-value step.
    public var documentBudget: Duration = .seconds(3)
    public var imageBudget: Duration = .seconds(8)
    /// Few-shot learning: show the model names you chose for similar files. nil = read corrections.jsonl.
    public var learnFromCorrections = true
    public var history: [Correction]? = nil

    public init() {}

    /// Load the model and the embedder ahead of time (e.g. while a download is still running): the first call is the slow one.
    public static func prewarm() {
        Model.prewarm()
        Embedder.shared.warm()
    }

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
            return .suggested(Suggestion(name: profile.render(stem), via: via, millis: ms, evidence: e))
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
        e.linkHint = Extract.linkHint(e.sourceURLs)
        let office: Extract.PDFInfo? = switch e.ext {
            case "docx": Extract.docx(url)
            case "pptx": Extract.pptx(url)
            case "ipynb": Extract.notebook(url)
            default: nil
        }
        if let info = office {
            if !Extract.isJunkTitle(info.title, stem: e.stem) { e.metadataTitle = info.title; e.steps.append("meta") }
            e.headline = info.headline
            e.bodySnippet = info.snippet
            if info.hasText { e.steps.append("text") }
        } else if e.ext == "zip" {
            let names = Extract.zipListing(url)
            let tops = Set(names.compactMap { $0.split(separator: "/").first.map(String.init) })
            if tops.count == 1, let top = tops.first, names.count > 1, Decision.junkReason(top) == nil {
                e.steps.append("zip")
                return done(Style.join(Style.words(top)), "rules[zip-folder]")
            }
            if !names.isEmpty { e.bodySnippet = "Archive contains: " + names.joined(separator: ", "); e.steps.append("zip") }
        } else if Self.pdfLike.contains(e.ext), let info = Extract.pdf(url) {
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
        if let n = ruleName(e) {
            if verifyRules, useModel, await Model.rejects(name: n, for: e) {
                e.steps.append("rule-rejected:\(n)")
            } else {
                return done(n, "rules[\(trail)]")
            }
        }

        // 6. On-device model. For images it looks at the picture itself (when the OS supports it).
        let budget = isImage ? imageBudget : documentBudget
        if useModel, clock.now - start < budget {
            let remaining = budget - (clock.now - start)
            let snapshot = e
            let look = isImage && Model.canSeeImages
            if look { e.steps.append("vision") }
            let examples = learnFromCorrections ? Examples.similar(to: snapshot, history: history ?? Correction.all()) : []
            if !examples.isEmpty { e.steps.append("\(examples.count) of your names") }
            if let w = await withTimeout(remaining, { await Model.name(for: snapshot, lookAtImage: look, examples: examples) }) ?? nil {
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
        // Look at heading + start of text together; the kind list is ordered specific → generic,
        // so "DEKONT … Öğrenim Ücreti" is tuition, not just a receipt.
        let kind = Style.kind(in: strong + " " + String(weak.prefix(300))) ?? Style.kind(in: weak)

        // Course files: course code first, then what it is. ceng213-hw2, ceng499-lecture5, ceng334-syllabus.
        let personal: Set<String> = ["transcript", "enrollment", "cv", "exam-schedule", "tuition", "learning-agreement"]   // mention courses, but are not about one
        if !(kind.map { personal.contains($0.word) } ?? false), let course = courseCode(e) {
            // A syllabus mentions "midterms"; a midterm never mentions "syllabus" — so the document kind wins.
            let kindItem = kind.flatMap { ["syllabus", "schedule"].contains($0.word) ? $0.word : nil }
            let full = e.bodySnippet ?? ""
            // Title says "midterm", page says "Midterm I" → take the one with the number.
            let fromTitle = Style.academicItem(in: strong), fromPage = Style.academicItem(in: full)
            let numbered = fromPage.flatMap { p in
                fromTitle.map { p.hasPrefix($0) && p != $0 } ?? false ? p : nil }
            if let item = kindItem ?? numbered ?? fromTitle ?? fromPage {
                // Exams are often old papers: name them by the term written on them. ceng331-final-fall22
                let isExam = ["midterm", "final", "quiz"].contains { item.hasPrefix($0) }
                let term = isExam ? Style.termIn(strong + "\n" + String(full.prefix(500))) : nil
                // "midterm KEY" / "Solutions" → …-solutions. Title, heading and filename only (exam text says "key" rarely).
                let sol = isExam && Style.isSolutions([e.metadataTitle, e.headline, e.stem].compactMap { $0 }.joined(separator: " "))
                return Style.join([course, item, term, sol ? "solutions" : nil].compactMap { $0 })
            }
        }

        // "LuMon: Lunar Monocular Depth Estimation Benchmark" → lumon. Papers and projects name themselves.
        // "Project Proposal: Campus Food Waste Tracker" → the part before the colon is generic → use the topic.
        if kind == nil, let t = e.metadataTitle ?? e.headline, let colon = t.firstIndex(of: ":"),
           t.distance(from: colon, to: t.endIndex) > 15 {
            let head = Style.words(String(t[..<colon]))
            let generic: Set<String> = ["project", "proposal", "report", "homework", "assignment", "chapter", "part",
                                        "summary", "abstract", "introduction", "re", "fwd", "subject", "draft", "notes"]
            if (1...2).contains(head.count), head.allSatisfy({ generic.contains($0) }) {
                let topic = Style.words(String(t[t.index(after: colon)...])).prefix(3)
                return Style.join(Array(topic) + [head.last!])
            }
            if (1...2).contains(head.count), head.joined().count >= 3 { return Style.join(head) }
        }

        // Archives from Kaggle, GitHub etc.: the link names the dataset or repo.
        if kind == nil, e.ext == "zip", let hint = e.linkHint { return Style.join(Style.words(hint)) }

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
