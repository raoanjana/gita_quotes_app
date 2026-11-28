import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration (long-press the widget → Edit Widget)

struct GitaWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Hindu Wisdom"
    static var description = IntentDescription("Choose whether the large widget shows the Sanskrit.")

    @Parameter(title: "Show Sanskrit (large widget)", default: false)
    var showSanskrit: Bool
}

// MARK: - Timeline

struct QuoteEntry: TimelineEntry {
    let date: Date
    let translation: Translation
    let showSanskrit: Bool

    /// Same verse for every widget at a given time.
    var quote: Quote { QuoteLibrary.quote(for: date, translation: translation) }
}

/// Today's verse plus tomorrow's, which WidgetKit swaps in at 4 am local time
/// even if it doesn't ask for a new timeline right then. After that it asks again.
private func dayTimeline(translation: Translation, showSanskrit: Bool) -> Timeline<QuoteEntry> {
    let now = Date.now
    let entries = [QuoteLibrary.dayStart(for: now), QuoteLibrary.nextDayStart(after: now)].map { date in
        QuoteEntry(date: date, translation: translation, showSanskrit: showSanskrit)
    }
    return Timeline(entries: entries, policy: .atEnd)
}

struct QuoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(date: .now, translation: .swarupananda, showSanskrit: false)
    }

    func snapshot(for configuration: GitaWidgetIntent, in context: Context) async -> QuoteEntry {
        QuoteEntry(date: .now, translation: .swarupananda, showSanskrit: configuration.showSanskrit)
    }

    func timeline(for configuration: GitaWidgetIntent, in context: Context) async -> Timeline<QuoteEntry> {
        dayTimeline(translation: .swarupananda, showSanskrit: configuration.showSanskrit)
    }
}

/// The Lock Screen widget has no settings: it shows the same verse as the Home Screen.
struct LockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(date: .now, translation: .swarupananda, showSanskrit: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuoteEntry) -> Void) {
        completion(QuoteEntry(date: .now, translation: .swarupananda, showSanskrit: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuoteEntry>) -> Void) {
        completion(dayTimeline(translation: .swarupananda, showSanskrit: false))
    }
}

// MARK: - Views

struct GitaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuoteEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            // The box below the clock. iOS tints it to match the wallpaper.
            let q = entry.quote
            VStack(alignment: .leading, spacing: 2) {
                Text(q.text(fitting: QuoteLibrary.Limit.lockScreen))
                    .font(.system(size: 14, design: .serif))
                    .minimumScaleFactor(0.75)
                Text(q.shortCitation)
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(q.deepLink(source: "lock_screen"))
        case .systemSmall:
            let q = entry.quote
            homeScreen(quote: q, text: q.text(fitting: QuoteLibrary.Limit.small), fontSize: 14, citation: q.shortCitation, source: "widget_small", small: true)
        case .systemMedium:
            let q = entry.quote
            homeScreen(quote: q, text: q.text(fitting: QuoteLibrary.Limit.medium), fontSize: 15, citation: q.attribution, source: "widget_medium", explain: "Explain")
        default:
            let q = entry.quote
            homeScreen(quote: q, text: q.text, fontSize: 19, citation: q.attribution, source: "widget_large", large: true, explain: "Explain this to me")
        }
    }

    private func homeScreen(quote: Quote, text: String, fontSize: CGFloat, citation: String, source: String, small: Bool = false, large: Bool = false, explain: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if large {
                if entry.showSanskrit {
                    Text(quote.sanskrit)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.cream.opacity(0.85))
                        .minimumScaleFactor(0.6)
                } else {
                    Text("ॐ").font(.title).foregroundStyle(Theme.cream.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            Text(text)
                .font(Theme.verseFont(size: fontSize))
                .foregroundStyle(Theme.cream)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 6) {
                Text(citation)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let explain {
                    Spacer(minLength: 4)
                    // Medium and large widgets can have a second tap target.
                    Link(destination: quote.explainLink(source: source)) {
                        Label(explain, systemImage: "text.book.closed")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.cream.opacity(0.22), in: Capsule())
                            .foregroundStyle(Theme.cream)
                    }
                } else if small {
                    Spacer(minLength: 4)
                    // The small widget allows only one tap target, so the whole
                    // widget opens the explanation; this icon says so.
                    Image(systemName: "text.book.closed")
                        .font(.caption2.weight(.semibold))
                        .padding(5)
                        .background(Theme.cream.opacity(0.22), in: Circle())
                        .foregroundStyle(Theme.cream)
                        .accessibilityLabel("Explain this verse")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(small ? quote.explainLink(source: source) : quote.deepLink(source: source))
    }
}

// MARK: - Widget

struct GitaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GitaWidget", intent: GitaWidgetIntent.self, provider: QuoteProvider()) { entry in
            GitaWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Hindu Wisdom")
        .description("A new verse from the Bhagavad Gita every morning. On the large size, Edit Widget can add the Sanskrit.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GitaLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GitaLockScreenWidget", provider: LockScreenProvider()) { entry in
            GitaWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Hindu Wisdom")
        .description("The same verse as your Home Screen widgets, in a short form that fits the Lock Screen.")
        // Below the clock only; no one-line version above the time.
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct GitaWidgetBundle: WidgetBundle {
    var body: some Widget {
        GitaWidget()
        GitaLockScreenWidget()
    }
}

#Preview(as: .accessoryRectangular) {
    GitaLockScreenWidget()
} timeline: {
    QuoteEntry(date: .now, translation: .swarupananda, showSanskrit: false)
}

#Preview(as: .systemLarge) {
    GitaWidget()
} timeline: {
    QuoteEntry(date: .now, translation: .swarupananda, showSanskrit: true)
}
