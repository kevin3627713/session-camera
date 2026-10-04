import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum PhotoRenderer {
    static func render(_ input: CIImage, adjustments: PhotoAdjustments) -> UIImage? {
        guard let image = PhotoRendering.cgImage(input, adjustments: adjustments) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
    static func jpeg(url: URL, adjustments: PhotoAdjustments) throws -> Data {
        try PhotoRendering.jpeg(url: url, adjustments: adjustments)
    }
}

private enum EditorTool: String, CaseIterable {
    case adjust = "调整", filters = "滤镜", crop = "裁剪"
    var symbol: String {
        switch self {
        case .adjust: return "dial.low"
        case .filters: return "camera.filters"
        case .crop: return "crop.rotate"
        }
    }
}

private enum PhotoAdjustment: String, CaseIterable {
    case exposure = "曝光", contrast = "对比度", saturation = "饱和度"
    var symbol: String {
        switch self {
        case .exposure: return "plusminus.circle"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop.halffull"
        }
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
    @State private var tool = EditorTool.adjust
    @State private var adjustment = PhotoAdjustment.exposure
    @State private var cropOrigin: CGPoint?
    @State private var originalThumbnail: UIImage?
    @State private var monoThumbnail: UIImage?

    init(store: SessionStore, capture: SessionCapture) {
        self.store = store
        self.capture = capture
        _adjustments = State(initialValue: capture.adjustments)
        #if CAMERA_UI_PREVIEW
        if CameraUIPreview.screen == "crop" {
            _tool = State(initialValue: .crop)
            var crop = capture.adjustments
            crop.cropRatio = 1
            _adjustments = State(initialValue: crop)
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar.frame(height: 44)
            imageArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            toolControls.frame(height: 122)
            toolBar.frame(height: 54)
            bottomBar.frame(height: 44)
        }
        .background(.black).foregroundStyle(.white)
        .preferredColorScheme(.dark).statusBarHidden()
        .buttonStyle(.plain)
        .interactiveDismissDisabled()
        .disabled(busy)
        .overlay {
            if busy {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("正在保存").font(.system(size: 14))
                }.padding(25).background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .alert("无法保存修改", isPresented: Binding(get: { error != nil },
            set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
        .task {
            let image = await Task.detached {
                MediaThumbnails.make(url: capture.originalURL, kind: .photo, maxPixelSize: 1600)
            }.value
            if let image {
                previewInput = CIImage(image: image)
                originalThumbnail = image
                if let input = previewInput {
                    monoThumbnail = await Task.detached {
                        var values = PhotoAdjustments()
                        values.monochrome = true
                        return PhotoRenderer.render(input, adjustments: values)
                    }.value
                }
            }
            schedulePreview()
        }
        .onChange(of: adjustments) { _ in schedulePreview() }
        .onChange(of: store.sessionID) { _ in dismiss() }
        .onDisappear { previewTask?.cancel() }
    }

    private var topBar: some View {
        HStack {
            if tool == .crop {
                Button {
                    adjustments.quarterTurns = (adjustments.quarterTurns + 1) % 4
                } label: {
                    Image(systemName: "rotate.left").font(.system(size: 21))
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("向左旋转 90 度")
            } else { Color.clear.frame(width: 44, height: 44) }
            Spacer()
            Button("还原") { adjustments = PhotoAdjustments() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(adjustments == PhotoAdjustments() ? .gray : cameraYellow)
                .disabled(adjustments == PhotoAdjustments())
            Spacer()
            if tool == .crop {
                Menu {
                    ratioMenu("原始", ratio: 0)
                    ratioMenu("正方形", ratio: 1)
                    ratioMenu("4:3", ratio: 4.0 / 3)
                    ratioMenu("3:4", ratio: 3.0 / 4)
                    ratioMenu("16:9", ratio: 16.0 / 9)
                } label: {
                    Image(systemName: "aspectratio").font(.system(size: 21))
                        .frame(width: 44, height: 44)
                }.accessibilityLabel("裁剪比例")
            } else { Color.clear.frame(width: 44, height: 44) }
        }.padding(.horizontal, 10)
    }

    private var imageArea: some View {
        GeometryReader { geometry in
            ZStack {
                if let preview {
                    let factor = min(geometry.size.width / preview.size.width,
                                     geometry.size.height / preview.size.height)
                    let fitted = CGSize(width: preview.size.width * factor, height: preview.size.height * factor)
                    Image(uiImage: preview).resizable().scaledToFit()
                        .frame(width: fitted.width, height: fitted.height)
                        .overlay {
                            if tool == .crop {
                                ZStack {
                                    CameraGrid().stroke(.white.opacity(0.6), lineWidth: 0.5)
                                    CropCorners().stroke(.white, lineWidth: 2.5)
                                    Rectangle().stroke(.white.opacity(0.8), lineWidth: 0.6)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { gesture in
                                guard tool == .crop, adjustments.cropRatio > 0 else { return }
                                if cropOrigin == nil { cropOrigin = CGPoint(x: adjustments.cropX, y: adjustments.cropY) }
                                adjustments.cropX = min(1, max(0,
                                    Double(cropOrigin!.x - gesture.translation.width / max(1, fitted.width))))
                                adjustments.cropY = min(1, max(0,
                                    Double(cropOrigin!.y + gesture.translation.height / max(1, fitted.height))))
                            }
                            .onEnded { _ in cropOrigin = nil })
                } else { ProgressView().tint(.white) }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.padding(.horizontal, tool == .crop ? 16 : 0)
    }

    @ViewBuilder private var toolControls: some View {
        switch tool {
        case .adjust:
            VStack(spacing: 8) {
                Text(adjustment.rawValue).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 26) {
                    ForEach(PhotoAdjustment.allCases, id: \.self) { item in
                        Button { adjustment = item; UISelectionFeedbackGenerator().selectionChanged() } label: {
                            ZStack {
                                Circle().stroke(item == adjustment ? cameraYellow : .gray.opacity(0.6), lineWidth: 1.5)
                                Image(systemName: item.symbol).font(.system(size: 23, weight: .light))
                            }
                            .frame(width: 44, height: 44)
                            .foregroundStyle(item == adjustment ? cameraYellow : .white)
                            .background(item == adjustment ? cameraYellow.opacity(0.08) : .clear, in: Circle())
                        }.accessibilityLabel(item.rawValue)
                    }
                }
                VStack(spacing: 0) {
                    Text(String(Int(dialValue.wrappedValue.rounded())))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(cameraYellow)
                    AdjustmentRuler(value: dialValue, range: -100...100, step: 5, defaultValue: 0)
                        .frame(height: 34).padding(.horizontal, 34)
                }
            }
        case .filters:
            HStack(spacing: 18) {
                filterChoice("原片", image: originalThumbnail, mono: false)
                filterChoice("单色", image: monoThumbnail, mono: true)
            }.frame(maxWidth: .infinity)
        case .crop:
            VStack(spacing: 22) {
                HStack(spacing: 20) {
                    ratioButton("原始", ratio: 0)
                    ratioButton("正方形", ratio: 1)
                    ratioButton("4:3", ratio: 4.0 / 3)
                    ratioButton("3:4", ratio: 3.0 / 4)
                    ratioButton("16:9", ratio: 16.0 / 9)
                }.font(.system(size: 12, weight: .medium))
                Text(adjustments.cropRatio == 0 ? "选择比例以裁剪照片" : "拖动照片调整裁剪位置")
                    .font(.system(size: 12)).foregroundStyle(.gray)
            }.frame(maxWidth: .infinity)
        }
    }

    private var toolBar: some View {
        HStack(spacing: 55) {
            ForEach(EditorTool.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tool = item }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 23, weight: .regular))
                        Text(item.rawValue).font(.system(size: 10, weight: .medium))
                    }.frame(width: 48, height: 52)
                        .foregroundStyle(tool == item ? cameraYellow : .white)
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        HStack {
            Button("取消") { dismiss() }.foregroundStyle(.white)
                .frame(minWidth: 52, minHeight: 44, alignment: .leading)
            Spacer()
            Button("完成") { save() }.foregroundStyle(cameraYellow)
                .fontWeight(.semibold).frame(minWidth: 52, minHeight: 44, alignment: .trailing)
                .disabled(previewInput == nil)
        }.font(.system(size: 17)).padding(.horizontal, 20)
    }

    private var dialValue: Binding<Double> {
        Binding(get: {
            switch adjustment {
            case .exposure: return adjustments.exposure * 50
            case .contrast: return (adjustments.contrast - 1) * 200
            case .saturation: return (adjustments.saturation - 1) * 100
            }
        }, set: { value in
            switch adjustment {
            case .exposure: adjustments.exposure = value / 50
            case .contrast: adjustments.contrast = 1 + value / 200
            case .saturation: adjustments.saturation = 1 + value / 100
            }
        })
    }

    private func filterChoice(_ title: String, image: UIImage?, mono: Bool) -> some View {
        Button { adjustments.monochrome = mono } label: {
            VStack(spacing: 8) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 68, height: 86).clipped()
                        .overlay(Rectangle().stroke(adjustments.monochrome == mono ? cameraYellow : .clear, lineWidth: 2))
                }
                Text(title).font(.system(size: 12))
                    .foregroundStyle(adjustments.monochrome == mono ? cameraYellow : .white)
            }
        }
    }

    private func ratioButton(_ title: String, ratio: Double) -> some View {
        Button { adjustments.cropRatio = ratio } label: {
            Text(title).foregroundStyle(adjustments.cropRatio == ratio ? cameraYellow : .white)
                .padding(.vertical, 12)
        }
    }

    private func ratioMenu(_ title: String, ratio: Double) -> some View {
        Button { adjustments.cropRatio = ratio } label: {
            if adjustments.cropRatio == ratio { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private func save() {
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

struct CropCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 22
        for (point, horizontal, vertical) in [
            (CGPoint(x: rect.minX, y: rect.minY), CGFloat(1), CGFloat(1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGFloat(-1), CGFloat(1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGFloat(1), CGFloat(-1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGFloat(-1), CGFloat(-1))
        ] {
            path.move(to: CGPoint(x: point.x + horizontal * length, y: point.y))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + vertical * length))
        }
        return path
    }
}
