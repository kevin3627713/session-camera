import AppIntents
import Foundation

// App Intents documents this protocol as executing in the main app process.
// The experiment records whether that process is background or foreground.
struct BackgroundProbeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Research main-process background dispatch"
    static var isDiscoverable = false
    static var openAppWhenRun = false
    @Parameter(title: "Fixture URL") var fixtureURL: String
    init() {}
    init(_ url: String) { self.fixtureURL = url }
    @MainActor func perform() async throws -> some IntentResult {
        NSLog("SCURLPROBE background-main intent bundle=%@", Bundle.main.bundleIdentifier ?? "nil")
        if let url = URL(string: fixtureURL), url.scheme == "photos-navigation" { _ = SCProbeDispatch("direct", url) }
        try await Task.sleep(nanoseconds: 3_000_000_000)
        return .result()
    }
}
