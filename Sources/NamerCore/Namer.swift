import Foundation
import ImageIO
import NaturalLanguage

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
    /// Experimental: ask the model to double-check names made by rules. Measured in neatly-eval --verify.
    public var verifyRules = false
    /// Wall-clock budgets. Past these we give up rather than make the user wait.
    /// Images get more: looking at a picture is the expensive, high-value step.
    public var documentBudget: Duration = .seconds(3)
    public var imageBudget: Duration = .seconds(8)
    /// Few-shot learning: show the model names you chose for similar files. nil = read corrections.jsonl.
    public var learnFromCorrections = true
    public var history: [Correction]? = nil
    /// "↻ another name": names already shown and rejected. Skips the rules (they'd give the same answer)
    /// and asks the model for something different.
    public var avoid: [String] = []

    public init() {}

    /// `suggest`, but never longer than `limit` — a stuck step (a busy system service) can't stall the queue.
    public func suggest(for url: URL, explicit: Bool = false, app: String? = nil, within limit: Duration) async -> Outcome {
        let me = self
        return await withTimeout(limit) { await me.suggest(for: url, explicit: explicit, app: app) }
            ?? .unsure(why: "took too long")
    }

    /// Load the model and the embedder ahead of time (e.g. while a download is still running): the first call is the slow one.
    public static func prewarm() {
        Model.prewarm()
        Embedder.shared.warm()
    }

    public static var modelStatus: String { Model.status }
    /// Wait until the on-device model answers (at most `limit`), e.g. before naming a batch.
    /// Every first-use cost happens here, not on your files: on a fresh install the text reader (OCR), the photo
    /// classifier, the embedding model and the language model each set themselves up (measured: >20 s together).
    public static func warmUp(limit: Duration = .seconds(90)) async {
        _ = await withTimeout(limit) {
            Embedder.shared.warm()
            if let img = Self.testImage() {
                Extract.warmOCR(img)
                _ = Extract.labels(image: img)
                try? FileManager.default.removeItem(at: img)
            }
            await Model.warmUp()
        }
    }

    /// A small picture with a few words on it, to wake the text reader and the classifier.
    static func testImage() -> URL? {
        let w = 1600, h = 1000
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for i in 0..<5 { ctx.fill(CGRect(x: 20, y: 30 + i * 30, width: 200 + i * 20, height: 14)) }   // text-like bars
        guard let img = ctx.makeImage() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "neatly-warmup-\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    /// Is Apple Intelligence on and its on-device model ready? (Off: names come from text only, simpler.)
    public static var modelAvailable: Bool { Model.isAvailable }

    public static let pdfLike: Set<String> = ["pdf"]
    public static let imageLike: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp"]
    /// Read as text by macOS's document reader.
    public static let textLike: Set<String> = ["doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive", "txt", "md", "markdown"]

    /// `explicit`: the user pointed at this file (Finder hotkey, CLI --force), so skip the
    /// "name already meaningful" check — but never override a name they chose themselves.
    /// `app`: the app a screenshot was taken in, if known (added only when the style asks for it).
    public func suggest(for url: URL, explicit: Bool = false, app: String? = nil) async -> Outcome {
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
            // "↻ another name": never hand back one that was already rejected.
            if avoid.contains(where: { Style.join(Style.tokens($0)) == Style.join(Style.tokens(stem)) }) {
                return .unsure(why: "no different name found")
            }
            let c = (clock.now - start).components
            let ms = Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
            return .suggested(Suggestion(name: profile.render(stem, date: e.date, app: app), via: via, millis: ms, evidence: e))
        }
        var trail: String { e.steps.joined(separator: "+") }
        let debugTimes = ProcessInfo.processInfo.environment["NEATLY_DEBUG"] != nil
        func mark(_ what: String) {
            guard debugTimes else { return }
            let c = (clock.now - start).components
            FileHandle.standardError.write(Data("  [\(Int(Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15)) ms] \(what)\n".utf8))
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
            let extra = profile.len == .short ? 0 : profile.len == .standard ? 1 : 3
            return done(Style.paperName(title: paper.title, year: paper.year, topicWords: extra), "arxiv")
        }

        var isImage = Self.imageLike.contains(e.ext)
        var preview: URL?                   // a Quick Look rendering we made; deleted when we're done
        defer { if let preview { try? FileManager.default.removeItem(at: preview) } }
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
            if avoid.isEmpty, e.metadataTitle != nil, let n = ruleName(e) { return done(n, "rules[\(trail)]") }
            // 4. Page 1 only
            e.headline = info.headline
            e.bodySnippet = info.snippet
            if info.hasText { e.steps.append("page1") }
            // 5. Scanned PDF: OCR page 1
            if !info.hasText, e.metadataTitle == nil, let text = Extract.ocr(pdfFirstPage: url) {
                e.bodySnippet = text; e.steps.append("ocr")
            }
        } else if Self.textLike.contains(e.ext), let info = Extract.textDocument(url) {
            // A text file with almost nothing in it ("a", "12345"): any name would be a guess.
            let letters = ((info.headline ?? "") + (info.snippet ?? "")).filter(\.isLetter).count
            if letters >= 12 {
                e.headline = info.headline
                e.bodySnippet = info.snippet
                e.steps.append("text")
            }
        } else if !isImage, !["zip", "dmg", "pkg", "app", "iso", "exe"].contains(e.ext),
                  let rendered = await withTimeout(.seconds(4), { await Extract.quickLook(url) }) ?? nil {
            preview = rendered; isImage = true; e.steps.append("preview")
        }
        if isImage {
            let imageFile = preview ?? url
            e.imageURL = imageFile
            // 5. Cheap image signals first: text in the image, and Apple's label classifier.
            mark("image: start")
            // Under the time budget too: if the system's text reader is busy, don't wait forever.
            let read = await withTimeout(imageBudget) { Extract.ocrWithHeadline(image: imageFile) }
            let (text, headline) = read ?? (nil, nil)
            mark("image: ocr done")
            if let text { e.bodySnippet = text; e.steps.append("ocr") }
            e.headline = headline
            e.labels = await withTimeout(.seconds(3)) { Extract.labels(image: imageFile) } ?? []
            // A photo from a phone knows where it was taken. Asking Apple's map service sends its coordinates,
            // so only with online lookups on. A screenshot's location is where you were, not what it shows: skipped.
            if useNetwork, !e.isScreenshot, preview == nil, let c = Places.coordinate(url),
               let p = await withTimeout(.seconds(3), { await Places.place(at: c) }) ?? nil {
                e.place = p.description.isEmpty ? nil : p.description
                e.placeName = p.best
                if e.place != nil { e.steps.append("place") }
            }
            mark("image: labels done")
            if !e.labels.isEmpty { e.steps.append("labels") }
        }

        // Known document kinds are decided by rules: fast and predictable.
        // A home listing (a screenshot or a saved page): what, how big, and where — the street tells two apart.
        // Only for pictures of a page (screenshots, saved images): a rental contract PDF mentions bedrooms and rent too.
        if avoid.isEmpty, isImage, let n = listingName(e) { return done(n, "rules[listing]") }

        // Screenshots: the model looking at the screen beats the document rules ("ticket-nov26" for a boarding pass),
        // except for course files, where the rules' course codes are what people want. Rules stay the fallback.
        let screenFirst = isImage && e.isScreenshot && useModel && Model.canSeeImages && courseCode(e) == nil
        if avoid.isEmpty, !screenFirst, let n = ruleName(e) {
            if verifyRules, useModel, await Model.rejects(name: n, for: e) {
                e.steps.append("rule-rejected:\(n)")
            } else {
                return done(n, "rules[\(trail)]")
            }
        }

        // 6. On-device model. For images it looks at the picture itself (when the OS supports it).
        let budget = isImage ? imageBudget : documentBudget
        // The model always gets its own few seconds: on a busy Mac reading the text can eat the whole budget (8 s
        // measured under load), and skipping the model then left screenshots with no name at all.
        // The caller's overall limit (20 s in the app) still applies.
        if useModel {
            let remaining = max(budget - (clock.now - start), isImage ? .seconds(6) : .seconds(2))
            let snapshot = e
            let look = isImage && Model.canSeeImages
            if look { e.steps.append("vision") }
            mark("model: start")
            let examples = learnFromCorrections ? Examples.similar(to: snapshot, history: history ?? Correction.all()) : []
            mark("model: examples done")
            if !examples.isEmpty { e.steps.append("\(examples.count) of your names") }
            mark("model: calling")
            // Screenshots and photos get a little more room than documents: "two cats on red chairs in istanbul".
            let wide = isImage && (e.isScreenshot || (e.bodySnippet?.count ?? 0) < 40)
            var words = wide ? profile.len.screenshotWords : profile.len.modelWords
            // Photos: a short phrase for what it shows (≤ 4 words on Short), plus room for the place.
            if wide, !e.isScreenshot {
                let extra = Style.words(e.placeName ?? "").count
                words = words.lowerBound...(min(words.upperBound, 4) + extra)
            }
            let answer = await withTimeout(remaining, { [words, avoid] in
                await Model.name(for: snapshot, lookAtImage: look, examples: examples, words: words, avoid: avoid) }) ?? nil
            mark("model: answered")
            if let w = answer {
                let placeWords = Style.words(e.placeName ?? "").count
                let (mw, ml) = wide ? (e.isScreenshot ? profile.len.screenshotMaxWords : min(profile.len.screenshotMaxWords, 4) + placeWords,
                                       profile.len.maxLength + 30)
                                                         : (profile.len.maxWords, profile.len.maxLength)
                // The model picked part of the page's own title ("cornbread" from "Hot Honey Cornbread"):
                // the whole title is more specific, if it fits.
                var w = w
                // Only a clean title: OCR of an emoji or an icon leaves bits like "lj" ("Your order is on its way! 🛵").
                if avoid.isEmpty, let h = e.headline,
                   Style.words(h).allSatisfy({ $0.count >= 3 || $0.allSatisfy(\.isNumber) || ["tv", "uk", "us", "eu", "ai", "pr", "ui", "3d", "4k"].contains($0) }) {
                    // A title used as the name reads as a title, not a sentence: "booking confirmed", not "your booking is confirmed".
                    let glue: Set<String> = ["your", "my", "our", "is", "are", "was", "were", "has", "have", "been", "be", "this", "that", "it", "its"]
                    let hw = Style.words(h).filter { !glue.contains($0) }
                    if !hw.isEmpty, hw.count <= min(mw, 5), w.count == 1, Set(w).isSubset(of: Set(hw)), hw.count > 1 { w = hw }
                    // …or cut it short ("hot honey skillet" from "Hot Honey Skillet Cornbread"): the title's own words, in its order.
                    else if e.isScreenshot, w.count >= 2, hw.count <= min(mw, 5), hw.count > w.count, Array(hw.prefix(w.count)) == w { w = hw }
                    // …or kept only the generic half of a short title ("algorithm notes" for "Dijkstra's Algorithm"):
                    // the title, in its own order, plus the kind word the model added.
                    else if e.isScreenshot, (2...4).contains(hw.count), Self.readable(h), !Set(w).isDisjoint(with: hw) {
                        let missing = hw.filter { !w.contains($0) && $0.count >= 3 && !Model.kindWords.contains($0) }
                        let extra = w.filter { !hw.contains($0) && Model.kindWords.contains($0) }
                        if !missing.isEmpty, hw.count + extra.count <= mw { w = hw + extra }
                    }
                }
                // A photo with a known place says where: "two cats on red chairs in istanbul".
                // Already says where (the model used the landmark, district or city): leave it.
                if let place = e.placeName {
                    let pw = Style.words(place), known = Set(Style.words(e.place ?? "")).union(pw)
                    if !pw.isEmpty, known.isDisjoint(with: Set(w)) { w = w + ["in"] + pw }
                }
                if let course = courseCode(e) {
                    // "cs 491 meeting" → cs491-meeting, not cs491-cs-491-meeting
                    var rest: [String] = []
                    for x in w where x != course {
                        if let last = rest.last, last + x == course { rest.removeLast(); continue }
                        rest.append(x)
                    }
                    return done(Style.join([course] + rest, maxWords: mw, maxLength: ml), "model[\(trail)]")
                }
                if wide {
                    let end = Style.words(e.placeName ?? "")
                    return done(Self.phrase(w, maxWords: mw, maxLength: ml, keepEnd: w.suffix(end.count).elementsEqual(end) ? end : []), "model[\(trail)]")
                }
                return done(Style.join(w + [qualifierFor(e)].compactMap { $0 }, maxWords: mw, maxLength: ml), "model[\(trail)]")
            }
        }

        if avoid.isEmpty, screenFirst, let n = ruleName(e) { return done(n, "rules[\(trail)]") }

        // Fallback: a clean title is still better than a junk name.
        // Only if it reads like words: OCR of an old scan gives "ennra ficenim poffumuf", worse than the junk name.
        // A picture with a line or two of text ("ME ON MONDAY BEFORE COFFEE") has no "biggest" line: use its first one.
        let firstLine = isImage ? e.bodySnippet?.split(whereSeparator: \.isNewline).map(String.init)
            .first { Style.words($0).count >= 2 } : nil
        if let t = e.metadataTitle ?? e.headline ?? firstLine, Self.readable(t) {
            return done(Style.join(Array(Style.words(t).prefix(3)) + [qualifierFor(e)].compactMap { $0 }), "title")
        }
        return .unsure(why: "not enough evidence")
    }

    /// A short phrase as a name: joining words may repeat ("cats on chairs in istanbul"), a cut never leaves one
    /// dangling at the end ("…-with-black-tips-on"), and the place at the end is never cut in half.
    static func phrase(_ w: [String], maxWords: Int, maxLength: Int, keepEnd: [String]) -> String {
        let joins: Set<String> = ["in", "on", "at", "with", "from", "to", "for", "of", "and", "near", "by"]
        var words: [String] = []
        for x in w where words.last != x { words.append(x) }               // no "the-the"
        let tail = !keepEnd.isEmpty && words.suffix(keepEnd.count).elementsEqual(keepEnd) ? Array(words.suffix(keepEnd.count + 1)) : []
        var head = Array(words.dropLast(tail.count))
        func fits(_ a: [String]) -> Bool { a.filter { !joins.contains($0) }.count <= maxWords && a.joined(separator: "-").count <= maxLength }
        // Too long: drop the last whole "with …" / "on …" part first ("vintage red car with red balloons" →
        // "vintage red car"), and only then single words.
        while !head.isEmpty, !fits(head + tail) {
            if let j = head.lastIndex(where: { joins.contains($0) }), j > 0 { head = Array(head[..<j]) } else { head.removeLast() }
        }
        while let l = head.last, joins.contains(l) { head.removeLast() }
        var out = head.isEmpty ? Array(tail.drop { joins.contains($0) }) : head + tail
        while let l = out.last, joins.contains(l) { out.removeLast() }
        return out.joined(separator: "-")
    }

    /// Most words are real (English or Turkish/German/… via the language's word list), not OCR noise.
    static func readable(_ text: String) -> Bool {
        let w = Style.words(text).filter { $0.count >= 3 && !$0.contains(where: \.isNumber) }
        guard !w.isEmpty else { return false }
        let lang = NLLanguageRecognizer.dominantLanguage(for: text) ?? .english
        let vocab = NLEmbedding.wordEmbedding(for: lang) ?? NLEmbedding.wordEmbedding(for: .english)
        guard let vocab else { return true }
        return Double(w.filter { vocab.contains($0) }.count) / Double(w.count) >= 0.6
    }

    /// Rules: known document kinds and course files are named directly — fast and predictable.
    func ruleName(_ e: Evidence) -> String? {
        let strong = [e.metadataTitle, e.headline].compactMap { $0 }.joined(separator: " ")
        let weak = String((e.bodySnippet ?? "").prefix(400))
        // Look at heading + start of text together; the kind list is ordered specific → generic,
        // so "DEKONT … Öğrenim Ücreti" is tuition, not just a receipt.
        let kind = Style.kind(in: strong + " " + String(weak.prefix(300))) ?? Style.kind(in: weak)

        // Course files: course code first, then what it is. cs213-hw2, cs499-lecture5, cs334-syllabus.
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
                // Exams are often old papers: name them by the term written on them. cs331-final-fall22
                let isExam = ["midterm", "final", "quiz"].contains { item.hasPrefix($0) }
                let term = isExam ? Style.termIn(strong + "\n" + String(full.prefix(500))) : nil
                // "midterm KEY" / "Quiz 2 Solutions" / "HW1 Solutions" → …-solutions.
                // Title, heading, filename and the page header only: exam questions can say "key" too.
                let gradable = isExam || ["hw", "rec", "lab"].contains { item.hasPrefix($0) }
                let top = full.split(whereSeparator: \.isNewline).prefix(3).joined(separator: " ")   // the page header
                let sol = gradable && Style.isSolutions([e.metadataTitle, e.headline, e.stem, top].compactMap { $0 }.joined(separator: " "))
                // Lectures and chapters: the number alone says little. cs334-ch5-cpu-scheduling
                let topic = ["lecture", "ch", "week"].contains { item.hasPrefix($0) } ? itemTopic(e) : []
                return Style.join([course, item] + topic + [term, sol ? "solutions" : nil].compactMap { $0 })
            }
        }

        // No course code, but clearly coursework: "Homework 2: CNN on CIFAR-10" → hw2-cnn-cifar10.
        if kind == nil, let item = Style.academicItem(in: strong), item != "syllabus", item.contains(where: \.isNumber) {
            return Style.join([item] + itemTopic(e))
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

        // A photo or screenshot of a till receipt never says "receipt": it says TOTAL under a list of prices.
        if kind == nil, let body = e.bodySnippet {
            let lines = body.split(whereSeparator: \.isNewline).map { Style.tokens(String($0)).joined(separator: " ") }
            let priced = body.split(whereSeparator: \.isNewline).filter { $0.range(of: #"\d+[.,]\d{2}\s*$"#, options: .regularExpression) != nil }
            if priced.count >= 2, lines.contains(where: { $0.hasPrefix("total") || $0.hasPrefix("toplam") || $0.hasPrefix("summe") || $0.hasPrefix("grand total") }) {
                let shop = (e.headline ?? body.split(whereSeparator: \.isNewline).first.map(String.init)).map { Array(Style.words($0).prefix(3)) } ?? []
                return Style.join(["receipt"] + shop.filter { !$0.allSatisfy(\.isNumber) })
            }
        }

        guard let kind else { return nil }
        if kind.word == "cv" { return cvName(e) }
        // A webmail host says nothing about who wrote the document: prefer the text then.
        let fromHost = Style.issuer(host: e.sourceHost).flatMap { ["gmail", "outlook", "webmail", "mail"].contains($0) ? nil : $0 }
        let issuer = kind.keepIssuer
            ? (kind.word == "acceptance" ? nil : fromHost) ?? Style.issuer(inText: strong + "\n" + weak, kind: kind.word)
            : nil
        if kind.issuerFirst { return issuer.map { Style.join([$0, kind.word]) } ?? kind.word }
        // Bills and payslips: the month they are FOR, not the day they arrived.
        let date = kind.qualifier == .month ? (Style.period(in: strong + " " + weak) ?? e.date) : e.date
        // Names with spaces read naturally, who first: "Turkcell Invoice Nov 2026". Dashes keep the kind first,
        // which sorts the same kind together: invoice-turkcell-nov26.
        let natural = profile.separator == " "
        let parts: [String?] = (natural ? [issuer, kind.word] : [kind.word, issuer]) + [Style.qualifier(kind.qualifier, date)]
        return Style.join(parts.compactMap { $0 })
    }

    /// "2 bd · 1 ba · $3,100/mo · 42 Linden Ave" → apartment-3-bed-linden-st. Needs a size AND a rent or price
    /// on the same screen, so a recipe that "serves 2" or an article about bedrooms isn't taken for one.
    func listingName(_ e: Evidence) -> String? {
        let text = [e.headline, e.bodySnippet].compactMap { $0 }.joined(separator: "\n")
        guard text.count < 1500,
              let beds = text.firstMatch(of: /(?i)\b(\d{1,2}|studio)\s*(?:-\s*)?(?:bd|bds|bed|beds|bedrooms?|br)\b/)
                  ?? text.firstMatch(of: /(?i)\b(studio)\b/),
              text.range(of: #"(?i)(/\s?mo\b|per month|/month|\bsq\s?ft\b|\bsqft\b|m²|\bfor rent\b|\bfor sale\b|\bba\b|\bbath)"#,
                         options: .regularExpression) != nil
        else { return nil }
        let n = String(beds.1).lowercased()
        let kind = text.range(of: #"(?i)\b(house|townhouse|villa)\b"#, options: .regularExpression).map { String(text[$0]).lowercased() } ?? "apartment"
        let size = n == "studio" ? ["studio"] : [n, "bed"]
        var street: [String] = []
        if let m = text.firstMatch(of: /\b\d{1,5}\s+((?:[A-Z0-9][a-z0-9]+\s){1,2}(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Dr|Drive|Lane|Ln|Way|Pl|Sokak|Sok|Cadde|Caddesi|Cd))\b/) {
            street = Style.words(String(m.1))
        }
        return Style.join([kind] + size + street)
    }

    /// The topic of a numbered course item, from the title line that names it: "Lecture 7: Procedures" → [procedures].
    func itemTopic(_ e: Evidence) -> [String] {
        let lines = [e.metadataTitle, e.headline].compactMap { $0 }
            + (e.bodySnippet ?? "").split(whereSeparator: \.isNewline).prefix(6).map(String.init)
        guard let line = lines.first(where: { $0.contains(":") && Style.academicItem(in: $0) != nil }) else { return [] }
        return Style.topic(after: line)
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
        let lms = ["moodle", "canvas", "blackboard", "classroom.google", "edu"]
        return lms.contains { host.contains($0) }
    }

    /// Qualifier for model-named files: academic sources get a term, others nothing (keep it short).
    func qualifierFor(_ e: Evidence) -> String? {
        guard isAcademic(e), let date = e.date else { return nil }
        return Style.term(date)
    }
}

/// Run `op`, but give up after `d`. Returns as soon as either finishes — unlike a task group, which would
/// wait for the model call to end even after cancelling it (model calls don't stop when cancelled).
func withTimeout<T: Sendable>(_ d: Duration, _ op: @escaping @Sendable () async -> T) async -> T? {
    let once = Once()
    return await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
        // Detached: never inherit the caller's thread. On the main thread Vision's text reader stalls (measured: 8 s → limit).
        let work = Task.detached { let v = await op(); if once.claim() { c.resume(returning: v) } }
        Task { try? await Task.sleep(for: d); if once.claim() { work.cancel(); c.resume(returning: nil) } }
    }
}

/// First caller wins: whichever of "result" and "deadline" comes first resumes the continuation.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
