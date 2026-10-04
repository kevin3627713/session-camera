import AVFoundation
import Combine
import UIKit

enum CameraMode { case photo, video }

struct CameraLens: Identifiable {
    let id: String
    let label: String
}

/// Every AVCaptureSession mutation, including start/stop, is on one serial queue.
final class CameraEngine: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var ready = false
    @Published private(set) var recording = false
    @Published private(set) var capturing = false
    @Published private(set) var isFront = false
    @Published private(set) var lenses: [CameraLens] = []
    @Published private(set) var selectedLens = ""
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var maxZoom: CGFloat = 8
    @Published var error: String?
    var onPhoto: ((Data, CaptureTicket) -> Void)?
    var onVideo: ((URL, CaptureTicket) -> Void)?
    private let queue = DispatchQueue(label: "session-camera.capture", qos: .userInitiated)
    private let photos = AVCapturePhotoOutput()
    private let movies = AVCaptureMovieFileOutput()
    private var input: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var photoTickets: [Int64: CaptureTicket] = [:]
    private var movieTicket: CaptureTicket?
    private var currentMode = CameraMode.photo
    private var position = AVCaptureDevice.Position.back
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVCaptureSessionRuntimeError,
                                             object: session, queue: .main) { [weak self] note in
            let failure = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            if failure?.code == .mediaServicesWereReset { self?.start() }
            else { self?.ready = false; self?.error = "相机发生中断，请重试。" }
        })
        observers.append(center.addObserver(forName: .AVCaptureSessionWasInterrupted,
                                             object: session, queue: .main) { [weak self] _ in
            self?.ready = false
        })
        observers.append(center.addObserver(forName: .AVCaptureSessionInterruptionEnded,
                                             object: session, queue: .main) { [weak self] _ in
            self?.start()
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { @MainActor in
            let permitted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: permitted = true
            case .notDetermined: permitted = await AVCaptureDevice.requestAccess(for: .video)
            default: permitted = false
            }
            guard permitted else {
                DispatchQueue.main.async { self.error = CameraFailure.permission.localizedDescription }
                return
            }
            guard UIApplication.shared.applicationState != .background else { return }
            self.queue.async {
                self.wantsRunning = true
                do {
                    if self.input == nil { try self.configure() }
                    if !self.session.isRunning { self.session.startRunning() }
                    DispatchQueue.main.async { self.ready = self.session.isRunning }
                } catch { self.report(error) }
            }
        }
    }

    func stop() {
        queue.async {
            self.wantsRunning = false
            if self.movies.isRecording { self.movies.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.ready = false }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                    position: position) else {
            throw CameraFailure.unavailable
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput), session.canAddOutput(photos) else {
            throw CameraFailure.unavailable
        }
        session.addInput(newInput)
        session.addOutput(photos)
        input = newInput
        photos.maxPhotoQualityPrioritization = .quality
        configurePhotoDimensions(device)
        publishDevice(device)
    }

    private func configurePhotoDimensions(_ device: AVCaptureDevice) {
        if let dimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) { photos.maxPhotoDimensions = dimensions }
    }

    private func publishDevice(_ device: AVCaptureDevice) {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [
            .builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera
        ], mediaType: .video, position: device.position).devices
        let wideFOV = devices.first { $0.deviceType == .builtInWideAngleCamera }?
            .activeFormat.videoFieldOfView ?? 65
        let choices = devices.map { lens -> CameraLens in
            let label: String
            switch lens.deviceType {
            case .builtInUltraWideCamera: label = "0.5"
            case .builtInTelephotoCamera:
                let ratio = tan(Double(wideFOV) * .pi / 360) /
                    tan(Double(lens.activeFormat.videoFieldOfView) * .pi / 360)
                label = String(format: "%.0f", ratio.rounded())
            default: label = "1"
            }
            return CameraLens(id: lens.uniqueID, label: label)
        }.sorted { (Double($0.label) ?? 1) < (Double($1.label) ?? 1) }
        DispatchQueue.main.async {
            self.isFront = device.position == .front
            self.lenses = choices
            self.selectedLens = device.uniqueID
            self.zoom = device.videoZoomFactor
            self.maxZoom = min(8, device.activeFormat.videoMaxZoomFactor)
        }
    }

    func switchCamera() {
        queue.async {
            guard !self.movies.isRecording, self.photoTickets.isEmpty else { return }
            let newPosition: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                       position: newPosition) else { return }
            self.replaceInput(with: device)
        }
    }

    func selectLens(_ id: String) {
        queue.async {
            guard !self.movies.isRecording, self.photoTickets.isEmpty else { return }
            let device = AVCaptureDevice.DiscoverySession(deviceTypes: [
                .builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera
            ], mediaType: .video, position: self.position).devices.first { $0.uniqueID == id }
            if let device { self.replaceInput(with: device) }
        }
    }

    private func replaceInput(with device: AVCaptureDevice) {
        do {
            let replacement = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            if session.canAddInput(replacement) {
                session.addInput(replacement)
                input = replacement
                position = device.position
                configurePhotoDimensions(device)
                publishDevice(device)
            } else if let input, session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
        } catch { report(error) }
    }

    func setMode(_ mode: CameraMode) {
        queue.async {
            guard !self.movies.isRecording, self.photoTickets.isEmpty else { return }
            self.session.beginConfiguration()
            if mode == .video {
                if self.session.canSetSessionPreset(.hd1920x1080) {
                    self.session.sessionPreset = .hd1920x1080
                }
                if !self.session.outputs.contains(self.movies), self.session.canAddOutput(self.movies) {
                    self.session.addOutput(self.movies)
                }
                if let connection = self.movies.connection(with: .video),
                   connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            } else {
                if self.session.outputs.contains(self.movies) { self.session.removeOutput(self.movies) }
                if let audioInput = self.audioInput { self.session.removeInput(audioInput); self.audioInput = nil }
                self.session.sessionPreset = .photo
            }
            if let device = self.input?.device { self.configurePhotoDimensions(device) }
            self.currentMode = mode
            self.session.commitConfiguration()
        }
    }

    func setZoom(_ factor: CGFloat) {
        queue.async {
            guard let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                    min(factor, min(8, device.activeFormat.videoMaxZoomFactor)))
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoom = device.videoZoomFactor }
            } catch { self.report(error) }
        }
    }

    func focus(at point: CGPoint, lock: Bool = false) {
        queue.async {
            guard let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    let mode: AVCaptureDevice.FocusMode = lock ? .locked : .autoFocus
                    if device.isFocusModeSupported(mode) { device.focusMode = mode }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    let mode: AVCaptureDevice.ExposureMode = lock ? .locked : .continuousAutoExposure
                    if device.isExposureModeSupported(mode) { device.exposureMode = mode }
                }
                device.unlockForConfiguration()
            } catch { self.report(error) }
        }
    }

    func setExposure(_ value: Float) {
        queue.async {
            guard let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(max(device.minExposureTargetBias,
                    min(value, device.maxExposureTargetBias)), completionHandler: nil)
                device.unlockForConfiguration()
            } catch { self.report(error) }
        }
    }

    func takePhoto(ticket: CaptureTicket, flash: AVCaptureDevice.FlashMode) {
        let orientation = Self.captureOrientation()
        queue.async {
            guard self.session.isRunning, self.currentMode == .photo,
                  self.photoTickets.isEmpty, let device = self.input?.device else { return }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.maxPhotoDimensions = self.photos.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            if device.hasFlash && device.isFlashAvailable { settings.flashMode = flash }
            self.orient(self.photos.connection(with: .video), orientation: orientation)
            self.photoTickets[settings.uniqueID] = ticket
            DispatchQueue.main.async { self.capturing = true }
            self.photos.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleVideo(ticket: CaptureTicket) {
        let orientation = Self.captureOrientation()
        Task {
            let permitted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: permitted = true
            case .notDetermined: permitted = await AVCaptureDevice.requestAccess(for: .audio)
            default: permitted = false
            }
            guard permitted else {
                self.report(CameraFailure.permission)
                return
            }
            self.queue.async {
                if self.movies.isRecording { self.movies.stopRecording(); return }
                guard self.session.isRunning, self.currentMode == .video,
                      self.session.outputs.contains(self.movies), self.movieTicket == nil else { return }
                do {
                    if self.audioInput == nil {
                        guard let microphone = AVCaptureDevice.default(for: .audio) else {
                            throw CameraFailure.unavailable
                        }
                        let audio = try AVCaptureDeviceInput(device: microphone)
                        self.session.beginConfiguration()
                        if self.session.canAddInput(audio) {
                            self.session.addInput(audio)
                            self.audioInput = audio
                        }
                        self.session.commitConfiguration()
                        guard self.audioInput != nil else { throw CameraFailure.unavailable }
                    }
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                    self.movieTicket = ticket
                    self.orient(self.movies.connection(with: .video), orientation: orientation)
                    self.movies.startRecording(to: url, recordingDelegate: self)
                } catch { self.report(error) }
            }
        }
    }

    private func orient(_ connection: AVCaptureConnection?, orientation: AVCaptureVideoOrientation) {
        guard let connection else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false // Native-style unmirrored saved selfie.
        }
    }

    private static func captureOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    private func report(_ failure: Error) {
        DispatchQueue.main.async { self.error = failure.localizedDescription }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        queue.async {
            guard let ticket = self.photoTickets[photo.resolvedSettings.uniqueID] else { return }
            if let error { self.report(error) }
            else if let data = photo.fileDataRepresentation() {
                DispatchQueue.main.async { self.onPhoto?(data, ticket) }
            } else { self.report(CameraFailure.invalidImage) }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        queue.async {
            self.photoTickets.removeValue(forKey: resolvedSettings.uniqueID)
            DispatchQueue.main.async { self.capturing = false }
            if let error { self.report(error) }
        }
    }
}

extension CameraEngine: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.recording = true }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let ticket = self.movieTicket
            self.movieTicket = nil
            DispatchQueue.main.async { self.recording = false }
            let completed = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
            if error == nil || completed, let ticket {
                DispatchQueue.main.async { self.onVideo?(outputFileURL, ticket) }
            } else {
                if let error { self.report(error) }
                try? FileManager.default.removeItem(at: outputFileURL)
            }
        }
    }
}
