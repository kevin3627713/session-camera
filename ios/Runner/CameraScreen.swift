import AVFoundation
import AVKit
import SwiftUI
import Photos
import LocalAuthentication
import WidgetKit

struct CameraScreen: View {
    @StateObject private var engine = CameraEngine()
    @StateObject private var store = SessionStore()
    @State private var mode = CameraMode.photo
    @State private var flash = AVCaptureDevice.FlashMode.auto
    @State private var timerSeconds = 0
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var exposure = 0.0
    @State private var controlsVisible = false
    @State private var selectedControl: CaptureControl?
    @State private var galleryVisible = false
    @State private var guideVisible = false
    @State private var active = true
    @State private var setupDone = false
    @State private var guidedAccess = UIAccessibility.isGuidedAccessEnabled
    @State private var recordingStarted: Date?
    @State private var shutterPulse = false
    @AppStorage("showGrid") private var grid = false
    @AppStorage("remindGuidedAccess") private var remindGuidedAccess = false
    @AppStorage("completedSetup") private var completedSetup = false
    @AppStorage("captureAspect") private var aspectRaw = CaptureAspect.wide.rawValue

    private var aspect: CaptureAspect { CaptureAspect(rawValue: aspectRaw) ?? .wide }
    private var overlaysPreview: Bool { mode == .video || aspect == .wide }

