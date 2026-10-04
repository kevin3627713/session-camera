import AVFoundation
import AVKit
import SwiftUI

struct CameraScreen: View {
    @StateObject private var engine = CameraEngine()
    @StateObject private var store = SessionStore()
    @State private var mode = CameraMode.photo
    @State private var flash = AVCaptureDevice.FlashMode.off
    @State private var timerSeconds = 0
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var exposure = 0.0
    @State private var controlsVisible = false
    @State private var galleryVisible = false
    @State private var guideVisible = false
    @State private var active = true
    @State private var setupDone = false
    @State private var guidedAccess = UIAccessibility.isGuidedAccessEnabled
    @State private var recordingStarted: Date?
    @AppStorage("showGrid") private var grid = false
    @AppStorage("remindGuidedAccess") private var remindGuidedAccess = true
    @AppStorage("completedSetup") private var completedSetup = false

    var body: some View {
        VStack(spacing: 0) {
            header
            viewfinder
            if controlsVisible { additionalControls }
            modeSelector
            shutterRow
            Text("本次 \(store.captures.count) 项 · 自动存入照片")
                .font(.caption2).foregroundStyle(.gray).padding(.bottom, 12)
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .statusBarHidden()
        .sheet(isPresented: $galleryVisible) {
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
            active = false
            countdownTask?.cancel()
            countdown = 0
            galleryVisible = false
            guideVisible = false
            store.resetSession()
            engine.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
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
        HStack {
            Button {
                flash = flash == .off ? .auto : flash == .auto ? .on : .off
            } label: {
                Image(systemName: flash == .off ? "bolt.slash.fill" : flash == .auto ? "bolt.badge.a.fill" : "bolt.fill")
                    .foregroundStyle(flash == .off ? .white : .yellow)
                    .frame(width: 44, height: 44)
            }.disabled(mode == .video || engine.isFront || engine.recording || countdown > 0)
                .accessibilityLabel("闪光灯")
            Spacer()
            Button { guideVisible = true } label: {
                Label(guidedAccess ? "已锁定" : "本次可见", systemImage: guidedAccess ? "lock.fill" : "shield.lefthalf.filled")
                    .font(.caption).foregroundStyle(guidedAccess ? .green : .white)
            }.accessibilityLabel(guidedAccess ? "引导式访问已开启" : "相册已隔离，查看引导式访问")
            Spacer()
            Button { controlsVisible.toggle() } label: {
                Image(systemName: controlsVisible ? "chevron.down" : "chevron.up")
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("拍摄选项")
        }.padding(.horizontal, 14).padding(.top, 4)
    }

    private var viewfinder: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreview(engine: engine)
                if grid { CameraGrid().stroke(.white.opacity(0.4), lineWidth: 0.5).allowsHitTesting(false) }
                if !engine.ready {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text("轻点重试启动相机").font(.caption)
                        Button("重试") { engine.start() }
                    }.padding(22).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                }
                if countdown > 0 {
                    Text("\(countdown)").font(.system(size: 92, weight: .thin))
                        .shadow(radius: 8).allowsHitTesting(false)
                }
                VStack {
                    if let started = recordingStarted {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            let seconds = max(0, Int(context.date.timeIntervalSince(started)))
                            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                                .monospacedDigit().padding(8).background(.red, in: Capsule())
                        }.padding(.top, 12)
                    }
                    Spacer()
                    if !engine.isFront {
                        HStack(spacing: 12) {
                            ForEach(engine.lenses) { lens in
                                Button { engine.selectLens(lens.id) } label: {
                                    Text(lens.id == engine.selectedLens ? "\(lens.label)×" : lens.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(lens.id == engine.selectedLens ? .yellow : .white)
                                        .frame(width: 40, height: 40)
                                        .background(.black.opacity(0.6), in: Circle())
                                }.disabled(engine.recording || engine.capturing || countdown > 0)
                            }
                        }.padding(.bottom, 14)
                    }
                }
            }
            .clipped()
            .frame(width: geometry.size.width, height: geometry.size.height)
        }.aspectRatio(mode == .photo ? 3.0 / 4 : 9.0 / 16, contentMode: .fit)
            .frame(maxHeight: .infinity)
    }

    private var additionalControls: some View {
        VStack(spacing: 10) {
            HStack {
                Button { grid.toggle() } label: {
                    Label("网格", systemImage: "grid").foregroundStyle(grid ? .yellow : .white)
                }
                Spacer()
                Button { timerSeconds = timerSeconds == 0 ? 3 : timerSeconds == 3 ? 10 : 0 } label: {
                    Label(timerSeconds == 0 ? "定时关闭" : "\(timerSeconds) 秒", systemImage: "timer")
                        .foregroundStyle(timerSeconds > 0 ? .yellow : .white)
                }.disabled(mode == .video || countdown > 0)
                Spacer()
                Text(String(format: "%.1f×", engine.zoom)).monospacedDigit()
            }.font(.caption)
            HStack {
                Image(systemName: "sun.max")
                Slider(value: $exposure, in: -2...2).tint(.yellow)
                Text(String(format: "%+.1f", exposure)).font(.caption).monospacedDigit()
            }
            if !store.photosAllowed {
                Button("照片权限未开启 · 前往设置") { openAppSettings() }
                    .font(.caption).foregroundStyle(.orange)
            }
            if store.pendingRecoveryCount > 0 {
                Button("\(store.pendingRecoveryCount) 项待保存 · 重试") { Task { await store.retryPending() } }
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var modeSelector: some View {
        HStack(spacing: 30) {
            Button("视频") { mode = .video; engine.setMode(.video) }
                .foregroundStyle(mode == .video ? .yellow : .white)
            Button("照片") { mode = .photo; engine.setMode(.photo) }
                .foregroundStyle(mode == .photo ? .yellow : .white)
        }.font(.system(size: 14, weight: .semibold)).padding(.vertical, 16)
            .disabled(engine.recording || engine.capturing || countdown > 0 || !engine.ready)
    }

    private var shutterRow: some View {
        HStack {
            Button { galleryVisible = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1))
                    if let thumbnail = store.captures.last?.thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else { Image(systemName: "photo").foregroundStyle(.gray) }
                }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            }.accessibilityLabel("查看本次拍摄的照片").disabled(engine.recording || countdown > 0)
            Spacer()
            Button(action: shutter) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                    if engine.recording {
                        RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(mode == .photo ? .white : .red).frame(width: 64, height: 64)
                    }
                }
            }.disabled(!engine.ready || engine.capturing || countdown > 0)
                .accessibilityLabel(mode == .photo ? "拍照" : engine.recording ? "停止录像" : "开始录像")
            Spacer()
            Button { engine.switchCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 25)).frame(width: 48, height: 48)
                    .background(.white.opacity(0.12), in: Circle())
            }.disabled(engine.recording || engine.capturing || countdown > 0)
                .accessibilityLabel("切换前后摄像头")
        }.padding(.horizontal, 32).padding(.bottom, 18)
    }

    private func shutter() {
        let ticket = store.issueTicket()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if mode == .video { engine.toggleVideo(ticket: ticket); return }
        if timerSeconds == 0 { engine.takePhoto(ticket: ticket, flash: flash); return }
        countdownTask = Task {
            for second in stride(from: timerSeconds, through: 1, by: -1) {
                guard !Task.isCancelled, active else { countdown = 0; return }
                countdown = second
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { countdown = 0; return }
            }
            countdown = 0
            guard !Task.isCancelled, active else { return }
            engine.takePhoto(ticket: ticket, flash: flash)
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
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
                    Text("这项自动化由你在系统中配置。借拍会显示实际锁定状态；没有显示「已锁定」时，请手动启动引导式访问。")
                }
                Section {
                    Toggle("每次打开时提醒开启引导式访问", isOn: $remind)
                }
                Section("照片权限") {
                    Text("建议选择「有限访问」：新拍照片仍可保存和编辑。借拍仅用本次照片 ID 请求修改，不枚举你的相册，也没有导入旧照片的入口。")
                    Text("仅添加照片权限可以保存新照片，但不能同步修改原记录。编辑时 iOS 可能要求你确认允许修改。")
                }
            }.navigationTitle("安心借拍").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("开始拍摄") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct SessionGallery: View {
    @ObservedObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var editing: SessionCapture?
    @State private var confirmHide = false

    var body: some View {
        NavigationStack {
            Group {
                if store.captures.isEmpty {
                    ContentUnavailableView("本次还没有照片", systemImage: "camera",
                                           description: Text("拍下的照片会显示在这里，并自动保存到系统照片。"))
                } else {
                    VStack(spacing: 10) {
                        TabView(selection: $selected) {
                            ForEach(store.captures) { item in
                                SessionMediaView(capture: item).tag(Optional(item.id))
                            }
                        }.tabViewStyle(.page(indexDisplayMode: .never))
                        if let item = current {
                            saveStatus(item)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(store.captures) { item in
                                        Button { selected = item.id } label: {
                                            if let image = item.thumbnail {
                                                Image(uiImage: image).resizable().scaledToFill()
                                                    .frame(width: 40, height: 48).clipped()
                                                    .overlay(Rectangle().stroke(item.id == selected ? .yellow : .clear, lineWidth: 2))
                                            }
                                        }
                                    }
                                }.padding(.horizontal)
                            }.frame(height: 52)
                            HStack {
                                Button { confirmHide = true } label: {
                                    Label("移出本次", systemImage: "eye.slash")
                                }
                                Spacer()
                                if item.kind == .photo {
                                    Button("编辑") { editing = item }.disabled(item.assetID == nil)
                                }
                            }.padding()
                        }
                    }
                }
            }.background(.black)
                .navigationTitle("本次拍摄 · \(store.captures.count) 项")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("相机") { dismiss() } } }
                .onAppear { selected = store.captures.last?.id }
                .onChange(of: store.sessionID) { _ in dismiss() }
                .sheet(item: $editing) { item in PhotoEditorView(store: store, capture: item) }
                .confirmationDialog("仅从本次预览移除，系统照片仍然保留", isPresented: $confirmHide) {
                    Button("移出本次预览", role: .destructive) {
                        if let item = current { store.hide(item) }
                        selected = store.captures.last?.id
                    }
                }
        }.preferredColorScheme(.dark)
    }

    private var current: SessionCapture? { selected.flatMap { store.capture($0) } }

    @ViewBuilder private func saveStatus(_ item: SessionCapture) -> some View {
        switch item.saveState {
        case .saving: Label("正在保存到照片…", systemImage: "arrow.triangle.2.circlepath").font(.caption)
        case .saved: Label("已保存到照片", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        case .failed:
            Button("尚未保存 · 轻点重试") { Task { await store.retryPending() } }
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

struct SessionMediaView: View {
    let capture: SessionCapture
    @State private var player: AVPlayer?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if capture.kind == .video {
                if let player { VideoPlayer(player: player) }
                else { ProgressView() }
            } else if let image = image ?? capture.thumbnail {
                ZoomablePhoto(image: image)
            } else { ProgressView() }
        }
        .task(id: capture.displayURL) {
            if capture.kind == .video { player = AVPlayer(url: capture.displayURL) }
            else {
                let url = capture.displayURL
                image = await Task.detached { MediaThumbnails.make(url: url, kind: .photo) }.value
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
    func makeUIView(context: Context) -> PhotoScrollSurface { PhotoScrollSurface() }
    func updateUIView(_ view: PhotoScrollSurface, context: Context) { view.setImage(image) }
}
