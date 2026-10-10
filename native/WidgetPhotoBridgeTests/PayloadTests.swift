import Foundation

@main struct PayloadTests {
    static func main() throws {
        let nonce = UUID().uuidString
        let expected: [AnyHashable: Any] = [SCPhotoBridgeAssetKey: "asset/L0/001",
            SCPhotoBridgeCloudKey: "full-cloud-identifier+reserved/value", SCPhotoBridgeNonceKey: nonce]
        let item = NSExtensionItem()
        item.userInfo = expected
        let original = try PhotoBridgePayload(item.userInfo!)
        precondition(original.assetID == "asset/L0/001" && original.nonce == nonce && !original.includeHidden)

        // Use Foundation's actual property setter to enrich the same userInfo.
        item.attributedTitle = NSAttributedString(string: "System share title")
        let enriched = item.userInfo!
        precondition(enriched.count > 3, "Fixture must reproduce the old exact-count rejection")
        let payload = try PhotoBridgePayload(enriched)
        precondition(payload.assetID == original.assetID && payload.cloudIdentifier == original.cloudIdentifier && payload.nonce == original.nonce)

        let data = try NSKeyedArchiver.archivedData(withRootObject: item, requiringSecureCoding: true)
        let restored = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSExtensionItem.self, NSDictionary.self,
            NSArray.self, NSString.self, NSAttributedString.self, NSData.self, NSNumber.self], from: data) as! NSExtensionItem
        let transported = try PhotoBridgePayload(restored.userInfo!)
        precondition(transported.assetID == payload.assetID && transported.cloudIdentifier == payload.cloudIdentifier && transported.nonce == nonce)

        for (key, value, code) in [(SCPhotoBridgeAssetKey, "", 13), (SCPhotoBridgeCloudKey, "", 14),
                                   (SCPhotoBridgeNonceKey, "bad-uuid", 15)] {
            var invalid = enriched
            invalid[key] = value
            do { _ = try PhotoBridgePayload(invalid); fatalError("Invalid \(key) was accepted") }
            catch { precondition((error as NSError).code == code) }
        }
        for flag in [false, true] {
            let flagged = NSExtensionItem()
            var fields = expected
            fields[SCPhotoBridgeIncludeHiddenKey] = flag
            flagged.userInfo = fields
            let archived = try NSKeyedArchiver.archivedData(withRootObject: flagged, requiringSecureCoding: true)
            let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSExtensionItem.self, NSDictionary.self,
                NSArray.self, NSString.self, NSNumber.self], from: archived) as! NSExtensionItem
            let decodedPayload = try PhotoBridgePayload(decoded.userInfo!)
            precondition(decodedPayload.includeHidden == flag && decodedPayload.assetID == original.assetID)
        }
        for value in ["true" as Any, NSNumber(value: 1) as Any] {
            var invalid = expected
            invalid[SCPhotoBridgeIncludeHiddenKey] = value
            do { _ = try PhotoBridgePayload(invalid); fatalError("Non-boolean hidden policy was accepted") }
            catch { precondition((error as NSError).code == 16) }
        }
        let report: [String: Any] = ["success": true, "count": 10,
            "enrichedUserInfoKeyCount": enriched.count,
            "checks": ["Real NSExtensionItem basic payload", "System title enriches userInfo without invalidating payload",
                "Secure coding retains required fields and extra metadata", "Missing asset rejected",
                "Missing cloud identifier rejected", "Malformed request nonce rejected",
                "Explicit hidden=false survives secure transport", "Explicit hidden=true survives secure transport",
                "String hidden flag rejected", "Numeric hidden flag rejected"]]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: URL(fileURLWithPath: "artifacts/photo-bridge-payload-tests.json"))
        print(String(decoding: json, as: UTF8.self))
    }
}