    var body: some View {
        GeometryReader { geometry in
            let layout = CameraLayout(size: geometry.size, insets: geometry.safeAreaInsets,
                                      video: mode == .video, aspect: aspect)
            ZStack(alignment: .top) {
                Color.black
                viewfinder(lensPadding: layout.lensBottom)
                    .frame(width: layout.previewWidth, height: layout.previewHeight)
                    .position(x: geometry.size.width / 2, y: layout.previewTop + layout.previewHeight / 2)
                VStack(spacing: 0) {
                    header.frame(height: 44).padding(.top, layout.headerTop)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if controlsVisible { additionalControls }
                    else { modeSelector }
                    shutterRow.frame(height: layout.shutterHeight)
                    Color.clear.frame(height: layout.bottomInset + layout.bottomSpacing)
                }
            }
        }
        .ignoresSafeArea()
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .statusBarHidden()
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $galleryVisible) {
            SessionGallery(store: store).id(store.sessionID)
        }
        .sheet(isPresented: $guideVisible) {
            GuidedAccessGuide(isEnabled: guidedAccess, remind: $remindGuidedAccess)
        }
        .alert("借拍", isPresented: Binding(get: { store.message != nil || engine.error != nil },
            set: { if !$0 { store.message = nil; engine.error = nil } })) {
            Button("好") { store.message = nil; engine.error = nil }
            Button("应用权限设置") { openAppSettings() }
        } message: { Text(store.message ?? engine.error ?? "") }
        .task {
            #if CAMERA_UI_PREVIEW
            if CameraUIPreview.enabled {
                store.loadUIPreview()
                engine.loadUIPreview()
                mode = CameraUIPreview.screen == "video" ? .video : .photo
                controlsVisible = CameraUIPreview.screen == "controls"
                selectedControl = controlsVisible ? .exposure : nil
                galleryVisible = ["gallery", "editor", "crop", "grid"].contains(CameraUIPreview.screen)
                setupDone = true
                if !galleryVisible { CameraUIPreview.reportReady(CameraUIPreview.screen) }
                return
            }
            #endif
            engine.onPhoto = { data, ticket in store.receive(photo: data, ticket: ticket) }
            engine.onVideo = { url, ticket in store.receive(movie: url, ticket: ticket) }
            await store.prepareLibrary()
            engine.start()
            setupDone = true
            if !completedSetup || (remindGuidedAccess && !guidedAccess) {
                guideVisible = true
                completedSetup = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            #if CAMERA_UI_PREVIEW
            if CameraUIPreview.enabled { return }
            #endif
            active = false
            countdownTask?.cancel()
            countdown = 0
            galleryVisible = false
            guideVisible = false
            store.resetSession()
            engine.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            #if CAMERA_UI_PREVIEW
            if CameraUIPreview.enabled { return }
            #endif
            guidedAccess = UIAccessibility.isGuidedAccessEnabled
            guard setupDone else { return }
            store.refreshPermissions()
            if !active {
                active = true
                engine.start()
                Task { await store.retryPending() }
                if remindGuidedAccess && !guidedAccess { guideVisible = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)) { _ in
            guidedAccess = UIAccessibility.isGuidedAccessEnabled
            if guidedAccess { guideVisible = false }
        }
        .onChange(of: engine.recording) { value in recordingStarted = value ? Date() : nil }
        .onChange(of: exposure) { value in engine.setExposure(Float(value)) }
    }

    private var header: some View {
        ZStack {
            HStack {
            HStack(spacing: -7) {
            Button {
                flash = flash == .off ? .auto : flash == .auto ? .on : .off
            } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.65), lineWidth: 1)
                    if flash == .on { Circle().fill(cameraYellow) }
                    Image(systemName: flash == .off ? "bolt.slash.fill" : "bolt.fill")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(flash == .on ? .black : .white)
                }.frame(width: 25, height: 25)
                    .frame(width: 44, height: 44)
            }.disabled(mode == .video || engine.isFront || engine.recording || countdown > 0)
                .accessibilityLabel("闪光灯")
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true; selectedControl = .exposure }
            } label: {
                Image(systemName: "plusminus.circle").font(.system(size: 25, weight: .ultraLight))
                    .foregroundStyle(exposure == 0 ? .white.opacity(0.7) : cameraYellow)
                    .frame(width: 44, height: 44)
            }.disabled(engine.recording || engine.capturing || countdown > 0).accessibilityLabel("曝光补偿")
            }
            Spacer()
            Button { guideVisible = true } label: {
                Image(systemName: guidedAccess ? "lock.circle.fill" : "lock.circle")
                    .font(.system(size: 25, weight: .ultraLight))
                    .foregroundStyle(guidedAccess ? cameraYellow : .white)
                    .frame(width: 44, height: 44)
            }.accessibilityLabel(guidedAccess ? "引导式访问已开启" : "相册已隔离，查看引导式访问")
            }
            if !engine.recording {
            Button { toggleControls() } label: {
                Image(systemName: controlsVisible ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color(white: 0.13), in: Circle())
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("拍摄选项")
            } else if let started = recordingStarted {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(started)))
                    Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }.padding(.horizontal, 2)
    }

    private func viewfinder(lensPadding: CGFloat) -> some View {
            ZStack(alignment: .bottom) {
                #if CAMERA_UI_PREVIEW
                if CameraUIPreview.enabled {
                    GeometryReader { bounds in
                        Image(uiImage: CameraUIPreview.image).resizable().scaledToFill()
                            .frame(width: bounds.size.width, height: bounds.size.height).clipped()
                    }
                } else { CameraPreview(engine: engine) }
                #else
                CameraPreview(engine: engine)
                #endif
                if grid { CameraGrid().stroke(.white.opacity(0.4), lineWidth: 0.5).allowsHitTesting(false) }
                if mode == .photo && aspect == .wide {
                    CropCorners().stroke(.white.opacity(0.65), lineWidth: 0.6).allowsHitTesting(false)
                }
                if !engine.ready {
                    VStack(spacing: 12) {
                        Image(systemName: "camera").font(.system(size: 30, weight: .light))
                        Button("轻点启动相机") { engine.start() }.font(.system(size: 14))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if countdown > 0 {
                    Text("\(countdown)").font(.system(size: 92, weight: .thin))
                        .shadow(radius: 8).frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
                Color.white.opacity(shutterPulse ? 0.6 : 0).allowsHitTesting(false)
                VStack(spacing: 8) {
                    if timerSeconds > 0 && mode == .photo {
                        Label("\(timerSeconds) 秒", systemImage: "timer")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(cameraYellow)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                    if !engine.isFront {
                        HStack(spacing: -4) {
                            ForEach(engine.lenses) { lens in
                                Button { engine.selectLens(lens.id) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                                        Text(lens.id == engine.selectedLens ? selectedZoomLabel : lens.label)
                                        if lens.id == engine.selectedLens { Text("×").font(.system(size: 10, weight: .semibold)) }
                                    }
                                    .font(.system(size: lens.id == engine.selectedLens ? 16 : 13, weight: .semibold))
                                    .foregroundStyle(lens.id == engine.selectedLens ? cameraYellow : .white)
                                    .frame(width: lens.id == engine.selectedLens ? 42 : 32,
                                           height: lens.id == engine.selectedLens ? 42 : 32)
                                    .background(.black.opacity(lens.id == engine.selectedLens ? 0.28 : 0.35), in: Circle())
                                    .frame(width: 44, height: 44)
                                }.disabled(engine.recording || engine.capturing || countdown > 0)
                                    .accessibilityLabel("\(lens.label) 倍镜头")
                            }
                        }.background(.black.opacity(0.16), in: Capsule())
                    }
                }.padding(.bottom, lensPadding)
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 32).onEnded { gesture in
                guard !engine.recording, !engine.capturing, countdown == 0 else { return }
                if abs(gesture.translation.width) > abs(gesture.translation.height) {
                    changeMode(gesture.translation.width < 0 ? .photo : .video)
                } else if gesture.translation.height < -35 {
                    withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
                } else if gesture.translation.height > 35 {
                    withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false; selectedControl = nil }
                }
            })
    }

    private var additionalControls: some View {
        VStack(spacing: 0) {
            if let selectedControl {
                HStack(spacing: 18) {
                    Button { withAnimation { self.selectedControl = nil } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                            .frame(width: 36, height: 44)
                    }.accessibilityLabel("返回拍摄选项")
                    switch selectedControl {
                    case .flash:
                        optionButton("自动", selected: flash == .auto) { flash = .auto }
                        optionButton("打开", selected: flash == .on) { flash = .on }
                        optionButton("关闭", selected: flash == .off) { flash = .off }
                    case .timer:
                        optionButton("关闭", selected: timerSeconds == 0) { timerSeconds = 0 }
                        optionButton("3 秒", selected: timerSeconds == 3) { timerSeconds = 3 }
                        optionButton("10 秒", selected: timerSeconds == 10) { timerSeconds = 10 }
                    case .exposure:
                        Text(String(format: "%+.1f", exposure)).font(.system(size: 12)).monospacedDigit()
                            .foregroundStyle(cameraYellow).frame(width: 36)
                        AdjustmentRuler(value: $exposure, range: -2...2, step: 0.1, defaultValue: 0)
                            .frame(height: 42)
                    case .aspect:
                        ForEach(CaptureAspect.allCases, id: \.rawValue) { item in
                            optionButton(item.rawValue, selected: aspect == item) { aspectRaw = item.rawValue }
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).frame(height: 50)
            } else {
                HStack {
                    captureControl("bolt", active: flash != .off, label: "闪光灯") { selectedControl = .flash }
                        .disabled(mode == .video || engine.isFront)
                    Spacer()
                    captureControl("plusminus.circle", active: exposure != 0, label: "曝光") { selectedControl = .exposure }
                    Spacer()
                    Button { selectedControl = .aspect } label: {
                        Text(aspect.rawValue).font(.system(size: 11, weight: .semibold))
                            .frame(width: 36, height: 36).background(Color(white: 0.18), in: Circle())
                            .frame(width: 44, height: 44)
                    }.disabled(mode == .video).accessibilityLabel("照片比例")
                    Spacer()
                    captureControl("timer", active: timerSeconds != 0, label: "定时") { selectedControl = .timer }
                        .disabled(mode == .video)
                    Spacer()
                    captureControl("grid", active: grid, label: "网格") { grid.toggle() }
                }.padding(.horizontal, 30).frame(height: 50)
            }
            if !store.photosAllowed {
                Button("照片权限未开启 · 前往设置") { openAppSettings() }
                    .font(.caption).foregroundStyle(.orange)
            }
            if store.pendingRecoveryCount > 0 {
                Button("\(store.pendingRecoveryCount) 项待保存 · 重试") { Task { await store.retryPending() } }
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(.bottom, 2).background(.black.opacity(0.9))
            .disabled(engine.recording || engine.capturing || countdown > 0)
    }

    private var modeSelector: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Button("视频") { changeMode(.video) }.frame(width: 56, height: 44)
                    .foregroundStyle(mode == .video ? cameraYellow : .white)
                Button("照片") { changeMode(.photo) }.frame(width: 56, height: 44)
                    .foregroundStyle(mode == .photo ? cameraYellow : .white)
            }
            .font(.system(size: 13, weight: .semibold))
            .offset(x: geometry.size.width / 2 - (mode == .photo ? 84 : 28))
        }.frame(height: 44).clipped()
            .background(overlaysPreview ? Color.clear : .black)
            .disabled(engine.recording || engine.capturing || countdown > 0 || !engine.ready)
    }

    private var shutterRow: some View {
        ZStack {
            HStack {
            Button { galleryVisible = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1))
                    if let thumbnail = store.captures.last?.thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else { Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.gray) }
                }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 4))
            }.accessibilityLabel("查看本次拍摄的照片").disabled(engine.recording || countdown > 0)
            Spacer()
            Button { engine.switchCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24, weight: .regular)).frame(width: 48, height: 48)
                    .background(.black.opacity(0.4), in: Circle())
            }.disabled(engine.recording || engine.capturing || countdown > 0)
                .accessibilityLabel("切换前后摄像头")
            }.padding(.horizontal, 20)
            Button(action: shutter) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                    if engine.recording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 32, height: 32)
                    } else {
                        Circle().fill(mode == .photo ? .white : .red).frame(width: 60, height: 60)
                    }
                }
                .scaleEffect(engine.capturing ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: engine.capturing)
            }.disabled(!engine.ready || engine.capturing || countdown > 0)
                .accessibilityLabel(mode == .photo ? "拍照" : engine.recording ? "停止录像" : "开始录像")
        }.background(overlaysPreview ? Color.clear : .black)
    }

    private var selectedZoomLabel: String {
        let optical = Double(engine.lenses.first { $0.id == engine.selectedLens }?.label ?? "1") ?? 1
        let value = optical * Double(engine.zoom)
        return abs(value.rounded() - value) < 0.05 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private func changeMode(_ newMode: CameraMode) {
        guard mode != newMode, !engine.recording, !engine.capturing, countdown == 0 else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.22)) {
            mode = newMode
            controlsVisible = false
            selectedControl = nil
        }
        engine.setMode(newMode)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
            selectedControl = nil
        }
    }

    private func captureControl(_ symbol: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(active ? .black : .white).frame(width: 36, height: 36)
                .background(active ? cameraYellow : Color(white: 0.18), in: Circle())
                .frame(width: 44, height: 48)
        }.accessibilityLabel(label).accessibilityValue(active ? "开启" : "关闭")
    }

    private func optionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? cameraYellow : .white).frame(minWidth: 46, minHeight: 44)
    }

    private func shutter() {
        let ticket = store.issueTicket()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if mode == .video { engine.toggleVideo(ticket: ticket); return }
        if timerSeconds == 0 { capturePhoto(ticket); return }
        countdownTask = Task {
            for second in stride(from: timerSeconds, through: 1, by: -1) {
                guard !Task.isCancelled, active else { countdown = 0; return }
                countdown = second
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { countdown = 0; return }
            }
            countdown = 0
            guard !Task.isCancelled, active else { return }
            capturePhoto(ticket)
        }
    }

    private func capturePhoto(_ ticket: CaptureTicket) {
        engine.takePhoto(ticket: ticket, flash: flash, aspect: aspect)
        shutterPulse = true
        withAnimation(.easeOut(duration: 0.18)) { shutterPulse = false }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

private enum CaptureControl { case flash, timer, exposure, aspect }
let cameraYellow = Color(red: 1, green: 0.83, blue: 0.04)

/// The supplied phone reference uses 16:9 photos behind the shutter controls.
/// Other formats retain their aspect and fit above the same fixed control dock.
struct CameraLayout {
    let previewWidth: CGFloat
    let previewHeight: CGFloat
    let previewTop: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let bottomSpacing: CGFloat
    let shutterHeight: CGFloat
    let lensBottom: CGFloat
    let headerTop: CGFloat

    init(size: CGSize, insets: EdgeInsets, video: Bool, aspect: CaptureAspect) {
        let windowInsets = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
        topInset = max(insets.top, windowInsets.top)
        bottomInset = max(insets.bottom, windowInsets.bottom)
        headerTop = max(0, topInset - 14)
        shutterHeight = 80
        bottomSpacing = size.height < 700 ? 14 : 43
        let dock = 44 + shutterHeight + bottomInset + bottomSpacing
        if video || aspect == .wide {
            previewTop = max(44, topInset + 38)
            previewHeight = min(size.width * 16 / 9, size.height - previewTop - max(12, bottomInset))
            previewWidth = previewHeight * 9 / 16
            lensBottom = max(14, previewTop + previewHeight - (size.height - dock) + 14)
        } else {
            let available = max(1, size.height - topInset - 44 - dock)
            previewHeight = min(size.width / CGFloat(aspect.portraitRatio), available)
            previewWidth = min(size.width, previewHeight * CGFloat(aspect.portraitRatio))
            previewTop = topInset + 44 + max(0, (available - previewHeight) / 2)
            lensBottom = 16
        }
    }
}

/// A centered tick dial, shared by exposure compensation and the photo editor.
/// Moving the scale left increases the value, as in the system editor.
struct AdjustmentRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 7
            Canvas { context, size in
                let count = Int(((range.upperBound - range.lowerBound) / step).rounded())
                for index in 0...count {
                    let tick = range.lowerBound + Double(index) * step
                    let x: CGFloat = size.width / 2 + CGFloat((tick - value) / step) * spacing
                    guard x >= 0, x <= size.width else { continue }
                    let major = index % 5 == 0
                    let isDefault = abs(tick - defaultValue) < step / 2
                    let height: CGFloat = major ? 18 : 10
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: (size.height - height) / 2))
                    path.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
                    context.stroke(path, with: .color(isDefault ? .white : .gray.opacity(major ? 0.8 : 0.5)), lineWidth: 1)
                }
                var indicator = Path()
                indicator.move(to: CGPoint(x: size.width / 2, y: 5))
                indicator.addLine(to: CGPoint(x: size.width / 2, y: size.height - 5))
                context.stroke(indicator, with: .color(cameraYellow), lineWidth: 2)
            }
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if dragStart == nil { dragStart = value }
                    value = min(range.upperBound, max(range.lowerBound,
                        (dragStart ?? value) - Double(gesture.translation.width / spacing) * step))
                }
                .onEnded { _ in dragStart = nil })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
            .accessibilityElement()
            .accessibilityLabel("调整数值")
            .accessibilityValue(String(format: "%.1f", value))
            .accessibilityAdjustableAction { direction in
                value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
            }
            .frame(width: geometry.size.width)
        }
    }
}

