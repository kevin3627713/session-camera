import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

public struct PhotoAdjustments: Codable, Equatable {
    public var exposure: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var quarterTurns: Int = 0
    public var cropRatio: Double = 0
    public var cropX: Double = 0.5
    public var cropY: Double = 0.5
    public var monochrome = false
    public init() {}
}

public enum PhotoRenderFailure: LocalizedError {
    case invalidImage
    public var errorDescription: String? { "无法处理这张照片。原图仍然保留。" }
}

/// This file is compiled directly into the iOS app and tested with Apple's
/// Core Image and ImageIO on macOS. The pixel/encoding path has no UI dependency.
public enum PhotoRendering {
    private static let context = CIContext()

    public static func cgImage(_ input: CIImage, adjustments: PhotoAdjustments) -> CGImage? {
        let orientations: [Int32] = [1, 8, 3, 6]
        let turns = (adjustments.quarterTurns % 4 + 4) % 4
        var image = input.oriented(forExifOrientation: orientations[turns])
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX,
                                                       y: -image.extent.minY))
        if adjustments.cropRatio > 0 {
            let bounds = image.extent
            let ratio = CGFloat(adjustments.cropRatio)
            let size: CGSize = bounds.width / bounds.height > ratio
                ? CGSize(width: bounds.height * ratio, height: bounds.height)
                : CGSize(width: bounds.width, height: bounds.width / ratio)
            let rect = CGRect(x: (bounds.width - size.width) * CGFloat(adjustments.cropX),
                              y: (bounds.height - size.height) * CGFloat(adjustments.cropY),
                              width: size.width, height: size.height)
            image = image.cropped(to: rect.integral.intersection(bounds))
        }
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = Float(adjustments.exposure)
        image = exposure.outputImage ?? image
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.contrast = Float(adjustments.contrast)
        color.saturation = adjustments.monochrome ? 0 : Float(adjustments.saturation)
        image = color.outputImage ?? image
        return context.createCGImage(image, from: image.extent)
    }

    public static func jpeg(url: URL, adjustments: PhotoAdjustments) throws -> Data {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              let rendered = cgImage(input, adjustments: adjustments) else {
            throw PhotoRenderFailure.invalidImage
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw PhotoRenderFailure.invalidImage
        }
        CGImageDestinationAddImage(destination, rendered, [
            kCGImageDestinationLossyCompressionQuality: 0.97,
            kCGImagePropertyOrientation: 1
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoRenderFailure.invalidImage }
        return data as Data
    }
}
