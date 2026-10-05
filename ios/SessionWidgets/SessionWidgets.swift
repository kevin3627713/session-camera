import SwiftUI
import WidgetKit
import Photos

struct CameraWidgetEntry: TimelineEntry {
    let date: Date
    let style: CameraWidgetStyle
    let tapBehavior: WidgetTapBehavior
    var imageData: Data?
    var message: String?
}

struct CameraWidgetProvider: AppIntentTimelineProvider {
    let preset: CameraWidgetStyle
    func placeholder(in context: Context) -> CameraWidgetEntry {
        CameraWidgetEntry(date: Date(), style: preset, tapBehavior: .none)
    }
    func snapshot(for configuration: CameraWidgetConfiguration, in context: Context) async -> CameraWidgetEntry {
        if context.isPreview {
            return CameraWidgetEntry(date: Date(), style: resolved(configuration), tapBehavior: .none,
                                     message: "长按 → 编辑小组件，选择照片来源")
        }
        return await timeline(for: configuration, in: context).entries[0]
    }
    private func resolved(_ configuration: CameraWidgetConfiguration) -> CameraWidgetStyle {
        configuration.style == .preset ? preset : configuration.style
    }
    func timeline(for configuration: CameraWidgetConfiguration, in context: Context) async -> Timeline<CameraWidgetEntry> {
        let now = Date(), style = resolved(configuration)
        func entry(_ message: String) -> CameraWidgetEntry {
            CameraWidgetEntry(date: now, style: style, tapBehavior: configuration.tapBehavior, message: message)
        }
        guard style == .photos else {
            return Timeline(entries: [CameraWidgetEntry(date: now, style: style, tapBehavior: configuration.tapBehavior)], policy: .never)
        }
        guard PhotoLibrarySource.status == .authorized || PhotoLibrarySource.status == .limited else {
            return Timeline(entries: [entry("请在借拍的机主设置中开启照片权限")], policy: .after(now.addingTimeInterval(900)))
        }
        guard let source = configuration.source else {
            return Timeline(entries: [entry("长按 → 编辑小组件，选择相册或文件夹")], policy: .never)
        }
        guard let identity = configuration.identity, !identity.id.isEmpty else {
            return Timeline(entries: [entry("请在编辑小组件中选择一个独立编号")], policy: .never)
        }
        guard (5...10_080).contains(configuration.intervalMinutes) else {
            return Timeline(entries: [entry("更换间隔请填写 5～10080 分钟")], policy: .never)
        }
        let assets = PhotoLibrarySource.assetIDs(sourceID: source.id)
        guard !assets.isEmpty else {
            let message = PhotoLibrarySource.status == .limited && source.id != PhotoLibrarySource.accessibleID
                ? "读取相册/文件夹需要完整照片访问；有限权限可选已授权照片"
                : "来源为空、已删除或没有可访问的照片"
            return Timeline(entries: [entry(message)], policy: .after(now.addingTimeInterval(900)))
        }
        let picks = PhotoSchedule.plan(assetIDs: assets, instanceID: identity.id, sourceID: source.id,
                                      minutes: configuration.intervalMinutes, now: now)
        var data: [String: Data] = [:], entries: [CameraWidgetEntry] = []
        let deadline = Date().addingTimeInterval(16)
        for pick in picks {
            if data[pick.assetID] == nil && Date() < deadline {
                data[pick.assetID] = await PhotoLibrarySource.imageData(assetID: pick.assetID, size: context.displaySize)
            }
            entries.append(CameraWidgetEntry(date: pick.date, style: .photos, tapBehavior: configuration.tapBehavior,
                imageData: data[pick.assetID], message: "照片暂不可用，请联网后刷新小组件"))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct CameraWidgetView: View {
    let entry: CameraWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.tapBehavior == .camera {
                Button(intent: OpenBorrowCamera()) { content }
            } else {
                // A full-size interactive control consumes the tap. Merely
                // removing widgetURL would still open the containing app.
                Button(intent: KeepWidgetOnHomeScreen()) { content }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel(entry.tapBehavior == .camera ? "打开借拍" : "借拍小组件，不打开应用")
    }

    private var content: some View {
        GeometryReader { geometry in
            ZStack {
                switch entry.style {
                case .standard: Color(uiColor: .secondarySystemBackground)
                case .blur: Rectangle().fill(.regularMaterial)
                case .photos:
                    if let data = entry.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 30, weight: .light))
                            Text(entry.message ?? "选择相册或文件夹").font(.system(size: 13)).multilineTextAlignment(.center)
                        }.foregroundStyle(.primary).padding(18)
                    }
                default: Color.clear
                }
                if entry.style != .blank && entry.style != .photos {
                    VStack(spacing: 12) {
                        Image(systemName: "camera").font(.system(size: family == .systemSmall ? 38 : 48, weight: .light))
                        Text("借拍").font(.system(size: 19, weight: .semibold))
                        if family != .systemSmall { Text("长按可编辑样式").font(.system(size: 13)) }
                    }
                    .foregroundStyle(entry.style == .standard ? Color.primary : .white)
                    .shadow(color: entry.style == .standard ? .clear : .black.opacity(0.45), radius: 2, y: 1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private func cameraConfiguration(kind: String, preset: CameraWidgetStyle, name: String) -> some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: CameraWidgetConfiguration.self, provider: CameraWidgetProvider(preset: preset)) { entry in
        CameraWidgetView(entry: entry)
    }
    .configurationDisplayName(name)
    .description("长按 → 编辑小组件，可切换五种样式；照片支持相册/文件夹、独立编号和更换周期。默认点击不打开应用。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .containerBackgroundRemovable(true)
    .contentMarginsDisabled()
    .promptsForUserConfiguration()
}

// Keep the old kinds so existing installations can gain editing in place.
private struct ClearCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(kind: "SessionCamera.Clear", preset: .clear, name: "借拍 · 可编辑样式") }
}
private struct BlankCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(kind: "SessionCamera.Blank", preset: .blank, name: "空白透明 · 可编辑样式") }
}
private struct BlurCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(kind: "SessionCamera.Blur", preset: .blur, name: "磨砂相机 · 可编辑样式") }
}
private struct StandardCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(kind: "SessionCamera.Standard", preset: .standard, name: "普通背景 · 可编辑样式") }
}

#if !WIDGET_INTEGRATION_TEST
@main
struct SessionCameraWidgets: WidgetBundle {
    init() { SCInstallWidgetBackgroundHook() }
    var body: some Widget {
        ClearCameraWidget()
        BlankCameraWidget()
        BlurCameraWidget()
        StandardCameraWidget()
    }
}
#endif
