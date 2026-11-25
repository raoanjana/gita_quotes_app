import Foundation

// MARK: - Languages and translations

/// Language of a translation's text. Explanations exist in each of these.
/// The app is English-only for now; add a case here to bring a language back.
enum Language: String, CaseIterable, Codable {
    case en
}

/// The app uses one translation. The type stays so a second one could be added later.
enum Translation: String, CaseIterable, Identifiable, Codable {
    case swarupananda

    var id: String { rawValue }

    var language: Language { .en }

    var title: String { "Swami Swarupananda (1909)" }

    var shortTitle: String { "Swarupananda" }

    var sourceNote: String {
        String(localized: "Srimad-Bhagavad-Gita, translated by Swami Swarupananda (Advaita Ashrama, Mayavati, 1909). Public domain. Text from sacred-texts.com. Where Swarupananda translates two verses as one sentence, they appear together, as in 12.13–14.")
    }
}

// MARK: - Verses

struct Verse: Identifiable, Hashable {
    let chapter: Int
    let verse: String          // String so ranges like "62–63" work
    let sanskrit: String
    /// Backstory + lesson, shown by "Explain this to me".
    let explanations: [Language: String]
    let texts: [Translation: String]
    /// Word-for-word excerpts ("…" marks skipped words) for when the full
    /// text is too long for a small widget or the Lock Screen.
    let shortTexts: [Translation: String]

    var id: String { "\(chapter).\(verse)" }

    var chapterTitle: String {
        let name = Verse.chapterNames[chapter].map { String(localized: $0) } ?? ""
        return String(localized: "Chapter \(chapter) · \(name)")
    }

    static let chapterNames: [Int: String.LocalizationValue] = [
        1: "Arjuna's Despair",
        2: "The Yoga of Knowledge",
        3: "The Yoga of Action",
        4: "The Yoga of Knowledge and Renunciation of Action",
        5: "The Yoga of Renunciation",
        6: "The Yoga of Meditation",
        7: "The Yoga of Knowledge and Realisation",
        8: "The Imperishable Brahman",
        9: "The Royal Knowledge and Royal Secret",
        10: "Divine Glories",
        11: "The Vision of the Universal Form",
        12: "The Yoga of Devotion",
        13: "The Field and the Knower of the Field",
        14: "The Three Qualities of Nature",
        15: "The Supreme Person",
        16: "Divine and Demonic Natures",
        17: "The Three Kinds of Faith",
        18: "Liberation through Renunciation",
    ]
}

/// One verse in one translation — what the app and widgets display.
struct Quote: Identifiable, Hashable {
    let verse: Verse
    let translation: Translation

    var id: String { "\(verse.id)-\(translation.rawValue)" }
    var text: String { verse.texts[translation] ?? "" }

    /// The full text if it fits within `limit` characters; otherwise the
    /// translation's excerpt, or failing that a trimmed version ending in "…".
    /// Line breaks (Arnold's verse) are flattened in short form.
    func text(fitting limit: Int) -> String {
        let full = text.replacingOccurrences(of: "\n", with: " ")
        if full.count <= limit { return text }
        if let short = verse.shortTexts[translation], short.count <= limit { return short }
        return Quote.trim(full, to: limit)
    }

    static func trim(_ s: String, to limit: Int) -> String {
        let head = String(s.prefix(limit - 1))
        // Prefer ending at a clause boundary if it keeps most of the text.
        if let r = head.lastIndex(where: { ".;:!?".contains($0) }),
           head.distance(from: head.startIndex, to: r) > limit / 2 {
            return String(head[...r]).trimmingCharacters(in: CharacterSet(charactersIn: ";:,")) + " …"
        }
        let words = head.split(separator: " ").dropLast()
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ";:,")) + " …"
    }
    var sanskrit: String { verse.sanskrit }
    /// The explanation in the same language as the verse text.
    var explanation: String { verse.explanations[translation.language] ?? verse.explanations[.en] ?? "" }
    var citation: String { String(localized: "Bhagavad Gita \(verse.id)") }
    var shortCitation: String { "BG \(verse.id)" }
    var attribution: String { "\(citation) · \(translation.shortTitle)" }

    var deepLink: URL {
        URL(string: "gitaquotes://verse/\(verse.id)?t=\(translation.rawValue)")!
    }

    /// Opens the app straight to this verse's explanation.
    var explainLink: URL {
        URL(string: "gitaquotes://verse/\(verse.id)?t=\(translation.rawValue)&explain=1")!
    }
}

// MARK: - Library

enum QuoteLibrary {
    /// The verse changes once a day, at this hour of the user's local time.
    /// Every widget and the app show the same verse.
    static let dayStartHour = 4

    /// Character limits for each place a verse appears.
    enum Limit {
        static let lockScreen = 95
        static let small = 120
        static let medium = 200
    }

    static var verses: [Verse] { VerseData.verses }

    /// The verse for a given moment. It doesn't depend on translation or widget
    /// size, so the Home Screen, the Lock Screen and the app always agree.
    static func verse(for date: Date) -> Verse {
        let day = dayNumber(for: date)
        // Simple hash so consecutive days don't walk through the list in order.
        // The multiplier shares no factor with the verse count, so every verse
        // appears once before any repeats.
        let index = (day &* 2654435761 % verses.count + verses.count) % verses.count
        return verses[index]
    }

    static func quote(for date: Date, translation: Translation) -> Quote {
        quote(verse: verse(for: date), translation: translation)
    }

    /// Every verse has Swarupananda's text; the fallback only guards against a stale setting.
    static func quote(verse: Verse, translation: Translation) -> Quote {
        Quote(verse: verse, translation: verse.texts[translation] != nil ? translation : .swarupananda)
    }

    static func quote(verseID: String, translation: Translation) -> Quote? {
        verses.first(where: { $0.id == verseID }).map { quote(verse: $0, translation: translation) }
    }

    /// Gregorian calendar in the user's time zone, so the day boundary is local
    /// whatever calendar the phone is set to display.
    static var localCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    /// Start of the verse-day containing `date`: the most recent 4 am, local time.
    static func dayStart(for date: Date, calendar: Calendar = localCalendar) -> Date {
        guard let todays = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: date) else { return date }
        if todays <= date { return todays }
        return calendar.date(byAdding: .day, value: -1, to: todays) ?? todays
    }

    /// When the next verse arrives: the 4 am after `date`, local time.
    static func nextDayStart(after date: Date, calendar: Calendar = localCalendar) -> Date {
        let start = dayStart(for: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
    }

    /// Which verse-day `date` falls in. Everyone whose phone shows the same date
    /// (after 4 am) gets the same number, and so the same verse.
    static func dayNumber(for date: Date, calendar: Calendar = localCalendar) -> Int {
        let d = calendar.dateComponents([.year, .month, .day], from: dayStart(for: date, calendar: calendar))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: d) ?? date
        return Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
    }
}
