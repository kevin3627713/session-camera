import SwiftUI
import WidgetKit
import Photos
import AppIntents

struct ProbeEntry: TimelineEntry { let date: Date; var url: String = "" }
struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry { ProbeEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) { completion(makeEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) { completion(Timeline(entries: [makeEntry()], policy: .after(Date().addingTimeInterval(60)))) }
    func makeEntry() -> ProbeEntry {
        let options = PHFetchOptions()
        // Target the older red photo; the newer blue decoy distinguishes a
        // selected asset from simply opening the most recent library photo.
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject,
              let result = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: [asset.localIdentifier])[asset.localIdentifier],
              let cloud = try? result.get() else {
            NSLog("SCURLPROBE widget missing fixture/authorization")
            return ProbeEntry(date: Date())
        }
        var url = URLComponents()
        url.scheme = "photos-navigation"
        url.host = "asset"
        url.queryItems = [URLQueryItem(name: "cloud-identifier", value: cloud.stringValue)]
        NSLog("SCURLPROBE widget fixture resolved")
        return ProbeEntry(date: Date(), url: url.url?.absoluteString ?? "")
    }
}

struct ProbeIntent: AppIntent {
    static var title: LocalizedStringResource = "Research URL dispatch"
    static var isDiscoverable = false
    static var openAppWhenRun = false
    @Parameter(title: "Route") var route: String
    @Parameter(title: "Fixture URL") var fixtureURL: String
    init() {}
    init(_ route: String, _ url: String) { self.route = route; self.fixtureURL = url }
    @MainActor func perform() async throws -> some IntentResult {
        NSLog("SCURLPROBE AppIntent perform bundle=%@ route=%@", Bundle.main.bundleIdentifier ?? "nil", route)
        if let url = URL(string: fixtureURL), url.scheme == "photos-navigation" {
            _ = SCProbeDispatch(route, url)
            // Keep this actual widget intent alive while a child extension starts.
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } else { NSLog("SCURLPROBE AppIntent has no fixture URL") }
        return .result()
    }
}
@main struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "URLRouteProbe", provider: ProbeProvider()) { entry in
            VStack(spacing: 12) {
                Text(entry.url.isEmpty ? "NO FIXTURE" : "URL ROUTE PROBE").font(.caption).foregroundStyle(.white)
                HStack {
                    Button("DIRECT", intent: ProbeIntent("direct", entry.url))
                    Button("SENSITIVE", intent: ProbeIntent("sensitive", entry.url))
                }.font(.caption).buttonStyle(.borderedProminent)
                HStack {
                    Button("SHARE", intent: ProbeIntent("share", entry.url))
                    Button("MAIN BG", intent: BackgroundProbeIntent(entry.url))
                }.font(.caption).buttonStyle(.borderedProminent)
            }.accessibilityElement(children: .contain).accessibilityIdentifier("url-route-probe")
                .containerBackground(.black, for: .widget)
        }.configurationDisplayName("URL Probe").description("Synthetic Photos navigation research").supportedFamilies([.systemMedium])
    }
}
