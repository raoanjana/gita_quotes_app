import SwiftUI

enum Theme {
    static let saffron = Color(red: 0.96, green: 0.55, blue: 0.16)
    static let deepSaffron = Color(red: 0.80, green: 0.30, blue: 0.08)
    static let cream = Color(red: 1.0, green: 0.97, blue: 0.90)

    static let background = LinearGradient(
        colors: [saffron, deepSaffron],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func verseFont(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}
