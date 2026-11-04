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
            guard let stem, stem.count >= 3, stem != e.stem.lowercased() else {
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
                return done(Style.join(w + [qualifierFor(e)].compactMap { $0 }), "model[\(trail)]")
            }
        }

        // Fallback: a clean title is still better than a junk name.
        if let t = e.metadataTitle ?? e.headline {
            return done(Style.join(Array(Style.words(t).prefix(3)) + [qualifierFor(e)].compactMap { $0 }), "title")
        }
        return .unsure(why: "not enough evidence")
    }

    /// Rules: if the strongest evidence names a known document kind, build the name directly.
    func ruleName(_ e: Evidence) -> String? {
        let strong = [e.metadataTitle, e.headline].compactMap { $0 }.joined(separator: " ")
        let weak = String((e.bodySnippet ?? "").prefix(300))
        guard let kind = Style.kind(in: strong) ?? Style.kind(in: weak) else { return nil }
        let issuer = kind.keepIssuer ? Style.issuer(host: e.sourceHost) : nil
        return Style.join([kind.word, issuer, Style.qualifier(kind.qualifier, e.date)].compactMap { $0 })
    }

    /// Qualifier for model-named files: academic sources get a term, others nothing (keep it short).
    func qualifierFor(_ e: Evidence) -> String? {
        guard let host = e.sourceHost, let date = e.date else { return nil }
        let academic = host.contains(".edu") || host.hasSuffix("odtuclass.metu.edu.tr")
        return academic ? Style.term(date) : nil
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
