#if WIDGET_PHOTO_DIAGNOSTICS
import AppIntents
import WidgetKit
import UIKit
import os
import Darwin

enum PhotoWidgetDiagnosticMode: String, AppEnum {
    case off, rendering, library, request
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "照片排查"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .off: "关闭（正常照片）", .rendering: "1 · 测试图与文字",
        .library: "2 · 只读取相册", .request: "3 · 请求照片但只显示结果"
    ]
}

enum WidgetPhotoDiagnostics {
    private static let logger = Logger(subsystem: "com.kevin3627713.sessioncamera.widgets", category: "PhotoPipeline")
    static var memoryMiB: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
    static func record(_ phase: String) {
        // No asset IDs, album names or photo bytes enter the system log.
        logger.info("phase=\(phase, privacy: .public) memoryMiB=\(memoryMiB, privacy: .public)")
    }
    static func testImage() -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.systemRed.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        }.pngData()
    }

    // Diagnostic timelines intentionally isolate rendering, PhotoKit access and
    // image loading. None of these paths exists in the normal extension binary.
    static func renderingTimeline(_ configuration: CameraWidgetConfiguration, now: Date) -> Timeline<CameraWidgetEntry>? {
        guard configuration.photoDiagnostic == .rendering else { return nil }
        record("rendering-test-ready")
        return Timeline(entries: [CameraWidgetEntry(date: now, style: .photos, tapBehavior: configuration.tapBehavior,
            imageData: testImage(), message: "绘制测试通过\n红蓝色块与文字")], policy: .never)
    }
    static func libraryTimeline(_ configuration: CameraWidgetConfiguration, now: Date, count: Int) -> Timeline<CameraWidgetEntry>? {
        guard configuration.photoDiagnostic == .library else { return nil }
        return Timeline(entries: [CameraWidgetEntry(date: now, style: .photos, tapBehavior: configuration.tapBehavior,
            message: "相册读取完成\n可用照片：\(count)\n权限：\(PhotoLibrarySource.status.rawValue)\n内存：\(String(format: "%.1f", memoryMiB)) MiB")], policy: .never)
    }
    static func requestTimeline(_ configuration: CameraWidgetConfiguration, now: Date, data: Data) -> Timeline<CameraWidgetEntry>? {
        guard configuration.photoDiagnostic == .request else { return nil }
        let pixels = PhotoImageMetadata.dimensions(data) ?? .zero
        record("request-test-ready")
        return Timeline(entries: [CameraWidgetEntry(date: now, style: .photos, tapBehavior: configuration.tapBehavior,
            message: "照片请求完成\n\(Int(pixels.width)) × \(Int(pixels.height)) 像素\n\(data.count / 1024) KiB\n内存：\(String(format: "%.1f", memoryMiB)) MiB")], policy: .never)
    }
}
#endif
