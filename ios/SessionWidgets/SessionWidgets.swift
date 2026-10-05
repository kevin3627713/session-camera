import SwiftUI
import WidgetKit

private struct CameraEntry: TimelineEntry {
    let date: Date
}

private struct CameraProvider: TimelineProvider {
    func placeholder(in context: Context) -> CameraEntry { CameraEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (CameraEntry) -> Void) {
        completion(CameraEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CameraEntry>) -> Void) {
        completion(Timeline(entries: [CameraEntry(date: Date())], policy: .never))
    }
}

private enum BackgroundStyle {
    case standard, clear, blur, blank
    var kind: String {
        switch self {
        case .standard: return "SessionCamera.Standard"
        case .clear: return "SessionCamera.Clear"
        case .blur: return "SessionCamera.Blur"
        case .blank: return "SessionCamera.Blank"
        }
    }
    var name: String {
        switch self {
        case .standard: return "普通背景"
        case .clear: return "透明相机"
        case .blur: return "磨砂相机"
        case .blank: return "空白透明"
        }
    }
    var description: String {
        switch self {
        case .standard: return "普通系统背景，作为透明效果的对照。轻点打开借拍。"
        case .clear: return "尝试透出真实主屏幕壁纸，轻点打开借拍。适用于 iOS 18。"
        case .blur: return "尝试使用系统模糊背景，轻点打开借拍。适用于 iOS 18。"
        case .blank: return "留出透明网格区域，不显示前景内容；轻点仍可打开借拍。"
        }
    }
}

private struct CameraWidgetView: View {
    let style: BackgroundStyle
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if style == .blank {
                Color.clear
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.system(size: family == .systemSmall ? 38 : 48, weight: .light))
                    Text("借拍").font(.system(size: 19, weight: .semibold))
                    if family != .systemSmall {
                        Text("轻点进入相机").font(.system(size: 13))
                    }
                }
                .foregroundStyle(style == .standard ? Color.primary : .white)
                .shadow(color: style == .standard ? .clear : .black.opacity(0.45), radius: 2, y: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "sessioncamera://camera"))
        .accessibilityLabel(style == .blank ? "打开借拍相机" : "借拍，\(style.name)")
    }
}

private func cameraConfiguration(_ style: BackgroundStyle) -> some WidgetConfiguration {
    StaticConfiguration(kind: style.kind, provider: CameraProvider()) { _ in
        CameraWidgetView(style: style)
    }
    .configurationDisplayName(style.name)
    .description(style.description)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .containerBackgroundRemovable(true)
}

// Widget requires init(). Each kind has a distinct zero-argument type so
// WidgetKit can reconstruct it without losing a parameterized style.
private struct ClearCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(.clear) }
}
private struct BlankCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(.blank) }
}
private struct BlurCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(.blur) }
}
private struct StandardCameraWidget: Widget {
    var body: some WidgetConfiguration { cameraConfiguration(.standard) }
}

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
