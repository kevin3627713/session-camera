import Foundation
import CoreGraphics

enum PhotoWidgetGeometry {
    /// Keep the largest possible aspect-fill window; only translate it.
    /// PHAsset's suggestion is in upright source pixels; PhotoKit uses unit
    /// coordinates. Its suggested window must never change our zoom level.
    static func crop(assetSize: CGSize, target: CGSize, suggestedPixelCrop: CGRect? = nil) -> CGRect {
        guard assetSize.width.isFinite, assetSize.height.isFinite,
              target.width.isFinite, target.height.isFinite,
              assetSize.width > 0, assetSize.height > 0, target.width > 0, target.height > 0 else { return .zero }
        let ratio = (target.width / target.height) / (assetSize.width / assetSize.height)
        let width = min(1, ratio), height = min(1, 1 / ratio)
        var x: CGFloat = 0.5, y: CGFloat = 0.5
        if let rect = suggestedPixelCrop,
           rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
           rect.width > 0, rect.height > 0, rect.minX >= 0, rect.minY >= 0,
           rect.maxX <= assetSize.width + 0.001, rect.maxY <= assetSize.height + 0.001 {
            x = rect.midX / assetSize.width
            y = rect.midY / assetSize.height
        }
        return CGRect(x: min(max(x - width / 2, 0), 1 - width),
                      y: min(max(y - height / 2, 0), 1 - height), width: width, height: height)
    }
}

enum PhotoWidgetLink {
    static func url(assetID: String) -> URL? {
        guard !assetID.isEmpty, assetID.count <= 2048 else { return nil }
        var components = URLComponents()
        components.scheme = "sessioncamera"
        components.host = "photos"
        components.queryItems = [URLQueryItem(name: "asset", value: assetID)]
        return components.url
    }

    static func assetID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "sessioncamera", components.host == "photos",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let items = components.queryItems, items.count == 1, items[0].name == "asset",
              let value = items[0].value, !value.isEmpty, value.count <= 2048 else { return nil }
        return value
    }
}
