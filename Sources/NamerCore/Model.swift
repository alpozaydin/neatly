import Foundation
import FoundationModels
import ImageIO
import NaturalLanguage

/// Stage 6 — Apple's on-device model. Only used when the cheap stages can't decide,
/// and it only ever sees ~1k characters of evidence, never the whole file.
enum Model {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// macOS 27+: the on-device model can look at an image directly.
    static var canSeeImages: Bool {
        guard isAvailable else { return false }
        if #available(macOS 27.0, *) { return SystemLanguageModel.default.capabilities.contains(.vision) }
        return false
    }

    static var status: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "Apple on-device model" + (canSeeImages ? " (text + vision)" : " (text only)")
        case .unavailable(let r): return "unavailable (\(r))"
        }
    }

    static func instructions(words: ClosedRange<Int>) -> String {
        let base = baseInstructions.replacingOccurrences(of: "Answer with 1 to 3 lowercase words", with: "Answer with \(words.lowerBound) to \(words.upperBound) lowercase words")
        return words.upperBound > 3
            ? base + "\nUse the extra words for specifics that tell this file apart: names, places, numbers, versions."
            : base
    }

    static let baseInstructions = """
    You name files. Produce the shortest name that lets the owner recognise the file later.
    Rules:
    - Say WHAT the document is, and WHO it is from if that is a company or institution.
    - The most distinctive word first. Always write the name in English, even if the content is not.
    - Name the TOPIC, never the form. Never answer "handwriting", "notes", "text", "screenshot" alone.
    - Drop generic words: document, file, image, photo, picture, student, official, final, copy.
    - Never include personal names of the owner, ids, order numbers, dates, or file types.
    - Keep names of places, products, apps and companies: they are usually the most distinctive words.
    Examples:
    - title "Student Transcript" -> transcript
    - "UniDepth: Universal Monocular Metric Depth Estimation" -> unidepth
    - "CENG 232 Logic Design Lab 2 Preliminary Work" -> lab2 ceng232
    - letter from Lufthansa Kundenservice about a lost suitcase -> lufthansa baggage claim
    - photo labels: whiteboard; text: "Midterm topics: graphs, DP" -> midterm topics
    - photo labels: food, pizza; no text -> pizza
    - handwritten notes: "integration by parts, u = x, dv = e^x dx" -> integration by parts
    - whiteboard: "sprint 4 retro: what went well / blockers" -> sprint4 retro
    Screenshots of web pages and apps: say WHAT it is and WHOSE (product, site, app), not a slogan, price or menu item:
    - GitLab page of the linux-kernel repository -> linux kernel gitlab
    - Zara product page "Linen Blend Shirt", 39.95 -> linen shirt zara
    - Samsung marketing page "Epic, just like that." for Galaxy S24 -> galaxy s24
    - Rust book chapter "5. Using Structs" -> rust structs
    Answer with 1 to 3 lowercase words separated by spaces and nothing else.
    """

    /// Words the model must never hand back: they describe the container, not the content.
    static let banned: Set<String> = ["img", "image", "images", "photo", "picture", "pic", "heic", "jpg", "jpeg",
                                       "png", "svg", "pdf", "gif", "webp", "file", "document", "tbn", "download",
                                       "unknown", "untitled", "name", "none", "scan", "handwriting", "handwritten",
                                       "writing", "text", "screenshot"]

    /// Load the model into memory now, so the first real request doesn't pay for it.
    static func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(instructions: instructions(words: 1...3)).prewarm()
    }

    static func name(for e: Evidence, lookAtImage: Bool = false, examples: [Examples.Example] = [],
                     words: ClosedRange<Int> = 1...3, avoid: [String] = []) async -> [String]? {
        guard isAvailable else { return nil }
        var shots = ""
        if !examples.isEmpty {
            // Retrieved from this person's own past saves (see Similarity.swift): their style beats our defaults.
            shots = "Names this person chose for similar files. Follow their style; reuse a word only if it fits this file:\n"
                + examples.map { "- \($0.about.prefix(150)) -> \($0.name)" }.joined(separator: "\n") + "\n\n"
        }
        var prompt = ""
        if Decision.junkReason(e.stem) == nil { prompt += "Current filename: \(e.stem)\n" }
        if let s = e.sourceDescription { prompt += "Downloaded from: \(s)\n" }
        if let h = e.linkHint { prompt += "The download link mentions: \(h)\n" }
        if let t = e.metadataTitle { prompt += "Embedded title: \(t)\n" }
        if let h = e.headline { prompt += "Biggest text (usually the topic; if it is a slogan, a number or a menu item, name the product or page instead): \(h)\n" }
        if !e.labels.isEmpty { prompt += "Photo labels: \(e.labels.joined(separator: ", "))\n" }
        if let b = e.bodySnippet { prompt += "Beginning of content:\n\(withoutLetterhead(b).prefix(800))\n" }
        let lang = language(of: e)
        if let lang { prompt += "The content is in \(lang). The name must be in English: translate it.\n" }
        // Nothing to go on: a guess would be worse than leaving the name alone.
        guard lookAtImage || e.metadataTitle != nil || e.headline != nil || !e.labels.isEmpty || e.bodySnippet != nil
        else { return nil }
        if lookAtImage {
            prompt += (e.bodySnippet?.count ?? 0) > 80
                ? "The image is attached. Name it by what its text is about.\n"
                : "The image is attached. Name it by what it shows.\n"
        }
        if !avoid.isEmpty {
            prompt += "The owner rejected these names: \(avoid.joined(separator: ", ")). Give a different name that is still specific to this file.\n"
        }
        prompt += "Name:"
        let summaryInput = prompt
        prompt = shots + prompt

        // Foreign text: summarize in English first, then name from the summary (two small steps beat one big one).
        var summary: String?
        if let lang, !lookAtImage {
            let s = LanguageModelSession(instructions: """
            Read a document written in \(lang). In one short English sentence, say what kind of document it is,
            who sent it, and what it is about. Ignore addresses, phone numbers and department names.
            """)
            summary = try? await s.respond(to: summaryInput, options: GenerationOptions(temperature: 0)).content
            if let summary { prompt = shots + "Summary: \(summary)\n" + (e.sourceDescription.map { "Downloaded from: \($0)\n" } ?? "") + "Name:" }
        }

        let session = LanguageModelSession(instructions: instructions(words: words))
        let options = GenerationOptions(temperature: avoid.isEmpty ? 0 : 0.7)   // a retry needs some variety
        let text: String
        if lookAtImage, #available(macOS 27.0, *), let img = thumbnail(e.url) {
            let p = prompt
            guard let out = try? await session.respond(options: options, prompt: {
                p
                Attachment(img)
            }) else { return nil }
            text = out.content
        } else {
            guard let out = try? await session.respond(to: prompt, options: options) else { return nil }
            text = out.content
        }
        if ProcessInfo.processInfo.environment["NEATLY_DEBUG"] != nil {
            FileHandle.standardError.write(Data("--- prompt\n\(prompt)\n--- answer\n\(text)\n---\n".utf8))
        }
        // First line only; models sometimes add an explanation after it.
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var line2 = line
        // Small models often copy words straight from a foreign text. If so, ask once more, just to translate.
        if let lang, summary == nil, copiedForeignWords(line, from: e) {
            line2 = await translate(line, from: lang) ?? line
        }
        // Small models misspell names they copy ("Aselsan" → "aseslan"): use the document's own spelling.
        let source = Set(Style.words([e.metadataTitle, e.headline, e.bodySnippet, e.linkHint].compactMap { $0 }.joined(separator: " ")))
        line2 = Style.words(line2).map { w in
            guard w.count >= 5, !source.contains(w) else { return w }
            return source.first { $0.first == w.first && abs($0.count - w.count) <= 2 && editDistance($0, w) <= 2 } ?? w
        }.joined(separator: " ")
        // Made-up words ("trickaide"): not in the file and not English → drop them.
        if let vocab = NLEmbedding.wordEmbedding(for: .english) {
            line2 = Style.words(line2).filter { source.contains($0) || vocab.contains($0) || $0.contains(where: \.isNumber) }
                .joined(separator: " ")
        }
        let stemWords = Set(Style.words(e.stem))
        let w = Style.words(line2).filter { $0.count >= 2 && !banned.contains($0) && !stemWords.contains($0) && $0 != e.ext }
        return w.isEmpty ? nil : Array(w.prefix(words.upperBound))
    }

    /// Downsampled copy: the model doesn't need 12 megapixels to tell a receipt from a cat.
    static func thumbnail(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF rotation
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ] as CFDictionary)
    }

    /// Language of the content, only when clearly not English. Uses Apple's on-device recognizer (~1 ms).
    static func language(of e: Evidence) -> String? {
        let text = [e.metadataTitle, e.headline, e.bodySnippet].compactMap { $0 }.joined(separator: "\n")
        guard text.count >= 60 else { return nil }
        let r = NLLanguageRecognizer()
        r.processString(String(text.prefix(800)))
        guard let (lang, p) = r.languageHypotheses(withMaximum: 1).first, p > 0.6, lang != .english else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: lang.rawValue)
    }

    /// True if a longer answer word appears verbatim in the (non-English) content.
    static func copiedForeignWords(_ answer: String, from e: Evidence) -> Bool {
        let content = Set(Style.words([e.metadataTitle, e.headline, e.bodySnippet].compactMap { $0 }.joined(separator: " ")))
        return Style.words(answer).contains { $0.count >= 5 && content.contains($0) }
    }

    static func translate(_ words: String, from lang: String) async -> String? {
        let session = LanguageModelSession(instructions: """
        Translate a short file name from \(lang) to English. Keep brand and company names as they are.
        Answer with 1 to 3 lowercase English words and nothing else.
        Examples: "mietvertrag" -> rent contract; "lufthansa gepaeckverlust" -> lufthansa lost baggage
        """)
        return try? await session.respond(to: words, options: GenerationOptions(temperature: 0)).content
    }

    /// Letters start with sender address, phone, web — the least informative lines. Drop them.
    static func withoutLetterhead(_ text: String) -> String {
        let contact = try! Regex(#"(?i)(\b\d{5}\s+\p{Lu}|\btel(efon)?\b|\bfax\b|\bphone\b|www\.|https?://|@\w|\+\d{2}\s?\d)"#)
        var seen = Set<String>()
        let kept = text.split(whereSeparator: \.isNewline).filter { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, seen.insert(l.lowercased()).inserted else { return false }   // drop repeats
            return l.firstMatch(of: contact) == nil
        }
        // Fall back to the original if we removed almost everything.
        return kept.count >= 2 ? kept.joined(separator: "\n") : text
    }

    /// Second opinion on a rule-made name. True only on a clear "no".
    static func rejects(name: String, for e: Evidence) async -> Bool {
        guard isAvailable else { return false }
        var facts = ""
        if let s = e.sourceDescription { facts += "Downloaded from: \(s)\n" }
        if let t = e.metadataTitle { facts += "Embedded title: \(t)\n" }
        if let h = e.headline { facts += "Largest heading: \(h)\n" }
        if let b = e.bodySnippet { facts += "Beginning of content:\n\(withoutLetterhead(b).prefix(600))\n" }
        let session = LanguageModelSession(instructions: """
        You check file names. A good name is short and says what the file is. Words like fall26 or nov26 are dates; \
        ceng213 is a course code; hw2 means homework 2. Answer only "yes" if the name fits the file, or "no" if it is wrong.
        """)
        let out = try? await session.respond(to: facts + "Proposed name: \(name)\nDoes it fit?",
                                             options: GenerationOptions(temperature: 0))
        return out?.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("no") ?? false
    }

    /// Pick one folder from the person's own folders, or nil. The answer must be one of the listed paths.
    static func pickFolder(for e: Evidence, name: String, options: [String]) async -> String? {
        guard isAvailable, !options.isEmpty else { return nil }
        var facts = "File: \(name).\(e.ext)\n"
        if let s = e.sourceDescription { facts += "Downloaded from: \(s)\n" }
        if let t = e.metadataTitle ?? e.headline { facts += "Title: \(t)\n" }
        if let b = e.bodySnippet { facts += "Beginning:\n\(withoutLetterhead(b).prefix(400))\n" }
        let session = LanguageModelSession(instructions: """
        You file documents into folders. Pick the single best folder for the file from the list.
        Answer with the folder path exactly as written in the list, or "none" if no folder clearly fits.
        """)
        let prompt = facts + "\nFolders:\n" + options.map { "- \($0)" }.joined(separator: "\n") + "\n\nBest folder:"
        guard let out = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0)) else { return nil }
        let answer = out.content.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-`\"'")))
        return options.first { $0.caseInsensitiveCompare(answer) == .orderedSame }   // must be a real folder
    }
}

/// Levenshtein distance, for short words.
func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var row = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
        var prev = row[0]; row[0] = i
        for j in 1...max(b.count, 1) where !b.isEmpty {
            let cur = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
            prev = cur
        }
    }
    return a.isEmpty ? b.count : row[b.count]
}
