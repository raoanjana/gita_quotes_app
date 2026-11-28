import Foundation
import UIKit

/// Anonymous usage analytics, sent to the Hindu Wisdom server (see server/).
///
/// Events carry a random install ID made on first launch and nothing that identifies
/// a person. They queue on the device and are sent in batches when the app opens or
/// goes to the background; if sending fails they are kept and retried later.
///
/// Release builds (TestFlight, App Store) send to the `AnalyticsEndpoint` URL in Info.plist,
/// if the user has left "Share anonymous usage data" on. Debug builds run from Xcode send
/// nothing unless given a server with the launch argument
/// `-AnalyticsEndpoint <url>` (for example the local test server, http://localhost:8787/v1/events),
/// so testing doesn't mix into real usage data.
@MainActor
final class Analytics {
    static let shared = Analytics()

    /// UserDefaults key for the user's on/off choice (on by default).
    static let enabledKey = "shareUsageData"

    private let maxQueued = 500
    private let batchSize = 50
    private var queue: [Event] = []
    private var sendingSince: Date?

    private struct Event: Codable {
        let name: String
        let ts: String
        let verse_id: String?
        let source: String?
        let props: [String: String]?
    }

    private struct Batch: Encodable {
        let install_id: String
        let app_version: String
        let os_version: String
        let events: [Event]
    }

    private init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        queue = (try? JSONDecoder().decode([Event].self, from: Data(contentsOf: Self.queueFile))) ?? []
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private var endpoint: URL? {
        #if DEBUG
        guard let s = UserDefaults.standard.string(forKey: "AnalyticsEndpoint") else { return nil }
        #else
        guard let s = Bundle.main.object(forInfoDictionaryKey: "AnalyticsEndpoint") as? String else { return nil }
        #endif
        return s.isEmpty ? nil : URL(string: s)
    }

    private var installID: String {
        let key = "analyticsInstallID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private static var queueFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("analytics-queue.json")
    }

    /// Record an event. Cheap: it only appends to the on-device queue.
    func log(_ name: String, verseID: String? = nil, source: String? = nil, props: [String: String]? = nil) {
        guard isEnabled, endpoint != nil else { return }
        let ts = ISO8601DateFormatter().string(from: Date.now)
        queue.append(Event(name: name, ts: ts, verse_id: verseID, source: source, props: props))
        if queue.count > maxQueued { queue.removeFirst(queue.count - maxQueued) }
        save()
    }

    /// Called when the user turns sharing off: drop anything not yet sent.
    func discardQueued() {
        queue.removeAll()
        save()
    }

    /// Send queued events in batches. Safe to call often; does nothing if already sending.
    /// Asks iOS for a little background time so a send started as the app closes can finish.
    func flush() {
        guard isEnabled, let url = endpoint, !queue.isEmpty else { return }
        // A send that has been going for over 30 s was cut off (the app was suspended); start again.
        if let since = sendingSince, Date.now.timeIntervalSince(since) < 30 { return }
        sendingSince = .now
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Send usage data") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        Task {
            defer {
                sendingSince = nil
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            while !queue.isEmpty, isEnabled {
                let chunk = Array(queue.prefix(batchSize))
                guard await post(chunk, to: url) else { return }   // keep them; retry next time
                queue.removeFirst(min(chunk.count, queue.count))
                save()
            }
        }
    }

    private func post(_ events: [Event], to url: URL) async -> Bool {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let batch = Batch(install_id: installID, app_version: version,
                          os_version: "iOS \(os.majorVersion).\(os.minorVersion)", events: events)
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(batch)
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        // 2xx: stored. 4xx: the server will never accept these, so don't retry them forever.
        return (200..<500).contains(status)
    }

    private func save() {
        try? JSONEncoder().encode(queue).write(to: Self.queueFile, options: .atomic)
    }
}
