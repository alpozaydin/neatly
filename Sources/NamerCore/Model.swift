import Foundation
import FoundationModels

/// Stage 6 — Apple's on-device model. Only used when the cheap stages can't decide,
/// and it only ever sees ~1k characters of evidence, never the whole file.
enum Model {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "available"
        case .unavailable(let r): return "\(r)"
        }
    }

    static let instructions = """
    You name files. Produce the shortest name that lets the owner recognise the file later.
    Rules:
    - Say WHAT the document is, and WHO it is from if that is a company or institution.
    - The most distinctive word first. Always write the name in English, even if the content is not.
    - Drop generic words: document, file, image, photo, picture, student, official, final, copy.
    - Never include personal names of the owner, ids, order numbers, dates, or file types.
    Examples:
    - title "Student Transcript" -> transcript
    - "UniDepth: Universal Monocular Metric Depth Estimation" -> unidepth
    - "CENG 232 Logic Design Lab 2 Preliminary Work" -> lab2 ceng232
    - letter from Lufthansa Kundenservice about a lost suitcase -> lufthansa baggage claim
    - photo labels: whiteboard; text: "Midterm topics: graphs, DP" -> midterm topics
    - photo labels: food, pizza; no text -> pizza
    Answer with 1 to 3 lowercase words separated by spaces and nothing else.
    """

    /// Words the model must never hand back: they describe the container, not the content.
    static let banned: Set<String> = ["img", "image", "images", "photo", "picture", "pic", "heic", "jpg", "jpeg",
                                       "png", "svg", "pdf", "gif", "webp", "file", "document", "tbn", "download",
                                       "unknown", "untitled", "name", "none", "scan"]

    static func name(for e: Evidence) async -> [String]? {
        guard isAvailable else { return nil }
        var prompt = ""
        if !Extract.isJunkName(e.stem) { prompt += "Current filename: \(e.stem)\n" }
        if let s = e.sourceDescription { prompt += "Downloaded from: \(s)\n" }
        if let t = e.metadataTitle { prompt += "Embedded title: \(t)\n" }
        if let h = e.headline { prompt += "Largest heading: \(h)\n" }
        if !e.labels.isEmpty { prompt += "Photo labels: \(e.labels.joined(separator: ", "))\n" }
        if let b = e.bodySnippet { prompt += "Beginning of content:\n\(b.prefix(800))\n" }
        // Nothing to go on: a guess would be worse than leaving the name alone.
        guard e.metadataTitle != nil || e.headline != nil || !e.labels.isEmpty || e.bodySnippet != nil else { return nil }
        prompt += "Name:"

        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0)
        guard let out = try? await session.respond(to: prompt, options: options) else { return nil }
        // First line only; models sometimes add an explanation after it.
        let line = out.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let stemWords = Set(Style.words(e.stem))
        let w = Style.words(line).filter { !banned.contains($0) && !stemWords.contains($0) && $0 != e.ext }
        return w.isEmpty ? nil : Array(w.prefix(3))
    }
}
