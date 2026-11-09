import Foundation
import NaturalLanguage

/// Meaning-based similarity with Apple's on-device BERT-style embedding (NLContextualEmbedding), mean-pooled.
/// ~7 ms per text, nothing leaves the Mac. The margins between related and unrelated texts are small
/// (cosine ~0.87 vs ~0.80), so this is only used to *rank* — closest past names, closest folders —
/// never to decide anything alone.
public final class Embedder: @unchecked Sendable {
    public static let shared = Embedder()
    private let lock = NSLock()
    private var model: NLContextualEmbedding?
    private var tried = false
    private var cache: [String: [Float]] = [:]

    /// Load the model now (first use takes a moment), e.g. while a download is still running.
    public func warm() { _ = vector("warm up") }

    public func vector(_ text: String) -> [Float]? {
        let t = String(text.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let v = cache[t] { return v }
        if !tried {
            tried = true
            if let m = NLContextualEmbedding(language: .english), m.hasAvailableAssets, (try? m.load()) != nil { model = m }
        }
        guard let m = model, let r = try? m.embeddingResult(for: t, language: .english) else { return nil }
        var sum = [Float](repeating: 0, count: m.dimension)
        var n: Float = 0
        r.enumerateTokenVectors(in: t.startIndex..<t.endIndex) { v, _ in
            for i in 0..<min(v.count, sum.count) { sum[i] += Float(v[i]) }
            n += 1
            return true
        }
        guard n > 0 else { return nil }
        let v = sum.map { $0 / n }
        if cache.count > 5000 { cache.removeAll() }
        cache[t] = v
        return v
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var d: Float = 0, x: Float = 0, y: Float = 0
        for i in 0..<min(a.count, b.count) { d += a[i] * b[i]; x += a[i] * a[i]; y += b[i] * b[i] }
        return x > 0 && y > 0 ? d / (x.squareRoot() * y.squareRoot()) : 0
    }

    /// `items` ranked by similarity to `query`, best first.
    /// With many items, the shared mean direction is removed first: mean-pooled BERT vectors all point roughly
    /// the same way, and subtracting the mean spreads them apart (a standard fix for "anisotropy").
    public func rank(_ query: String, _ items: [String]) -> [(index: Int, score: Float)] {
        guard var q = vector(query) else { return [] }
        var vs = items.map { vector($0) }
        let present = vs.compactMap { $0 }
        if present.count >= 10 {
            var mean = [Float](repeating: 0, count: q.count)
            for v in present { for i in mean.indices { mean[i] += v[i] / Float(present.count) } }
            q = zip(q, mean).map { $0 - $1 }
            vs = vs.map { $0.map { zip($0, mean).map { $0 - $1 } } }
        }
        return vs.enumerated().compactMap { i, v in v.map { (i, Self.cosine(q, $0)) } }
            .sorted { $0.score > $1.score }
    }
}

/// What a file is about, in one short line of text for the embedder.
public func gist(_ e: Evidence) -> String {
    var parts = [e.metadataTitle, e.headline].compactMap { $0 }
    if !e.labels.isEmpty { parts.append(e.labels.joined(separator: " ")) }
    if let b = e.bodySnippet { parts.append(String(Model.withoutLetterhead(b).prefix(250))) }
    if parts.isEmpty, Decision.junkReason(e.stem) == nil { parts.append(e.stem) }
    if let s = e.sourceDescription { parts.append("from \(s)") }
    return parts.joined(separator: ". ").replacingOccurrences(of: "\n", with: " ")
}

/// Few-shot learning from your own corrections: the names you saved for the most similar past files
/// go into the model's prompt as examples. No training — after a few dozen saves the model names
/// files the way you do. Only answers you gave count (not auto-saves, not "Leave as is").
public enum Examples {
    public struct Example: Sendable { public let about: String; public let name: String }

    /// Below this, a past file isn't similar enough to teach anything (and a bad example misleads a small model).
    static let minSimilarity: Float = 0.86

    public static func similar(to e: Evidence, k: Int = 3, history: [Correction] = Correction.all()) -> [Example] {
        var seen = Set<String>()
        let pool = history.reversed().filter { c in
            !c.chosen.isEmpty && c.auto != true && c.via != "kept" && seen.insert(c.chosen).inserted
        }.prefix(300)
        guard !pool.isEmpty else { return [] }
        let abouts = pool.map(\.about)
        let query = gist(e)
        guard !query.isEmpty else { return [] }
        // Raw cosine for the threshold (centering changes the scale), ranked the same way.
        guard let q = Embedder.shared.vector(query) else { return [] }
        return abouts.enumerated().compactMap { i, a -> (Int, Float)? in
            guard let v = Embedder.shared.vector(a) else { return nil }
            let s = Embedder.cosine(q, v)
            return s >= minSimilarity ? (i, s) : nil
        }
        .sorted { $0.1 > $1.1 }.prefix(k)
        .map { Example(about: abouts[$0.0], name: Array(pool)[$0.0].chosen) }
    }
}
