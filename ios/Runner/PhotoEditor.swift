import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PhotoAdjustments: Codable, Equatable {
    var exposure: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var quarterTurns: Int = 0
    var cropRatio: Double = 0 // 0 = original; crop is centered after rotation.
    var cropX: Double = 0.5
    var cropY: Double = 0.5
    var monochrome = false
}

enum PhotoRenderer {
    private static let context = CIContext()

    static func render(_ input: CIImage, adjustments: PhotoAdjustments) -> UIImage? {
        var image = input
        let angle = CGFloat(adjustments.quarterTurns % 4) * .pi / 2
        image = image.transformed(by: CGAffineTransform(rotationAngle: angle))
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
            image = image.cropped(to: rect)
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
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    static func jpeg(url: URL, adjustments: PhotoAdjustments) throws -> Data {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              let rendered = render(input, adjustments: adjustments),
              let data = rendered.jpegData(compressionQuality: 0.97) else {
            throw CameraFailure.invalidImage
        }
        return data
    }
}

struct PhotoEditorView: View {
    @ObservedObject var store: SessionStore
    let capture: SessionCapture
    @Environment(\.dismiss) private var dismiss
    @State private var adjustments: PhotoAdjustments
    @State private var preview: UIImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var busy = false
    @State private var error: String?
    @State private var previewInput: CIImage?

    init(store: SessionStore, capture: SessionCapture) {
        self.store = store
        self.capture = capture
        _adjustments = State(initialValue: capture.adjustments)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .frame(maxHeight: .infinity)
                } else { ProgressView().frame(maxHeight: .infinity) }
                HStack(spacing: 22) {
                    Button { adjustments.quarterTurns = (adjustments.quarterTurns + 1) % 4 } label: {
                        Label("旋转", systemImage: "rotate.left")
                    }
                    Button { adjustments.monochrome.toggle() } label: {
                        Label("黑白", systemImage: "circle.lefthalf.filled")
                    }.tint(adjustments.monochrome ? .yellow : .white)
                    Button("恢复原图") { adjustments = PhotoAdjustments() }
                }.font(.footnote)
                Picker("裁剪", selection: $adjustments.cropRatio) {
                    Text("原始").tag(0.0)
                    Text("1:1").tag(1.0)
                    Text("4:3").tag(4.0 / 3)
                    Text("3:4").tag(3.0 / 4)
                    Text("16:9").tag(16.0 / 9)
                }.pickerStyle(.segmented)
                if adjustments.cropRatio > 0 {
                    adjustmentSlider("裁剪位置 · 横", value: $adjustments.cropX, range: 0...1)
                    adjustmentSlider("裁剪位置 · 纵", value: $adjustments.cropY, range: 0...1)
                }
                adjustmentSlider("曝光", value: $adjustments.exposure, range: -2...2)
                adjustmentSlider("对比度", value: $adjustments.contrast, range: 0.5...1.5)
                adjustmentSlider("饱和度", value: $adjustments.saturation, range: 0...2)
                Text("完成后同步修改系统照片，原图可在系统照片中恢复。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding().background(.black)
            .navigationTitle("编辑").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "保存中…" : "完成") {
                        busy = true
                        Task {
                            do {
                                try await store.edit(capture, adjustments: adjustments)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                                busy = false
                            }
                        }
                    }.disabled(busy || previewInput == nil)
                }
            }
            .interactiveDismissDisabled(busy)
            .disabled(busy)
            .alert("无法保存修改", isPresented: Binding(get: { error != nil },
                set: { if !$0 { error = nil } })) {
                Button("好") { error = nil }
            } message: { Text(error ?? "") }
            .task {
                let image = await Task.detached {
                    MediaThumbnails.make(url: capture.originalURL, kind: .photo)
                }.value
                if let image { previewInput = CIImage(image: image) }
                schedulePreview()
            }
            .onChange(of: adjustments) { _ in schedulePreview() }
            .onChange(of: store.sessionID) { _ in dismiss() }
            .onDisappear { previewTask?.cancel() }
        }.preferredColorScheme(.dark)
    }

    private func adjustmentSlider(_ title: String, value: Binding<Double>,
                                  range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range).tint(.yellow)
        }
    }

    private func schedulePreview() {
        previewTask?.cancel()
        guard let input = previewInput else { return }
        let values = adjustments
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                PhotoRenderer.render(input, adjustments: values)
            }.value
            guard !Task.isCancelled else { return }
            preview = image
        }
    }
}