struct CameraGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
            path.move(to: CGPoint(x: rect.width * fraction, y: 0))
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
            path.move(to: CGPoint(x: 0, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        return path
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    let focusMark = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        focusMark.layer.borderColor = UIColor.systemYellow.cgColor
        focusMark.layer.borderWidth = 1
        focusMark.isUserInteractionEnabled = false
        focusMark.alpha = 0
        addSubview(focusMark)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    func showFocus(_ point: CGPoint, locked: Bool) {
        focusMark.frame = CGRect(x: point.x - 36, y: point.y - 36, width: 72, height: 72)
        focusMark.alpha = 1
        if !locked {
            UIView.animate(withDuration: 0.5, delay: 1, options: [.beginFromCurrentState]) {
                self.focusMark.alpha = 0
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var engine: CameraEngine
    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.previewLayer.session = engine.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator,
                                                        action: #selector(Coordinator.tap(_:))))
        view.addGestureRecognizer(UILongPressGestureRecognizer(target: context.coordinator,
                                                              action: #selector(Coordinator.hold(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator,
                                                          action: #selector(Coordinator.pinch(_:))))
        return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = engine.isFront
        }
    }

    final class Coordinator: NSObject {
        let engine: CameraEngine
        private var startingZoom: CGFloat = 1
        init(engine: CameraEngine) { self.engine = engine }
        @objc func tap(_ gesture: UITapGestureRecognizer) { focus(gesture, lock: false) }
        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { focus(gesture, lock: true) }
        }
        private func focus(_ gesture: UIGestureRecognizer, lock: Bool) {
            guard let view = gesture.view as? PreviewSurface else { return }
            let point = gesture.location(in: view)
            engine.focus(at: view.previewLayer.captureDevicePointConverted(fromLayerPoint: point), lock: lock)
            view.showFocus(point, locked: lock)
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began { startingZoom = engine.zoom }
            if gesture.state == .changed { engine.setZoom(startingZoom * gesture.scale) }
        }
    }
}

struct GuidedAccessGuide: View {
    let isEnabled: Bool
    @Binding var remind: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var photoWidgetSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(isEnabled ? "引导式访问已开启" : "相册隔离已生效", systemImage: isEnabled ? "lock.fill" : "shield.fill")
                        .foregroundStyle(.green)
                    Text("借拍只显示本次打开期间拍摄的内容，照片及修改自动同步到系统照片。退到后台后开始新的拍摄。")
                }
                Section("交给别人前") {
                    Text("引导式访问可将手机锁在借拍里，防止退出后打开系统照片或其他应用。")
                    Text("首次：系统设置 → 辅助功能 → 引导式访问，开启并设置密码、Face ID 和辅助功能快捷键。")
                    Text("每次：进入借拍后连按三下侧边按钮（有 Home 键的机型连按三下 Home），选择引导式访问并开始。")
                    Text("退出：使用侧边按钮及你的引导式访问密码或 Face ID，按系统提示结束。")
                }
                Section("打开借拍时自动开启") {
                    Text("先完成借拍的相机及照片权限授权，并手动测试一次引导式访问和退出。")
                    Text("快捷指令 → 自动化 → App → 选择借拍 → 被打开 → 立即运行。添加「开始引导式访问」动作并保存。")
                    Text("这项自动化由你在系统中配置。相机右上角的黄色实心锁表示引导式访问已开启；也可以点按图标查看状态。未开启时请手动启动。")
                }
                Section {
                    Toggle("每次打开时提醒开启引导式访问", isOn: $remind)
                }
                Section("照片权限") {
                    Text("建议选择「有限访问」：新拍照片仍可保存和编辑，也不会在借拍中显示你的其他照片。")
                    Text("仅添加照片权限可以保存新照片，但不能同步修改原记录。编辑时 iOS 可能要求你确认允许修改。")
                }
                Section("主屏小组件（实验）") {
                    Text("长按小组件 → 编辑小组件，即可切换透明、空白、磨砂、普通背景和随机相册照片，不需要删除重放。旧版四种预设均保留并可编辑。")
                    Text("默认点击不打开应用；可以在小组件设置中改成打开借拍。照片样式可分别选择相册/文件夹、更换周期和独立编号。")
                    Text("透明样式尝试透出真实壁纸。可移动小组件或切换壁纸检查效果；若显示普通底色，表示当前系统没有应用透明设置。")
                    Text("空白透明仍占主屏网格。小组件的系统名称标签由主屏设置控制。")
                    Button("照片小组件权限与刷新（机主验证）") { photoWidgetSettings = true }
                }
            }.navigationTitle("安心借拍").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("开始拍摄") { dismiss() } } }
        }.preferredColorScheme(.dark)
            .sheet(isPresented: $photoWidgetSettings) { PhotoWidgetOwnerSettings() }
    }
}

private struct PhotoWidgetOwnerSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false
    @State private var busy = false
    @State private var message: String?
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        NavigationStack {
            List {
                if !unlocked {
                    Section {
                        Label("照片小组件设置需要机主验证", systemImage: "lock.fill")
                        Text("用 Face ID、Touch ID 或设备密码验证后，才可管理照片访问。")
                        Button(busy ? "正在验证…" : "验证机主身份") { Task { await authenticate() } }.disabled(busy)
                        if let message { Text(message).foregroundStyle(.secondary) }
                    }
                } else {
                    Section("照片访问") {
                        Text(status == .authorized ? "当前为完整照片访问，可选择相册和文件夹。" :
                             status == .limited ? "当前为有限照片访问，小组件可选择已授权照片；无法读取相册/文件夹目录。" : "尚未允许读取照片。")
                        Text("使用相机仍只需有限权限。要按相册或文件夹随机展示，请在系统设置中将借拍的照片访问改成完整访问。")
                        if status == .notDetermined {
                            Button("申请照片访问") {
                                PHPhotoLibrary.requestAuthorization(for: .readWrite) { value in
                                    DispatchQueue.main.async { status = value; WidgetCenter.shared.reloadAllTimelines() }
                                }
                            }
                        }
                        Button("打开借拍的系统权限设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Section("每个小组件分别设置") {
                        Text("回到主屏幕，长按小组件 → 编辑小组件 → 样式选择随机相册照片。选择来源、5～10080 分钟的周期，以及这个小组件自己的独立编号。")
                        Text("编号会自动提供。复制小组件或需要独立随机序列时，选择一个新编号；来源相同的两个组件偶尔抽到同一张照片属于正常随机结果。")
                        Text("系统控制刷新时间，可能延后；照片在 iCloud 中且暂时无法下载时会显示提示。")
                        Button("刷新照片小组件") {
                            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                            WidgetCenter.shared.reloadAllTimelines()
                            message = "已请求系统刷新小组件。"
                        }
                        if let message { Text(message).foregroundStyle(.secondary) }
                    }
                    Section("显示范围") {
                        Text("所选照片会显示在主屏幕。这个功能只在小组件读取来源，不会把已有照片加入借拍的本次相册。默认点击小组件不打开任何应用。")
                    }
                }
            }.navigationTitle("照片小组件").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task { await authenticate() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in unlocked = false }
    }

    @MainActor private func authenticate() async {
        guard !busy, !unlocked else { return }
        busy = true
        defer { busy = false }
        let context = LAContext()
        do {
            unlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "管理借拍照片小组件的访问权限")
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            message = nil
        } catch {
            unlocked = false
            message = "未完成机主验证，可以稍后重试。"
        }
    }
}

