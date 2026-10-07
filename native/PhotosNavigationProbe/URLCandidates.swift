import Foundation

struct ProbeIdentifiers: Codable, Equatable {
    let assetLocalID: String
    let albumLocalID: String
    let albumName: String
    let assetCloudID: String?
    let albumCloudID: String?
    let mappingNotes: [String]

    static func uuid(from localID: String) -> String? {
        guard let first = localID.split(separator: "/").first,
              let uuid = UUID(uuidString: String(first)) else { return nil }
        return uuid.uuidString
    }
    var assetUUID: String? { Self.uuid(from: assetLocalID) }
    var albumUUID: String? { Self.uuid(from: albumLocalID) }
}

struct ProbeCandidate: Identifiable {
    let id: String
    let title: String
    let detail: String
    let url: URL?

    static func build(_ scheme: String, _ host: String, _ values: [(String, String?)]) -> URL? {
        guard values.allSatisfy({ $0.1?.isEmpty == false }) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = values.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url
    }

    static func all(_ ids: ProbeIdentifiers) -> [Self] {
        [
            .init(id: "A", title: "A · 外部照片入口", detail: "基准：定位照片，通常进入所有照片", url:
                build("photos-navigation", "asset", [("cloud-identifier", ids.assetCloudID)])),
            .init(id: "B", title: "B · 外部相册入口", detail: "验证真实相册云标识能否打开目标相册", url:
                build("photos-navigation", "album", [("cloud-identifier", ids.albumCloudID)])),
            .init(id: "C", title: "C · 内部照片＋相册 UUID", detail: "重点：照片大图携带相册上下文", url:
                build("photos", "asset", [("uuid", ids.assetUUID), ("albumuuid", ids.albumUUID)])),
            .init(id: "D", title: "D · 内部相册＋照片 UUID", detail: "重点：在目标相册中定位照片", url:
                build("photos", "album", [("uuid", ids.albumUUID), ("revealassetuuid", ids.assetUUID)])),
            .init(id: "E", title: "E · 内部照片本机标识", detail: "完整本机照片标识＋相册 UUID", url:
                build("photos", "asset", [("identifier", ids.assetLocalID), ("albumuuid", ids.albumUUID)])),
            .init(id: "F", title: "F · 内部相册本机标识", detail: "完整本机相册标识＋照片 UUID", url:
                build("photos", "album", [("identifier", ids.albumLocalID), ("revealassetuuid", ids.assetUUID)])),
            .init(id: "G", title: "G · 内部照片云标识", detail: "完整照片云标识＋相册 UUID", url:
                build("photos", "asset", [("cloud-identifier", ids.assetCloudID), ("albumuuid", ids.albumUUID)])),
            .init(id: "H", title: "H · 外部照片＋相册参数", detail: "版本对照：18.2 解析器忽略相册参数", url:
                build("photos-navigation", "asset", [("cloud-identifier", ids.assetCloudID), ("albumuuid", ids.albumUUID)])),
            .init(id: "I", title: "I · 外部相册＋照片参数", detail: "版本对照：18.2 解析器忽略照片参数", url:
                build("photos-navigation", "album", [("cloud-identifier", ids.albumCloudID), ("revealassetuuid", ids.assetUUID)])),
            .init(id: "J", title: "J · 内部图库定位", detail: "对照：所有照片中的大图入口", url:
                build("photos", "contentmode", [("id", "photos"), ("assetuuid", ids.assetUUID), ("oneUp", "1")])),
            .init(id: "K", title: "K · 内部相册名称入口", detail: "仅打开相册，检查名称是否被识别", url:
                build("photos", "userAlbum", [("name", ids.albumName)]))
        ]
    }

    static func permitted(_ url: URL) -> Bool {
        ["photos", "photos-navigation", "photos-redirect"].contains(url.scheme?.lowercased() ?? "") &&
            url.host?.isEmpty == false && url.absoluteString.utf8.count <= 16_384
    }
}

enum ProbeRoute: String, CaseIterable, Identifiable {
    case standard, direct, sensitive, share, shareSensitive = "share-sensitive"
    case frontBoard = "frontboard", shareFrontBoard = "share-frontboard"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "1 · 普通打开 URL"
        case .direct: return "2 · 主应用：私有普通派发"
        case .sensitive: return "3 · 主应用：私有敏感派发"
        case .share: return "4 · 中转扩展：私有普通派发"
        case .shareSensitive: return "5 · 中转扩展：私有敏感派发"
        case .frontBoard: return "6 · 主应用：直接系统启动"
        case .shareFrontBoard: return "7 · 中转扩展：直接系统启动"
        }
    }
}

struct ProbeRecord: Codable, Identifiable {
    let id: String
    let started: String
    let candidate: String
    let route: String
    let url: String
    let identifiers: ProbeIdentifiers
    var parser: String
    var dispatch: String
    var observation: String
    var routeTitle: String {
        route == "inspect-only" ? "只检查系统解析结果" : (ProbeRoute(rawValue: route)?.title ?? route)
    }
}
