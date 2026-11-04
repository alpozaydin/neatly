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

    static let instructions = """
    You name files. Produce the shortest name that lets the owner recognise the file later.
    Rules:
    - Say WHAT the document is, and WHO it is from if that is a company or institution.
    - The most distinctive word first. Always write the name in English, even if the content is not.
    - Name the TOPIC, never the form. Never answer "handwriting", "notes", "text", "screenshot" alone.
    - Drop generic words: document, file, image, photo, picture, student, official, final, copy.
    - Never include personal names of the owner, ids, order numbers, dates, or file types.
    Examples:
    - title "Student Transcript" -> transcript
    - "UniDepth: Universal Monocular Metric Depth Estimation" -> unidepth
    - "CENG 232 Logic Design Lab 2 Preliminary Work" -> lab2 ceng232
    - letter from Lufthansa Kundenservice about a lost suitcase -> lufthansa baggage claim
    - photo labels: whiteboard; text: "Midterm topics: graphs, DP" -> midterm topics
    - photo labels: food, pizza; no text -> pizza
    - handwritten notes: "integration by parts, u = x, dv = e^x dx" -> integration by parts
    - whiteboard: "sprint 4 retro: what went well / blockers" -> sprint4 retro
    Answer with 1 to 3 lowercase words separated by spaces and nothing else.
    """

    /// Words the model must never hand back: they describe the container, not the content.
    static let banned: Set<String> = ["img", "image", "images", "photo", "picture", "pic", "heic", "jpg", "jpeg",
                                       "png", "svg", "pdf", "gif", "webp", "file", "document", "tbn", "download",
                                       "unknown", "untitled", "name", "none", "scan", "handwriting", "handwritten",
                                       "writing", "text", "screenshot"]

    static func name(for e: Evidence, lookAtImage: Bool = false) async -> [String]? {
        guard isAvailable else { return nil }
        var prompt = ""
        if Decision.junkReason(e.stem) == nil { prompt += "Current filename: \(e.stem)\n" }
        if let s = e.sourceDescription { prompt += "Downloaded from: \(s)\n" }
        if let h = e.linkHint { prompt += "The download link mentions: \(h)\n" }
        if let t = e.metadataTitle { prompt += "Embedded title: \(t)\n" }
        if let h = e.headline { prompt += "Largest heading: \(h)\n" }
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
        prompt += "Name:"

        // Foreign text: summarize in English first, then name from the summary (two small steps beat one big one).
        var summary: String?
        if let lang, !lookAtImage {
            let s = LanguageModelSession(instructions: """
            Read a document written in \(lang). In one short English sentence, say what kind of document it is,
            who sent it, and what it is about. Ignore addresses, phone numbers and department names.
            """)
            summary = try? await s.respond(to: prompt, options: GenerationOptions(temperature: 0)).content
            if let summary { prompt = "Summary: \(summary)\n" + (e.sourceDescription.map { "Downloaded from: \($0)\n" } ?? "") + "Name:" }
        }

        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0)
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
        if ProcessInfo.processInfo.environment["NAMER_DEBUG"] != nil {
            FileHandle.standardError.write(Data("--- prompt\n\(prompt)\n--- answer\n\(text)\n---\n".utf8))
        }
        // First line only; models sometimes add an explanation after it.
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var line2 = line
        // Small models often copy words straight from a foreign text. If so, ask once more, just to translate.
        if let lang, summary == nil, copiedForeignWords(line, from: e) {
            line2 = await translate(line, from: lang) ?? line
        }
        let stemWords = Set(Style.words(e.stem))
        let w = Style.words(line2).filter { $0.count >= 2 && !banned.contains($0) && !stemWords.contains($0) && $0 != e.ext }
        return w.isEmpty ? nil : Array(w.prefix(3))
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
}