struct SessionGallery: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var editing: SessionCapture?
    @State private var confirmHide = false
    @State private var chromeVisible = true
    @State private var infoVisible = false
    @State private var gridVisible = false
    @State private var favoriteBusy = false
    @State private var error: String?
    private let blue = Color(red: 0, green: 0.48, blue: 1)
    private let controlFill = Color(white: 0.96)

    var body: some View {
        VStack(spacing: 0) {
            if chromeVisible { header.frame(height: 38) }
            ZStack(alignment: .bottom) {
                if store.captures.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(.gray)
                        Text("本次还没有照片").font(.system(size: 19, weight: .semibold))
                        Text("拍摄后可在这里查看").font(.system(size: 14)).foregroundStyle(.gray)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $selected) {
                        ForEach(store.captures) { item in
                            SessionMediaView(capture: item, isSelected: item.id == selected,
                                onTap: { withAnimation(.easeInOut(duration: 0.18)) { chromeVisible.toggle() } })
                                .tag(Optional(item.id))
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                }
                if chromeVisible, let item = current {
                    VStack(spacing: 6) {
                        saveStatus(item)
                        filmstrip
                    }.padding(.bottom, 8)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if chromeVisible, let item = current { bottomBar(item).frame(height: 54) }
        }
        .background(chromeVisible ? Color.white : .black)
        .foregroundStyle(chromeVisible ? Color.black : .white)
        .preferredColorScheme(chromeVisible ? .light : .dark)
        .statusBarHidden(!chromeVisible)
        .buttonStyle(.plain)
        .onAppear {
            if selected == nil { selected = store.captures.last?.id }
            #if CAMERA_UI_PREVIEW
            if ["editor", "crop"].contains(CameraUIPreview.screen) { editing = store.captures.last }
            if CameraUIPreview.screen == "grid" { gridVisible = true }
            CameraUIPreview.reportReady("gallery")
            #endif
        }
        .onChange(of: store.sessionID) { _ in dismiss() }
        .fullScreenCover(item: $editing) { item in PhotoEditorView(store: store, capture: item) }
        .fullScreenCover(isPresented: $gridVisible) {
            SessionPhotoGrid(store: store) { id in selected = id }
        }
        .sheet(isPresented: $infoVisible) {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield").font(.system(size: 32, weight: .light))
                Text("本次拍摄").font(.title3.weight(.semibold))
                Text("这里只显示这次打开借拍后拍摄的照片和视频。\n照片及修改自动保存到系统「照片」。")
                    .font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                if let item = current {
                    Text(item.capturedAt.formatted(date: .abbreviated, time: .standard))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(30).presentationDetents([.height(285)]).presentationDragIndicator(.visible)
                .preferredColorScheme(.light)
        }
        .alert("无法更新照片", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("从本次预览移除？系统照片仍会保留。", isPresented: $confirmHide, titleVisibility: .visible) {
            Button("移出本次预览", role: .destructive) {
                if let item = current { store.hide(item) }
                selected = store.captures.last?.id
            }
        }
    }

    private var current: SessionCapture? { selected.flatMap { store.capture($0) } }

    private var header: some View {
        ZStack {
            HStack(spacing: 4) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                        .frame(width: 28, height: 28).background(controlFill, in: Circle())
                        .frame(width: 44, height: 38)
                }.accessibilityLabel("返回相机")
                Spacer()
                Button { gridVisible = true } label: {
                    Text("本次照片").font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 13).frame(height: 28)
                        .background(controlFill, in: Capsule())
                }.accessibilityLabel("查看本次照片网格")
                Menu {
                    Button("本次拍摄说明", systemImage: "lock.shield") { infoVisible = true }
                    if current != nil {
                        Button("移出本次预览", systemImage: "eye.slash", role: .destructive) { confirmHide = true }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold))
                        .frame(width: 28, height: 28).background(controlFill, in: Circle())
                        .frame(width: 44, height: 38)
                }.accessibilityLabel("照片选项")
            }.foregroundStyle(blue)
            if let item = current {
                VStack(spacing: 2) {
                    Text(Calendar.current.isDateInToday(item.capturedAt) ? "今天" :
                        item.capturedAt.formatted(.dateTime.month().day()))
                        .font(.system(size: 15, weight: .semibold))
                    Text(item.capturedAt.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11)).foregroundStyle(.gray)
                }.allowsHitTesting(false)
            }
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(store.captures) { item in
                        Button { selected = item.id } label: {
                            ZStack(alignment: .bottomTrailing) {
                                if let image = item.thumbnail { Image(uiImage: image).resizable().scaledToFill() }
                                else { Color(white: 0.15) }
                                if item.kind == .video {
                                    Image(systemName: "video.fill").font(.system(size: 8))
                                        .padding(2).shadow(radius: 2)
                                }
                            }
                            .frame(width: item.id == selected ? 30 : 20, height: item.id == selected ? 32 : 30)
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 2))
                            .padding(.horizontal, item.id == selected ? 4 : 0)
                        }.id(item.id).accessibilityLabel("本次第 \((store.captures.firstIndex { $0.id == item.id } ?? 0) + 1) 项")
                    }
                }
                .padding(.horizontal, max(0, UIScreen.main.bounds.width / 2 - 19))
            }
            .task(id: selected) {
                // The initial selection is set while the gallery appears;
                // wait for the strip's layout before centering that thumbnail.
                await Task.yield()
                if let id = selected { proxy.scrollTo(id, anchor: .center) }
            }
        }.frame(height: 32)
    }

    private func bottomBar(_ item: SessionCapture) -> some View {
        HStack(spacing: 0) {
            Button { gridVisible = true } label: {
                Image(systemName: "square.grid.2x2").font(.system(size: 22))
                    .frame(width: 44, height: 44).background(controlFill, in: Circle())
            }.accessibilityLabel("本次照片网格")
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Button { favorite(item) } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart").font(.system(size: 23))
                        .frame(width: 44, height: 44)
                }.disabled(item.assetID == nil || favoriteBusy).accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏本次照片")
                Button { infoVisible = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 23)).frame(width: 44, height: 44)
                }.accessibilityLabel("本次照片信息")
                Button { editing = item } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 23)).frame(width: 44, height: 44)
                }.disabled(item.kind != .photo || item.assetID == nil).accessibilityLabel("编辑照片")
            }.padding(.horizontal, 8).background(controlFill, in: Capsule())
            Spacer(minLength: 8)
            Button { confirmHide = true } label: {
                Image(systemName: "trash").font(.system(size: 23))
                    .frame(width: 44, height: 44).background(controlFill, in: Circle())
            }.accessibilityLabel("移出本次预览，保留系统照片")
        }.foregroundStyle(blue).padding(.horizontal, 28)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func favorite(_ item: SessionCapture) {
        favoriteBusy = true
        Task {
            defer { favoriteBusy = false }
            do { try await store.toggleFavorite(item) }
            catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder private func saveStatus(_ item: SessionCapture) -> some View {
        switch item.saveState {
        case .saving:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.65)
                Text("正在保存").font(.system(size: 11))
            }.padding(6).background(.regularMaterial, in: Capsule())
        case .saved: EmptyView()
        case .failed:
            Button("尚未保存 · 轻点重试") { Task { await store.retryPending() } }
                .font(.system(size: 12)).foregroundStyle(.orange)
                .padding(6).background(.regularMaterial, in: Capsule())
        }
    }
}

