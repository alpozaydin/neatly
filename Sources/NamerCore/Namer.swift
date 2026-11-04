import Foundation

public struct Namer: Sendable {
    public var useNetwork = true
    public var useModel = true
    /// Wall-clock budget. Past this we give up rather than make the user wait.
    public var budget: Duration = .seconds(3)

    public init() {}

    public static var modelStatus: String { Model.unavailableReason }

    public static let pdfLike: Set<String> = ["pdf"]
    public static let imageLike: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "webp"]

    /// Returns nil when the file already has a good name or we aren't confident.
    public func suggest(for url: URL, force: Bool = false) async -> Suggestion? {
        let clock = ContinuousClock()
        let start = clock.now
        var e = Evidence(url: url)
        guard force || Extract.isJunkName(e.stem) else { return nil }

        func done(_ stem: String?, _ via: String) -> Suggestion? {
            guard let stem, !stem.isEmpty, stem != e.stem.lowercased() else { return nil }
            let c = (clock.now - start).components
            let ms = Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
            return Suggestion(name: stem, via: via, millis: ms, evidence: e)
        }

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

        // 3 + 4. Embedded title, then page 1 only
        if Self.pdfLike.contains(e.ext), let info = Extract.pdf(url) {
            if !Extract.isJunkTitle(info.title, stem: e.stem) { e.metadataTitle = info.title; e.steps.append("meta") }
            e.headline = info.headline
            e.bodySnippet = info.snippet
            if info.hasText { e.steps.append("page1") }
            // 5. Scanned PDF: OCR page 1
            if !info.hasText, e.metadataTitle == nil, let text = Extract.ocr(pdfFirstPage: url) {
                e.bodySnippet = text; e.steps.append("ocr")
            }
        } else if Self.imageLike.contains(e.ext) {
            if let text = Extract.ocr(image: url) { e.bodySnippet = text; e.steps.append("ocr") }
            e.labels = Extract.labels(image: url)
            if !e.labels.isEmpty { e.steps.append("labels") }
        }

        // Known document kinds are decided by rules: fast and predictable.
        if let n = ruleName(e) { return done(n, "rules[\(e.steps.joined(separator: "+"))]") }

        // 6. On-device model, inside the time budget.
        if useModel, clock.now - start < budget {
            let remaining = budget - (clock.now - start)
            let snapshot = e
            if let w = await withTimeout(remaining, { await Model.name(for: snapshot) }) ?? nil {
                return done(Style.join(w + [qualifierFor(e)].compactMap { $0 }), "model[\(e.steps.joined(separator: "+"))]")
            }
        }

        // Fallback: a clean title is still better than a junk name.
        if let t = e.metadataTitle ?? e.headline {
            return done(Style.join(Array(Style.words(t).prefix(3)) + [qualifierFor(e)].compactMap { $0 }), "title")
        }
        return nil
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
