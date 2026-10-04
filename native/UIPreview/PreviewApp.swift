import UIKit
import SwiftUI

// This file and CAMERA_UI_PREVIEW are used only by the separate simulator
// executable. Runner's release target has neither; it cannot load demo photos.
enum CameraUIPreview {
    static let enabled = true
    static var screen: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--screen"), arguments.indices.contains(index + 1) else { return "camera" }
        return arguments[index + 1]
    }
    static let image = makeImage(variant: 5)

    // A screenshot must wait for the requested view and its image rendering,
    // rather than assuming every simulator launch finishes within three seconds.
    static func reportReady(_ state: String) {
        guard screen == state else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let marker = directory.appendingPathComponent("ui-preview-ready-\(state)")
            try? Data(state.utf8).write(to: marker, options: .atomic)
        }
    }

    // Original, procedurally drawn still life for reproducible UI screenshots.
    // No network image, photo-library access or camera hardware is involved.
    static func makeImage(variant: Int) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            let hue = CGFloat(variant) * 0.012
            let colors = [UIColor(red: 0.86 + hue, green: 0.88, blue: 0.81, alpha: 1).cgColor,
                          UIColor(red: 0.48, green: 0.65 + hue, blue: 0.59, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 900, y: 1100), options: [])
            UIColor(red: 0.95, green: 0.93, blue: 0.82, alpha: 0.7).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 250, height: 920))
            UIColor.white.withAlphaComponent(0.4).setFill()
            context.fill(CGRect(x: 46, y: 0, width: 14, height: 920))
            context.fill(CGRect(x: 0, y: 230, width: 250, height: 12))
            context.fill(CGRect(x: 0, y: 540, width: 250, height: 12))
            UIColor(red: 0.82, green: 0.68, blue: 0.48, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 940, width: 900, height: 260))
            context.saveGState()
            context.setShadow(offset: CGSize(width: 70, height: 22), blur: 28, color: UIColor.black.withAlphaComponent(0.22).cgColor)
            UIColor(red: 0.24, green: 0.38, blue: 0.33, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 325, y: 957, width: 235, height: 34)).fill()
            context.restoreGState()
            UIColor(red: 0.88, green: 0.45 + hue, blue: 0.29, alpha: 1).setFill()
            let vase = UIBezierPath()
            vase.move(to: CGPoint(x: 383, y: 714))
            vase.addCurve(to: CGPoint(x: 329, y: 926), controlPoint1: CGPoint(x: 395, y: 795), controlPoint2: CGPoint(x: 315, y: 831))
            vase.addCurve(to: CGPoint(x: 554, y: 926), controlPoint1: CGPoint(x: 339, y: 1007), controlPoint2: CGPoint(x: 542, y: 1007))
            vase.addCurve(to: CGPoint(x: 500, y: 714), controlPoint1: CGPoint(x: 570, y: 831), controlPoint2: CGPoint(x: 488, y: 795))
            vase.close()
            vase.fill()
            UIColor(red: 0.42, green: 0.23, blue: 0.15, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 382, y: 701, width: 119, height: 22)).fill()
            context.setStrokeColor(UIColor(red: 0.17, green: 0.31, blue: 0.21, alpha: 1).cgColor)
            context.setLineWidth(6)
            for index in 0..<5 {
                let endX = CGFloat(200 + index * 130)
                let endY = CGFloat(300 + abs(index - 2) * 70)
                let stem = UIBezierPath()
                stem.move(to: CGPoint(x: 442, y: 712))
                stem.addQuadCurve(to: CGPoint(x: endX, y: endY), controlPoint: CGPoint(x: 450, y: 420))
                stem.stroke()
                for leaf in 0..<3 {
                    context.saveGState()
                    context.translateBy(x: (endX + 442) / 2 + CGFloat(leaf * 17 - 17),
                                        y: endY + CGFloat(leaf * 90 + 40))
                    context.rotate(by: CGFloat(index - 2) * 0.24 + CGFloat(leaf % 2 == 0 ? -0.55 : 0.55))
                    UIColor(red: 0.20 + CGFloat(index) * 0.025, green: 0.40 + CGFloat(leaf) * 0.04, blue: 0.28, alpha: 1).setFill()
                    UIBezierPath(ovalIn: CGRect(x: -48, y: -95, width: 96, height: 190)).fill()
                    context.restoreGState()
                }
            }
            UIColor(red: 0.94, green: 0.91, blue: 0.80, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 615, y: 990, width: 175, height: 58), cornerRadius: 6).fill()
            UIColor(red: 0.26, green: 0.43, blue: 0.40, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 627, y: 981, width: 168, height: 18), cornerRadius: 3).fill()
        }
    }
}

@main
final class PreviewAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: CameraScreen())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