struct SessionPhotoGrid: View {
    @ObservedObject var store: SessionStore
    let select: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(store.captures) { item in
                        Button {
                            guard store.isCurrent(item.ticket) else { return }
                            select(item.id)
                            dismiss()
                        } label: {
                            GeometryReader { geometry in
                                if let image = item.thumbnail {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.width).clipped()
                                }
                            }.aspectRatio(1, contentMode: .fit)
                        }.buttonStyle(.plain).accessibilityLabel("查看本次拍摄")
                    }
                }
            }.background(.white).navigationTitle("本次照片").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() } }
                }
                .onChange(of: store.sessionID) { _ in dismiss() }
        }.preferredColorScheme(.light).statusBarHidden(false)
        #if CAMERA_UI_PREVIEW
        .onAppear { CameraUIPreview.reportReady("grid") }
        #endif
    }
}

struct SessionMediaView: View {
    let capture: SessionCapture
    let isSelected: Bool
    var onTap: () -> Void = {}
    @State private var player: AVPlayer?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if capture.kind == .video {
                if let player { VideoPlayer(player: player) }
                else { ProgressView() }
            } else if let image = image ?? capture.thumbnail {
                ZoomablePhoto(image: image, onTap: onTap)
            } else { ProgressView() }
        }
        .task(id: capture.displayURL.absoluteString + (isSelected ? "selected" : "preview")) {
            guard isSelected else { player?.pause(); player = nil; image = nil; return }
            if capture.kind == .video { player = AVPlayer(url: capture.displayURL) }
            else {
                let url = capture.displayURL
                let loaded = await Task.detached {
                    MediaThumbnails.make(url: url, kind: .photo, maxPixelSize: 4096)
                }.value
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
        .onDisappear { player?.pause(); player = nil; image = nil }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            player?.pause()
        }
    }
}

