import Foundation
import Observation

/// Shoot many items in a row: each shot is kept, and Done sends them all to the inbox at once, so the pipeline's own
/// limit on concurrent tagging still holds.
@MainActor
@Observable
final class BatchCameraModel {
    enum State: Equatable {
        case starting
        case ready
        case needsAccess
        /// Access refused in Settings.
        case denied
        /// No camera, e.g. in the Simulator.
        case unavailable
    }

    /// A batch never holds more than this many shots in memory; at the limit, Done is the way on.
    static let maxShots = 40

    private(set) var state: State = .starting
    private(set) var shots: [Data] = []
    private(set) var isCapturing = false
    /// Briefly set after each shot, so the screen can flash.
    private(set) var lastShotAt: Date?
    private(set) var errorMessage: String?

    let camera: any PhotoCapturing

    init(camera: any PhotoCapturing) {
        self.camera = camera
    }

    var canShoot: Bool {
        state == .ready && !isCapturing && shots.count < Self.maxShots
    }

    /// Starts the camera, asking for access first if it was never asked.
    func start() async {
        switch camera.access {
        case .denied:
            state = .denied
            return
        case .notAsked:
            guard await camera.requestAccess() else {
                state = .denied
                return
            }
        case .granted:
            break
        }
        do {
            try await camera.start()
            state = .ready
        } catch {
            state = .unavailable
        }
    }

    func stop() async {
        await camera.stop()
    }

    func shoot(now: Date = .now) async {
        guard canShoot else { return }
        isCapturing = true
        defer { isCapturing = false }
        do {
            try await shots.append(camera.capturePhoto())
            lastShotAt = now
            errorMessage = nil
        } catch {
            errorMessage = "That shot didn't work. Try again."
        }
    }

    /// Drops the last shot, e.g. a blurry one.
    func undoLastShot() {
        guard !shots.isEmpty else { return }
        shots.removeLast()
    }

    /// The shots as loaders for `CaptureModel.importPhotos`, oldest first.
    var loaders: [@Sendable () async -> Data?] {
        shots.map { shot in { shot } }
    }
}
