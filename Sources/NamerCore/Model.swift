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
    - "CS 232 Logic Design Lab 2 Preliminary Work" -> lab2 cs232
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

    /// Screenshots get their own instructions: the name says what kind of thing is on screen and what sets it apart.
    /// The examples are deliberately different from the test screenshots (Tests/screens), so tuning can't just copy them.
    static func screenshotInstructions(words: ClosedRange<Int>) -> String {
        """
        You name screenshots so the owner can find them again later. Look at the screenshot and the text read from it.
        A good name says the specific subject first (the company, place, person's role, product or topic), then what \
        kind of thing it is: chat, note, list, recipe, receipt, order, listing, booking, ticket, boarding pass, \
        appointment, invoice, error, article, email, invite, map, directions, forecast, call, settings, chart, post, \
        quote, menu, tracking, schedule, budget, pull request.
        Always keep the most specific name you can see: the band, brand, company, product, place, or the person \
        being quoted. For an email or message, add who it is from ("interview invite from spotify").
        It may read as a natural phrase: "from", "to", "with", "for" are fine.
        Ignore the menu bar, the dock, desktop icons, window buttons, prices, ids and dates.
        Never use personal names of people. Never say "screenshot", "screen", "image" or the app's name alone.
        Be descriptive: the subject, the kind of thing, and the detail that makes this one different (what \
        happened, the item, the destination, the problem). For a purchase name the item bought, not the shop — \
        except a cafe or restaurant order. Keep words that say what happened: delayed, cancelled, failed, approved.
        Examples:
        - Messages: a landlord saying the music was too loud again -> landlord loud music complaint
        - Notes: "Camping gear: tent, stove, headlamp" -> camping trip gear list
        - Calendar event "Vet appointment" for Luna -> vet checkup appointment
        - Website: "3 bd · 2 ba · garden", $3,100/mo -> house listing 3 bed with garden
        - Website: order #A12 confirmed at Blue Bottle Coffee -> blue bottle coffee order
        - Website: "Thanks for your order" — Kindle Paperwhite 16GB -> kindle paperwhite order
        - A video call with four people, "Family" -> family video call
        - Dialog: "The disk wasn't ejected properly" -> disk not ejected warning
        - Mail: "Your Delta flight to Denver is delayed" -> delta denver flight delayed
        - GitHub: "Fix crash when uploading photos #91" -> photo upload crash fix pull request
        - Wikipedia article "Eiffel Tower" -> eiffel tower wikipedia article
        - Weather in Oslo, snow -> oslo snow weather forecast
        Answer in exactly two lines:
        What it is: <one short sentence>
        Name: <\(words.lowerBound) to \(words.upperBound) lowercase English words, like the examples>
        """
    }

    /// Words that appear only in the examples above. A small model sometimes borrows one ("delta" for a Turkish
    /// Airlines delay): unless it's really on the screen, it goes.
    static let screenshotExampleWords: Set<String> = ["landlord", "loud", "music", "complaint", "camping", "trip", "gear",
        "tent", "stove", "headlamp", "vet", "luna", "checkup", "garden", "blue", "bottle", "a12", "kindle", "paperwhite",
        "16gb", "family", "disk", "ejected", "delta", "denver", "photo", "upload", "crash", "uploading", "eiffel",
        "tower", "oslo", "snow", "spotify"]

    /// Words that only say what KIND of screen it is. A name made of nothing else fits every screenshot of that kind.
    static let kindWords: Set<String> = ["chat", "message", "messages", "text", "reminder", "conversation", "group", "thread",
        "error", "warning", "alert", "dialog", "notification", "settings", "system", "preferences", "ticket", "tickets",
        "weather", "forecast", "listing", "rental", "property", "directions", "route", "map", "call", "video", "meeting",
        "note", "notes", "list", "email", "mail", "inbox", "invite", "invitation", "web", "page", "website", "app",
        "application", "window", "browser", "screen", "screenshot", "post", "tweet", "article", "order", "receipt",
        "confirmation", "booking", "reservation", "details", "info", "information", "summary", "overview", "update",
        "whatsapp", "slack", "safari", "chrome", "finder", "imessage", "facetime", "github", "merge", "request", "pull",
        "a", "an", "the", "of", "with", "and", "for", "new", "my", "your"]
    static let screenshotExampleNames: Set<String> = ["landlord loud music complaint", "camping trip gear list",
        "vet checkup appointment", "house listing 3 bed with garden", "house listing 3 bed garden", "blue bottle coffee order",
        "kindle paperwhite order", "family video call", "disk not ejected warning", "delta denver flight delayed",
        "photo upload crash fix pull request", "eiffel tower wikipedia article", "oslo snow weather forecast",
        "interview invite from spotify", "interview invite spotify"]
    static let refineExampleTopics: Set<String> = ["cat sitting", "oslo", "login crash fix", "parcel delivery", "studio apartment", "heathrow airport"]

    /// The address bar says which site it is, but as text it drowns out the page ("github.com/orbit-labs/app/pull/482").
    static var urlLine: Regex<AnyRegexOutput> { try! Regex(#"^\s*(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/\S*)?\s*$"#).ignoresCase() }
    static func screenBody(_ text: String) -> String {
        let url = urlLine
        let kept = text.split(whereSeparator: \.isNewline).filter { $0.wholeMatch(of: url) == nil }
        return kept.isEmpty ? text : kept.joined(separator: "\n")
    }
    static func siteOnScreen(_ text: String) -> String? {
        let url = urlLine
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.wholeMatch(of: url) != nil }) else { return nil }
        var host = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        host = String(host.split(separator: "/").first ?? "")
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func isVague(_ name: String) -> Bool {
        let w = Style.words(name)
        return w.isEmpty || w.allSatisfy { kindWords.contains($0) }
    }

    /// Words the model must never hand back: they describe the container, not the content.
    static let banned: Set<String> = ["img", "image", "images", "photo", "picture", "pic", "heic", "jpg", "jpeg",
                                       "png", "svg", "pdf", "gif", "webp", "file", "document", "tbn", "download",
                                       "unknown", "untitled", "name", "none", "scan", "handwriting", "handwritten",
                                       "writing", "text", "screenshot",
                                       // words from our own instructions, which a small model likes to echo
                                       "title", "species", "style", "era", "detail", "details", "subject", "description",
                                       "fragment", "main", "specific"]

    /// Load the model into memory now, so the first real request doesn't pay for it.
    /// Wake the model up and wait until it answers. On a fresh install macOS sets it up first (~45 s);
    /// a window that waits for this once beats one where every file times out.
    static func warmUp() async {
        guard isAvailable else { return }
        _ = try? await LanguageModelSession().respond(to: "Reply with: ok", options: GenerationOptions(temperature: 0))
        // Images use a separate vision part with its own cold start: wake that too, with a tiny blank picture.
        if canSeeImages, #available(macOS 27.0, *),
           // Real size: images reach the model at ~1024 px, and a tiny picture doesn't warm that path.
           let ctx = CGContext(data: nil, width: 1024, height: 768, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 768))
            if let img = ctx.makeImage() {
                _ = try? await LanguageModelSession().respond(options: GenerationOptions(temperature: 0)) {
                    "What color is this? One word."
                    Attachment(img)
                }
            }
        }
    }

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

        // Images: caption first, then name from the caption — two small steps beat one big one (as for foreign text).
        // Asked for 1–3 words straight from the pixels, a small model collapses a whole scene to "landscape".
        // Only for real photos (little text): for screenshots and notes the text is the topic, and the
        // caption step adds noise there (tested: 57 → 54 on the screenshot cases when used for everything).
        var captioned = false
        var direct: String?        // one-call mode: the name came with the description
        let oneCall = true   // measured: photos 2.6 → 2.2 s, same names on both test sets
        // Screenshots: what KIND of thing is on screen (a chat, a listing, a boarding pass) plus what sets it apart.
        // A document-style name from the text alone gave "lunch-sunday" for a family chat planning Sunday lunch.
        if lookAtImage, e.isScreenshot, #available(macOS 27.0, *), let img = thumbnail(e.imageURL ?? e.url) {
            let s = LanguageModelSession(instructions: screenshotInstructions(words: words))
            var ask = ""
            if let h = e.headline { ask += "Biggest text: \(h)\n" }
            if let site = siteOnScreen(e.bodySnippet ?? "") { ask += "Website: \(site)\n" }
            if let b = e.bodySnippet, !b.isEmpty { ask += "Text on screen (may be partial):\n\(String(screenBody(b).prefix(700)))\n" }
            if !avoid.isEmpty { ask += "The owner rejected these names: \(avoid.joined(separator: ", ")). Give a different one.\n" }
            ask += "The screenshot is attached."
            let q = ask
            if let out = try? await s.respond(options: GenerationOptions(temperature: avoid.isEmpty ? 0 : 0.7, maximumResponseTokens: 100),
                                              prompt: { q; Attachment(img) }).content {
                var lines = out.split(whereSeparator: \.isNewline).map(String.init)
                // It may copy the examples' shape instead: "A reminder about the shared sink -> sink reminder".
                if !lines.contains(where: { $0.lowercased().hasPrefix("name:") }),
                   let arrow = lines.last(where: { $0.contains("->") }), let r = arrow.range(of: "->", options: .backwards) {
                    lines = ["What it is: " + arrow[..<r.lowerBound].replacingOccurrences(of: "What it is:", with: ""),
                             "Name: " + arrow[r.upperBound...]]
                }
                // Small models drop the "Name:" label now and then: the last line is the name then.
                direct = (lines.first(where: { $0.lowercased().hasPrefix("name:") }).map { String($0.dropFirst(5)) }
                          ?? (lines.count >= 2 ? lines.last : nil))?.trimmingCharacters(in: .whitespaces)
                // A small model sometimes hands back one of the examples word for word ("oslo weather forecast" for Istanbul).
                if let d = direct, screenshotExampleNames.contains(Style.words(d).joined(separator: " ")) { direct = nil }
                if let d = direct {
                    let onScreen = Set(Style.tokens(q)), squashed = Style.tokens(q).joined()
                    direct = Style.tokens(d).filter { !screenshotExampleWords.contains($0) || onScreen.contains($0)
                                                      || ($0.count >= 4 && squashed.contains($0)) }.joined(separator: " ")
                }
                let about = lines.first(where: { $0.lowercased().hasPrefix("what it is:") }).map { String($0.dropFirst(11)) }
                    ?? (lines.count >= 2 ? lines[0] : "")
                prompt = "Screenshot: \(about)\n" + q   // what the model saw, for the spelling and made-up-word checks below
                captioned = true
                // Only kind words ("chat reminder", "weather forecast", "system settings")? Every screenshot of that
                // kind would get the same name. Ask once more, from the text, for what sets this one apart.
                // Chats are named by what they're about, not who's in them ("landlord messages" → the heating repair).
                let chatWords: Set<String> = ["chat", "message", "messages", "conversation", "thread", "text", "texts", "dm"]
                // …but an "error message" or a "warning text" isn't a chat.
                let notChat: Set<String> = ["error", "warning", "alert", "dialog", "notification", "code", "verification", "system"]
                let isChat = direct.map { let w = Style.words($0); return w.contains { chatWords.contains($0) } && !w.contains { notChat.contains($0) } } ?? false
                if let d = direct, isVague(d), let b = e.bodySnippet, b.count > 20 {
                    // Asked to "make it specific" a 3B model rewords the same thing ("whatsapp message thread").
                    // Asked only for the TOPIC, it answers well; the kind word comes from its first answer.
                    let r = LanguageModelSession(instructions: """
                    You read the text of a screenshot and say what it is ABOUT: the topic, event, item, place or \
                    problem, in 1 to 3 lowercase English words. Never the app, never the kind of message, never a \
                    person's name, never a date, never a heading like "directions", "settings" or "inbox": look past it \
                    to what the screen is about (the destination, the change being made, the subject of the email).
                    Examples:
                    - "can you feed the cat while we're in Rome" -> cat sitting
                    - "Oslo -3° Snow H:-1 L:-6" -> oslo
                    - "Fix login crash on iOS 18 #213 · Open" -> login crash fix
                    - "Your parcel is out for delivery, tracking 1Z..." -> parcel delivery
                    - "From: Home  To: Heathrow Airport · 42 min" -> heathrow airport
                    - "studio · 1 ba · $1,800/mo" -> studio apartment
                    """)
                    let t = (e.headline.map { "Biggest text: \($0)\n" } ?? "") + "Text on screen:\n\(String(screenBody(b).prefix(600)))\nTopic:"
                    let topic = (try? await r.respond(to: t, options: GenerationOptions(temperature: 0)).content)?
                        .split(whereSeparator: \.isNewline).first.map { String($0).replacingOccurrences(of: "topic:", with: "", options: .caseInsensitive) }
                    let apps: Set<String> = ["whatsapp", "slack", "safari", "chrome", "finder", "imessage", "facetime", "github",
                                             "messages", "mail", "app", "application", "browser", "web", "page", "website", "screen", "screenshot", "system"]
                    let kind = Style.words(d).filter { !apps.contains($0) && !["a", "an", "the", "of", "with", "and", "for", "new", "my", "your"].contains($0) }
                    if ProcessInfo.processInfo.environment["NEATLY_DEBUG"] != nil {
                        FileHandle.standardError.write(Data("--- vague \(d), topic \(topic ?? "nil")\n".utf8))
                    }
                    if let topic, !isVague(topic), !refineExampleTopics.contains(Style.words(topic).joined(separator: " ")) {
                        let tw = Style.words(topic).filter { !apps.contains($0) }
                        let k = isChat ? ["chat"] : Array(kind.filter { !tw.contains($0) }.suffix(1))
                        direct = (tw + k.filter { !tw.contains($0) }).joined(separator: " ")
                    }
                }
                if ProcessInfo.processInfo.environment["NEATLY_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("--- screenshot\n\(q)\n--- answer\n\(out)\n".utf8))
                }
            }
        }
        // A vague name for a screen with almost nothing readable on it ("message" for a crop of "dfsadf"): the
        // screenshot's own name is more honest. Leave it.
        if e.isScreenshot, let d = direct, isVague(d), (e.bodySnippet ?? "").filter(\.isLetter).count < 25 { return nil }
        if direct == nil, lookAtImage, (e.bodySnippet?.count ?? 0) < 40, #available(macOS 27.0, *), let img = thumbnail(e.imageURL ?? e.url) {
            let c = LanguageModelSession(instructions: """
            You describe an image so it can be given a filename. Write one specific sentence: what the main subject is \
            (as specific as you can: the landmark, building, species, artwork style and era, vehicle, product, or kind of \
            document), the setting, and any clearly visible title, brand or name. Do not guess who a person is.
            """)
            var ask = "Describe this image."
            if let b = e.bodySnippet, !b.isEmpty { ask += "\nText read from the image (may be partial): \(String(withoutLetterhead(b).prefix(400)))" }
            if let p = e.place { ask += "\nThe photo was taken at: \(p). Use it to be specific (the landmark or city), but only say what you can see." }
            if oneCall {
                // One model call instead of two: the description and the name in the same answer.
                ask += """

                Answer in exactly two lines:
                Description: <one specific sentence>
                Name: <\(words.lowerBound) to \(words.upperBound) lowercase words, a short natural phrase: the MAIN SUBJECT first \
                (cats, a child, a painting, a castle, a ship), then its most specific detail — what it is doing, a title, \
                species, style or era; not background, clothing or small objects\(e.placeName != nil ? "; end with \"in <the place>\"" : "")>
                A person is the main subject when they fill the picture: say who (a woman, a man, a couple, friends, a \
                selfie), not what they wear.
                Examples of names: two cats on red chairs, red tulip in bloom, swan latte art, golden gate bridge in fog, \
                toddler laughing on a slide, smiling woman portrait, couple selfie at the beach
                """
                if !avoid.isEmpty { ask += "\nThe owner rejected these names: \(avoid.joined(separator: ", ")). Give a different one." }
            }
            let q = ask
            if var caption = try? await c.respond(options: GenerationOptions(temperature: avoid.isEmpty ? 0 : 0.7,
                                                                             maximumResponseTokens: oneCall ? 90 : 70),
                                                  prompt: { q; Attachment(img) }).content {
                if oneCall {
                    let lines = caption.split(whereSeparator: \.isNewline).map(String.init)
                    if let n = lines.first(where: { $0.lowercased().hasPrefix("name:") }) {
                        direct = String(n.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    }
                    caption = lines.first(where: { $0.lowercased().hasPrefix("description:") }).map { String($0.dropFirst(12)) } ?? caption
                }
                if ProcessInfo.processInfo.environment["NEATLY_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("--- caption\n\(caption)\n".utf8))
                }
                prompt = shots + "Image description: \(caption)\n"
                    + (e.headline.map { "Biggest text in the image: \($0)\n" } ?? "")
                    + (avoid.isEmpty ? "" : "The owner rejected these names: \(avoid.joined(separator: ", ")). Give a different name that is still specific to this file.\n")
                    + """
                    Name the MAIN SUBJECT first (a child, a painting, a map, a castle, a ship), then its most specific \
                    detail: a title, place, species, style or era. Ignore the background, clothing and small objects.
                    Examples:
                    - "A toddler laughing on a playground slide" -> toddler portrait
                    - "An oil painting in Renaissance style of a woman reading by a window" -> renaissance painting
                    - "A historical map titled 'Nova Hispania' showing Mexico" -> nova hispania map
                    - "A man speaking at a podium in front of a 'TechConf 2024' banner" -> techconf speaker
                    Name:
                    """
                captioned = true
            }
        }

        let session = LanguageModelSession(instructions: instructions(words: words))
        let options = GenerationOptions(temperature: avoid.isEmpty ? 0 : 0.7)   // a retry needs some variety
        let text: String
        if let direct {
            text = direct
        } else if lookAtImage, !captioned, #available(macOS 27.0, *), let img = thumbnail(e.imageURL ?? e.url) {
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
        // Screenshots read as titles: keep the small words that join them ("interview invite from stripe").
        let titled = lookAtImage && (e.isScreenshot || (e.bodySnippet?.count ?? 0) < 40)   // screenshots and photos
        let connectors: Set<String> = ["from", "to", "with", "for", "of", "on", "in", "at"]
        // Sentence words that make a title read like a sentence ("your booking is confirmed").
        let glue: Set<String> = ["your", "my", "our", "is", "are", "was", "were", "has", "have", "been", "be", "this", "that", "it", "its"]
        func W(_ s: String) -> [String] {
            titled ? Style.tokens(s).filter { (!Style.filler.contains($0) || connectors.contains($0) || $0 == "new") && !glue.contains($0) } : Style.words(s)
        }
        // First line only; models sometimes add an explanation after it.
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var line2 = line
        // Small models often copy words straight from a foreign text. If so, ask once more, just to translate.
        if let lang, summary == nil, copiedForeignWords(line, from: e) {
            line2 = await translate(line, from: lang) ?? line
        }
        // Small models misspell names they copy ("Aselsan" → "aseslan"): use the document's own spelling.
        // What the model saw: the file's text, plus its own caption for photos ("German Shepherd" → fixes "shepard").
        let source = Set(Style.words(([e.metadataTitle, e.headline, e.bodySnippet, e.linkHint].compactMap { $0 }
                                      + (captioned ? [prompt] : [])).joined(separator: " ")))
        line2 = W(line2).map { w in
            guard w.count >= 5, !source.contains(w) else { return w }
            return source.first { $0.first == w.first && abs($0.count - w.count) <= 2 && editDistance($0, w) <= 2 } ?? w
        }.joined(separator: " ")
        // Made-up words ("trickaide"): not in the file and not English → drop them.
        if let vocab = NLEmbedding.wordEmbedding(for: .english) {
            let joined = Style.words([e.metadataTitle, e.headline, e.bodySnippet].compactMap { $0 }.joined(separator: " ")).joined()
            line2 = W(line2).filter { source.contains($0) || vocab.contains($0) || $0.contains(where: \.isNumber)
                                                || ($0.count >= 3 && joined.contains($0)) }
                .joined(separator: " ")
        }
        // Images: every word must come from what the model saw (its caption or the text it read) or be a real word,
        // and letter salad from bad OCR ("cotrffjsol") never makes it into a name.
        if captioned, let vocab = NLEmbedding.wordEmbedding(for: .english) {
            let seen = Set(Style.words(prompt))
            // The text with nothing between words: "CafeNero_Guest" holds "nero", "Wi-Fi" holds "wifi".
            let squashed = Style.words([e.metadataTitle, e.headline, e.bodySnippet].compactMap { $0 }.joined(separator: " ")).joined()
            let salad = try! Regex("[bcdfghjklmnpqrstvwxz]{4,}")
            line2 = W(line2).filter { w in
                let onScreen = source.contains(w) || (w.count >= 3 && squashed.contains(w))
                // Letter salad from bad OCR is dropped — unless it's really written there ("Coldplay" has "ldpl").
                return onScreen || (vocab.contains(w) || seen.contains(w)) && w.firstMatch(of: salad) == nil
            }.joined(separator: " ")
        }
        let stemWords = Set(Style.words(e.stem))
        // Dropping the filename's own words stops junk coming back ("img" from IMG_4821) — but when the current name
        // is a real one ("egg-club"), the model agreeing with it is the answer: the file's name is already fine.
        let junkStem = Decision.junkReason(e.stem) != nil
        var w = W(line2).filter { ($0.count >= 2 || $0.allSatisfy(\.isNumber)) && !banned.contains($0) && !(junkStem && stemWords.contains($0)) && $0 != e.ext }
        // A joining word the file itself has between the same two words comes back: "pride prejudice" → "pride and
        // prejudice", "lord rings" → "lord of the rings" (titles read wrong without them).
        let said = " " + Style.tokens([e.metadataTitle, e.headline, e.bodySnippet].compactMap { $0 }.joined(separator: " ")).joined(separator: " ") + " "
        if w.count >= 2 {
            var joined: [String] = [w[0]]
            for (a, b) in zip(w, w.dropFirst()) {
                if let glue = [["and"], ["of"], ["of", "the"], ["and", "the"]].first(where: { said.contains(" \(a) \($0.joined(separator: " ")) \(b) ") }),
                   !connectors.contains(a), !connectors.contains(b) {
                    joined += glue
                }
                joined.append(b)
            }
            w = joined
        }
        let joiners: Set<String> = connectors.union(["and", "the"])
        // No joining word at either end, and never two in a row.
        while let f = w.first, joiners.contains(f) { w.removeFirst() }
        w = w.enumerated().filter { i, x in !(connectors.contains(x) && i > 0 && connectors.contains(w[i - 1])) }.map(\.1)
        let content = w.filter { !joiners.contains($0) }
        guard !content.isEmpty else { return nil }
        // The limit counts real words; joining words come along for free.
        var out: [String] = [], n = 0
        // Screenshots and photos: a little slack here; the caller cuts whole phrases to fit, not words mid-phrase.
        let cap = titled ? words.upperBound + 3 : words.upperBound
        for x in w { if !joiners.contains(x) { if n == cap { break }; n += 1 }; out.append(x) }
        while let l = out.last, joiners.contains(l) { out.removeLast() }
        return out
    }

    /// Downsampled copy: the model doesn't need 12 megapixels to tell a receipt from a cat.
    static func thumbnail(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF rotation
            kCGImageSourceThumbnailMaxPixelSize: 1024,   // 768 measured only ~2% faster and slightly worse
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
        cs213 is a course code; hw2 means homework 2. Answer only "yes" if the name fits the file, or "no" if it is wrong.
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
