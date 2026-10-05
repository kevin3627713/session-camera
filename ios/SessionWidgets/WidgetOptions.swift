import AppIntents
import WidgetKit

enum CameraWidgetStyle: String, AppEnum {
    case preset, clear, blank, blur, standard, photos
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "小组件样式"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .preset: "沿用当前预设", .clear: "透明相机", .blank: "空白透明",
        .blur: "磨砂相机", .standard: "普通背景", .photos: "随机相册照片"
    ]
}

enum WidgetTapBehavior: String, AppEnum {
    case none, camera
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "点击行为"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .none: "不打开应用", .camera: "打开借拍"
    ]
}

struct PhotoSourceEntity: AppEntity {
    var id: String
    var name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "相册或文件夹"
    static var defaultQuery = PhotoSourceQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PhotoSourceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PhotoSourceEntity] {
        identifiers.map { PhotoLibrarySource.resolve($0) }
    }
    func suggestedEntities() async throws -> [PhotoSourceEntity] { PhotoLibrarySource.catalog() }
    func entities(matching string: String) async throws -> [PhotoSourceEntity] {
        PhotoLibrarySource.catalog().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

struct WidgetIdentityEntity: AppEntity {
    var id: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "独立小组件编号"
    static var defaultQuery = WidgetIdentityQuery()
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "独立编号 · \(String(id.prefix(8)))", subtitle: "不同编号使用独立随机序列")
    }
}

struct WidgetIdentityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetIdentityEntity] {
        identifiers.map { WidgetIdentityEntity(id: $0) }
    }
    func suggestedEntities() async throws -> [WidgetIdentityEntity] {
        // Selecting this fresh entity also separates widgets duplicated by iOS.
        [WidgetIdentityEntity(id: UUID().uuidString)]
    }
    func defaultResult() async throws -> WidgetIdentityEntity? {
        WidgetIdentityEntity(id: UUID().uuidString)
    }
}

struct CameraWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "借拍小组件设置"
    static var description = IntentDescription("修改样式、点击行为，以及每个照片小组件自己的来源和周期。")
    static var isDiscoverable: Bool = false

    @Parameter(title: "样式", default: .preset) var style: CameraWidgetStyle
    @Parameter(title: "点击行为", default: WidgetTapBehavior.none) var tapBehavior: WidgetTapBehavior
    @Parameter(title: "相册或文件夹") var source: PhotoSourceEntity?
    @Parameter(title: "更换间隔（分钟，5～10080）", default: 60) var intervalMinutes: Int
    @Parameter(title: "独立编号") var identity: WidgetIdentityEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$style, .equalTo, CameraWidgetStyle.photos) {
            Summary {
                \.$style
                \.$source
                \.$intervalMinutes
                \.$identity
                \.$tapBehavior
            }
        } otherwise: {
            Summary {
                \.$style
                \.$tapBehavior
            }
        }
    }
}

struct KeepWidgetOnHomeScreen: AppIntent {
    static var title: LocalizedStringResource = "留在主屏幕"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult { .result() }
}
