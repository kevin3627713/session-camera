import Foundation

@main struct PayloadTests {
    static func main() throws {
        let nonce = UUID().uuidString
        let expected: [AnyHashable: Any] = [SCPhotoBridgeAssetKey: "asset/L0/001",
            SCPhotoBridgeCloudKey: "full-cloud-identifier+reserved/value", SCPhotoBridgeNonceKey: nonce]
        let item = NSExtensionItem()
        item.userInfo = expected
        let original = try PhotoBridgePayload(item.userInfo!)
        precondition(original.assetID == "asset/L0/001" && original.nonce == nonce)

        // Use Foundation's actual property setter to enrich the same userInfo.
        item.attributedTitle = NSAttributedString(string: "System share title")
        let enriched = item.userInfo!
        precondition(enriched.count > 3, "Fixture must reproduce the old exact-count rejection")
        let payload = try PhotoBridgePayload(enriched)
        precondition(payload.assetID == original.assetID && payload.cloudIdentifier == original.cloudIdentifier && payload.nonce == original.nonce)

        let data = try NSKeyedArchiver.archivedData(withRootObject: item, requiringSecureCoding: true)
        let restored = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSExtensionItem.self, from: data)!
        let transported = try PhotoBridgePayload(restored.userInfo!)
        precondition(transported.assetID == payload.assetID && transported.cloudIdentifier == payload.cloudIdentifier && transported.nonce == nonce)

        for (key, value, code) in [(SCPhotoBridgeAssetKey, "", 13), (SCPhotoBridgeCloudKey, "", 14),
                                   (SCPhotoBridgeNonceKey, "bad-uuid", 15)] {
            var invalid = enriched
            invalid[key] = value
            do { _ = try PhotoBridgePayload(invalid); fatalError("Invalid \(key) was accepted") }
            catch { precondition((error as NSError).code == code) }
        }
        let report: [String: Any] = ["success": true, "count": 6,
            "enrichedUserInfoKeyCount": enriched.count,
            "checks": ["Real NSExtensionItem basic payload", "System title enriches userInfo without invalidating payload",
                "Secure coding retains required fields and extra metadata", "Missing asset rejected",
                "Missing cloud identifier rejected", "Malformed request nonce rejected"]]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: "artifacts/photo-bridge-payload-tests.json"))
        print(String(decoding: json, as: UTF8.self))
    }
}