final class PhotoScrollSurface: UIScrollView, UIScrollViewDelegate {
    let photoView = UIImageView()
    var onSingleTap: (() -> Void)?
    private var fittedSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        photoView.contentMode = .scaleAspectFit
        addSubview(photoView)
        panGestureRecognizer.isEnabled = false
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        guard photoView.image !== image else { return }
        setZoomScale(1, animated: false)
        photoView.image = image
        fittedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1, let image = photoView.image, bounds.width > 0, bounds.height > 0 {
            let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            if size != fittedSize {
                fittedSize = size
                photoView.frame = CGRect(origin: .zero, size: size)
                contentSize = size
            }
        }
        centerPhoto()
    }

    private func centerPhoto() {
        photoView.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                                   y: max(contentSize.height, bounds.height) / 2)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photoView }
    @objc private func toggleChrome() { onSingleTap?() }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        panGestureRecognizer.isEnabled = zoomScale > 1.01
        centerPhoto()
    }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1, animated: true) }
        else {
            let point = gesture.location(in: photoView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    var onTap: () -> Void = {}
    func makeUIView(context: Context) -> PhotoScrollSurface { PhotoScrollSurface() }
    func updateUIView(_ view: PhotoScrollSurface, context: Context) {
        view.setImage(image)
        view.onSingleTap = onTap
    }
}
