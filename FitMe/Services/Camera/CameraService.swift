// AVCaptureSession isn't marked Sendable, but the preview layer must read it on the main thread while the actor
// drives it; AVFoundation documents the session as safe for that, so its Sendable errors are downgraded here.
@preconcurrency import AVFoundation
import Foundation
import os

enum CameraAccess: Equatable, Sendable {
    case notAsked
    case granted
    case denied
}

enum CameraError: Error, Equatable {
    /// No back camera, e.g. in the Simulator.
    case unavailable
    case captureFailed
}

/// Takes still photos one after another.
protocol PhotoCapturing: Sendable {
    var access: CameraAccess { get }
    /// What the live preview shows; nil when there's no real camera (tests, previews).
    var previewSession: AVCaptureSession? { get }
    /// Shows the system prompt the first time; returns whether FitMe may use the camera.
    func requestAccess() async -> Bool
    func start() async throws
    func stop() async
    /// A photo as image file data (HEIC or JPEG), ready for the capture pipeline.
    func capturePhoto() async throws -> Data
}

/// The back camera through AVFoundation. An actor so the session is configured and started off the main thread, as
/// AVFoundation asks (`startRunning` blocks).
actor CameraService: PhotoCapturing {
    /// The same session, for the viewfinder (see the import note).
    nonisolated let previewSession: AVCaptureSession?
    private let session: AVCaptureSession
    private let output = AVCapturePhotoOutput()
    private var isConfigured = false

    init() {
        let session = AVCaptureSession()
        self.session = session
        previewSession = session
    }

    nonisolated var access: CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() throws {
        if !isConfigured {
            try configure()
        }
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func capturePhoto() async throws -> Data {
        guard isConfigured else { throw CameraError.unavailable }
        let settings = output.availablePhotoCodecTypes.contains(.hevc)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            : AVCapturePhotoSettings()
        let id = settings.uniqueID
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoDelegate(continuation: continuation)
            // The output doesn't retain its delegate; keep it alive until the photo arrives.
            delegates[id] = delegate
            delegate.onFinish = { [weak self] in
                Task { await self?.forget(id) }
            }
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private var delegates: [Int64: PhotoDelegate] = [:]

    private func forget(_ id: Int64) {
        delegates[id] = nil
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera)
        else { throw CameraError.unavailable }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced
        isConfigured = true
    }
}

/// Hands one photo back to the `async` caller.
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    // Unchecked: AVFoundation calls the delegate once, on its own queue; `onFinish` is set before capture starts.
    private let continuation: CheckedContinuation<Data, Error>
    var onFinish: (@Sendable () -> Void)?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { onFinish?() }
        if let error {
            Logger.capture.error("Camera capture failed: \(String(describing: error))")
            continuation.resume(throwing: CameraError.captureFailed)
        } else if let data = photo.fileDataRepresentation() {
            continuation.resume(returning: data)
        } else {
            continuation.resume(throwing: CameraError.captureFailed)
        }
    }
}
