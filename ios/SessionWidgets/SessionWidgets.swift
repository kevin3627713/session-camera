import SwiftUI
import WidgetKit
import Photos

struct CameraWidgetEntry: TimelineEntry {
    let date: Date
    let style: CameraWidgetStyle
    let tapBehavior: WidgetTapBehavior
    var imageData: Data?
    var message: String?
    var assetID: String?
    var instanceID: String?
    var includeHidden: Bool = false
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
        await makeTimeline(for: configuration, size: context.displaySize)
    }
    func makeTimeline(for configuration: CameraWidgetConfiguration, size: CGSize, now: Date = Date(),
                      loadImage: (String, CGSize, TimeInterval, Bool) async -> Data? = {
                          await PhotoLibrarySource.imageData(assetID: $0, size: $1, timeout: $2, includeHidden: $3)
                      }) async -> Timeline<CameraWidgetEntry> {
        #if WIDGET_PHOTO_DIAGNOSTICS
        WidgetPhotoDiagnostics.record("provider-start")
        #endif
        let style = resolved(configuration)
        func entry(_ message: String) -> CameraWidgetEntry {
            CameraWidgetEntry(date: now, style: style, tapBehavior: configuration.tapBehavior, message: message)
        }
        guard style == .photos else {
            return Timeline(entries: [CameraWidgetEntry(date: now, style: style, tapBehavior: configuration.tapBehavior)], policy: .never)
        }
        #if WIDGET_PHOTO_DIAGNOSTICS
        if let timeline = WidgetPhotoDiagnostics.renderingTimeline(configuration, now: now) { return timeline }
        WidgetPhotoDiagnostics.record("authorization-check")
        #endif
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
        #if WIDGET_PHOTO_DIAGNOSTICS
        WidgetPhotoDiagnostics.record("source-query-start")
        #endif
        #if WIDGET_PHOTO_DIAGNOSTICS
        if configuration.photoDiagnostic == .library {
            let assets = PhotoLibrarySource.assetIDs(sourceID: source.id, includeHidden: configuration.includeHidden)
            if let timeline = WidgetPhotoDiagnostics.libraryTimeline(configuration, now: now, count: assets.count) { return timeline }
        }
        #endif
        guard let window = PhotoSchedule.window(instanceID: identity.id, sourceID: source.id,
                                               minutes: configuration.intervalMinutes, now: now),
              let assetID = PhotoLibrarySource.selection(sourceID: source.id, instanceID: identity.id,
                                                        minutes: configuration.intervalMinutes, now: now,
                                                        includeHidden: configuration.includeHidden) else {
            let message = PhotoLibrarySource.status == .limited && source.id != PhotoLibrarySource.accessibleID
                ? "读取相册/文件夹需要完整照片访问；有限权限可选已授权照片"
                : configuration.includeHidden
                    ? "没有可读取的照片；隐藏相册锁定时系统可能拒绝读取"
                    : "来源为空、已删除或没有可访问的照片"
            return Timeline(entries: [entry(message)], policy: .after(now.addingTimeInterval(900)))
        }
        // Calculate the next boundary but load only the current image. Six
        // preloaded entries also caused snapshot() to load six full images.
        guard let imageData = await loadImage(assetID, size, 8, configuration.includeHidden) else {
        #if WIDGET_PHOTO_DIAGNOSTICS
            WidgetPhotoDiagnostics.record("provider-image-unavailable")
        #endif
            return Timeline(entries: [entry("照片暂未加载；稍后会重试")],
                            policy: .after(now.addingTimeInterval(300)))
        }
        #if WIDGET_PHOTO_DIAGNOSTICS
        if let timeline = WidgetPhotoDiagnostics.requestTimeline(configuration, now: now, data: imageData) { return timeline }
        WidgetPhotoDiagnostics.record("timeline-ready-one-image")
        #endif
        let message = WidgetPhotoOpenStatus.message(instanceID: identity.id, assetID: assetID, now: now)
        let refresh = message == nil ? window.nextDate : min(window.nextDate, now.addingTimeInterval(90))
        return Timeline(entries: [CameraWidgetEntry(date: now, style: .photos, tapBehavior: configuration.tapBehavior,
            imageData: imageData, message: message, assetID: assetID, instanceID: identity.id,
            includeHidden: configuration.includeHidden)],
            policy: .after(refresh))
    }
}

struct CameraWidgetView: View {
    let entry: CameraWidgetEntry
    @Environment(\.widgetFamily) private var family

    private func photoImage(_ data: Data) -> UIImage? {
        #if WIDGET_PHOTO_DIAGNOSTICS
        WidgetPhotoDiagnostics.record("view-image-decode-start")
        #endif
        let image = UIImage(data: data)
        #if WIDGET_PHOTO_DIAGNOSTICS
        WidgetPhotoDiagnostics.record(image == nil ? "view-image-invalid" : "view-image-ready")
        #endif
        return image
    }

    var body: some View {
        Group {
            if entry.tapBehavior == .camera {
                Link(destination: URL(string: "sessioncamera://camera")!) { content }
            } else if entry.tapBehavior == .photos, entry.style == .photos,
                      let id = entry.assetID, entry.imageData != nil {
                Button(intent: OpenWidgetPhoto(assetID: id, instanceID: entry.instanceID ?? id,
                                              includeHidden: entry.includeHidden)) { content }
            } else {
                // A full-size interactive control consumes the tap. Merely
                // removing widgetURL would still open the containing app.
                Button(intent: KeepWidgetOnHomeScreen()) { content }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel(entry.tapBehavior == .camera ? "打开借拍" :
            entry.tapBehavior == .photos && entry.assetID != nil ? "在系统照片中打开这张照片" : "借拍小组件，不打开应用")
    }

    private var content: some View {
        GeometryReader { geometry in
            ZStack {
                switch entry.style {
                case .standard: Color(uiColor: .secondarySystemBackground)
                case .blur: Rectangle().fill(.regularMaterial)
                case .photos:
                    if let data = entry.imageData, let image = photoImage(data) {
                        Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        if let message = entry.message {
                            Text(message).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                                .foregroundStyle(.white).padding(8).background(.black.opacity(0.6)).unredacted()
                        }
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
