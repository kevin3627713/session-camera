import SwiftUI
import WidgetKit
import Photos

struct BridgeEntry: TimelineEntry { let date: Date; var assetID: String? }
struct BridgeProvider: TimelineProvider {
    func placeholder(in context: Context) -> BridgeEntry { BridgeEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (BridgeEntry) -> Void) { getTimeline(in: context) { completion($0.entries[0]) } }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BridgeEntry>) -> Void) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate == %@", Date(timeIntervalSince1970: 1_700_000_000) as NSDate)
        options.fetchLimit = 1
        let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject
        completion(Timeline(entries: [BridgeEntry(date: Date(), assetID: asset?.localIdentifier)], policy: .never))
    }
}
@main struct BridgeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProductionPhotoBridgeTest", provider: BridgeProvider()) { entry in
            Group {
                if let assetID = entry.assetID {
                    Button(intent: OpenWidgetPhoto(assetID: assetID, instanceID: "bridge-ui-test")) {
                        Text("OPEN PHOTO").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.buttonStyle(.plain)
                } else { Text("NO FIXTURE") }
            }.containerBackground(.red, for: .widget)
        }.configurationDisplayName("URL Probe").description("Production Share bridge test")
            .supportedFamilies([.systemMedium])
    }
}
