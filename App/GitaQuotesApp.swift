import SwiftUI

@main
struct GitaQuotesApp: App {
    init() {
        CrashReports.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
