import SwiftUI

struct ContentView: View {
    @AppStorage("translation") private var translation: Translation = .swarupananda
    @AppStorage("showSanskrit") private var showSanskrit = false
    // Opens on the same verse the widgets are showing right now.
    @State private var verseID = QuoteLibrary.verse(for: .now).id
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case howTo, about, explain
        var id: String { rawValue }
    }

    private var quote: Quote {
        QuoteLibrary.quote(verseID: verseID, translation: translation)
            ?? QuoteLibrary.quote(for: .now, translation: translation)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    settingsMenu
                }

                Text("ॐ")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.cream.opacity(0.9))

                ScrollView {
                    VStack(spacing: 20) {
                        if showSanskrit {
                            Text(quote.sanskrit)
                                .font(.system(size: 18))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Theme.cream.opacity(0.85))
                        }
                        Text(quote.text)
                            .font(Theme.verseFont(size: quote.text.count > 220 ? 20 : 24))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.cream)
                        VStack(spacing: 4) {
                            Text("— \(quote.citation)")
                                .font(.subheadline.weight(.semibold))
                            Text(translation.title)
                                .font(.caption)
                        }
                        .foregroundStyle(Theme.cream.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .id(quote.id)
                    .transition(.opacity)
                }
                .scrollBounceBehavior(.basedOnSize)

                Button {
                    sheet = .explain
                } label: {
                    Label("Explain this to me", systemImage: "text.book.closed")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.cream)

                HStack(spacing: 16) {
                    Button {
                        withAnimation(.easeInOut) { verseID = randomVerseID() }
                    } label: {
                        Label("Another verse", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cream)
                    .foregroundStyle(Theme.deepSaffron)

                    ShareLink(item: "\u{201C}\(quote.text)\u{201D}\n— \(quote.attribution)") {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.cream)
                }

                Button("How to add the widget") { sheet = .howTo }
                    .font(.footnote)
                    .foregroundStyle(Theme.cream.opacity(0.85))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
        }
        .onOpenURL { url in
            // gitaquotes://verse/2.47?t=arnold[&explain=1] — sent when the widget is tapped
            guard url.host == "verse" else { return }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let t = items.first(where: { $0.name == "t" })?.value,
               let tr = Translation(rawValue: t) {
                translation = tr
            }
            verseID = url.lastPathComponent
            sheet = items.contains(where: { $0.name == "explain" }) ? .explain : nil
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .howTo: HowToSheet()
            case .about: AboutSheet()
            case .explain: ExplanationSheet(quote: quote, showSanskrit: showSanskrit)
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Show Sanskrit", isOn: $showSanskrit)
            Button("About this translation") { sheet = .about }
        } label: {
            Label(translation.shortTitle, systemImage: "book")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.cream.opacity(0.2), in: Capsule())
                .foregroundStyle(Theme.cream)
        }
    }

    private func randomVerseID() -> String {
        let ids = QuoteLibrary.verses.map(\.id)
        var next = verseID
        while next == verseID { next = ids.randomElement()! }
        return next
    }
}

private struct HowToSheet: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Home Screen") {
                    Label("Touch and hold an empty spot on your Home Screen until the apps jiggle.", systemImage: "hand.tap")
                    Label("Tap Edit (or +) in the top corner, then Add Widget.", systemImage: "plus.circle")
                    Label("Search for \u{201C}Gita Quotes\u{201D}, choose a size, and tap Add Widget.", systemImage: "magnifyingglass")
                    Label("To show the Sanskrit on the large widget, touch and hold it and choose Edit Widget.", systemImage: "book")
                    Label("A new verse arrives every morning at 4 am. Tap the widget to open it here.", systemImage: "clock.arrow.circlepath")
                    Label("On medium and large widgets, tap \u{201C}Explain this to me\u{201D} to read the backstory and meaning.", systemImage: "text.book.closed")
                }
                Section("Lock Screen") {
                    Label("Wake your iPhone, then touch and hold the Lock Screen and tap Customize.", systemImage: "lock")
                    Label("Choose Lock Screen, then tap the widget area below the clock.", systemImage: "rectangle.on.rectangle")
                    Label("Pick \u{201C}Gita Quotes\u{201D} and tap Done.", systemImage: "checkmark.circle")
                    Label("It shows the same verse as your Home Screen widgets. Long verses appear as a short excerpt; tap to read the whole verse.", systemImage: "book")
                }
            }
            .navigationTitle("Add a widget")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ExplanationSheet: View {
    let quote: Quote
    let showSanskrit: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(quote.verse.chapterTitle.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.deepSaffron)

                    VStack(alignment: .leading, spacing: 10) {
                        if showSanskrit {
                            Text(quote.sanskrit)
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.cream.opacity(0.85))
                        }
                        Text(quote.text)
                            .font(Theme.verseFont(size: 19))
                            .foregroundStyle(Theme.cream)
                        Text("— \(quote.citation) · \(quote.translation.shortTitle)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.cream.opacity(0.8))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's happening, and what it means")
                            .font(.headline)
                        Text(quote.explanation)
                            .font(.body)
                            .lineSpacing(4)
                    }

                    ShareLink(item: "\u{201C}\(quote.text)\u{201D}\n— \(quote.attribution)\n\n\(quote.explanation)") {
                        Label("Share verse and explanation", systemImage: "square.and.arrow.up")
                    }
                    .font(.subheadline)
                    .tint(Theme.deepSaffron)
                }
                .padding(20)
            }
            .navigationTitle("Bhagavad Gita \(quote.verse.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

private struct AboutSheet: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(Translation.allCases) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.title).font(.headline)
                        Text(t.sourceNote).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Text("Sanskrit text from the gita/gita project (public domain). Verse numbers follow the standard numbering.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Translation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview { ContentView() }
