import Foundation
import MetricKit

/// Crash and hang reports from MetricKit, forwarded to the Hindu Wisdom server.
///
/// iOS collects a report when the app crashes or freezes and hands it to the app the
/// next time it opens (sometimes up to a day later). Each report becomes one `crash` or
/// `hang` event with a short summary: what kind of failure, the app build, and the top of
/// the call stack as `binary+offset`, which `atos` turns back into source lines using the
/// build's dSYM. Sent through `Analytics`, so the "Share anonymous usage data" switch
/// covers it too. Full reports for App Store users are also in Xcode → Organizer → Crashes.
final class CrashReports: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReports()

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var events: [(name: String, props: [String: String])] = []
        for payload in payloads {
            let day = Self.day(payload.timeStampEnd)
            for crash in payload.crashDiagnostics ?? [] {
                var props = Self.stackSummary(crash.callStackTree.jsonRepresentation())
                props["build"] = Self.clip(crash.metaData.applicationBuildVersion)
                props["occurred"] = day
                if let v = crash.exceptionType { props["exception_type"] = v.stringValue }
                if let v = crash.signal { props["signal"] = v.stringValue }
                if let v = crash.terminationReason { props["termination_reason"] = Self.clip(v) }
                events.append(("crash", props))
            }
            for hang in payload.hangDiagnostics ?? [] {
                var props = Self.stackSummary(hang.callStackTree.jsonRepresentation())
                props["build"] = Self.clip(hang.metaData.applicationBuildVersion)
                props["occurred"] = day
                props["hang_seconds"] = String(format: "%.1f", hang.hangDuration.converted(to: .seconds).value)
                events.append(("hang", props))
            }
        }
        guard !events.isEmpty else { return }
        Task { @MainActor in
            for e in events { Analytics.shared.log(e.name, props: e.props) }
            Analytics.shared.flush()
        }
    }

    // MARK: - Summarising a call stack

    /// The first three frames of the crashing (or hanging) thread, plus the first frame
    /// inside the app itself, as `binary+0xoffset`. Pure function, so it can be tested.
    static func stackSummary(_ json: Data, appBinary: String = appBinaryName) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]] else { return [:] }
        let thread = stacks.first(where: { ($0["threadAttributed"] as? Bool) == true }) ?? stacks.first
        var frame = (thread?["callStackRootFrames"] as? [[String: Any]])?.first
        var frames: [[String: Any]] = []
        while let f = frame, frames.count < 64 {
            frames.append(f)
            frame = (f["subFrames"] as? [[String: Any]])?.first
        }
        var props: [String: String] = [:]
        for (i, f) in frames.prefix(3).enumerated() { props["frame\(i + 1)"] = describe(f) }
        if let own = frames.first(where: { ($0["binaryName"] as? String) == appBinary }) {
            props["app_frame"] = describe(own)
            if let uuid = own["binaryUUID"] as? String { props["app_uuid"] = clip(uuid) }
        }
        return props
    }

    static var appBinaryName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "GitaQuotes"
    }

    private static func describe(_ frame: [String: Any]) -> String {
        let name = frame["binaryName"] as? String ?? "?"
        let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value ?? 0
        return clip("\(name)+0x\(String(offset, radix: 16))")
    }

    /// The server accepts property values up to 64 characters.
    private static func clip(_ s: String) -> String { String(s.prefix(64)) }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
