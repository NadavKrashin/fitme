import AVFoundation
import SwiftUI
import UIKit

/// A full-screen camera for photographing the closet one item after another. Done hands every shot to the inbox.
struct BatchCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var model: BatchCameraModel
    @State private var isConfirmingClose = false
    @State private var flash = false
    /// Receives the shots, oldest first, when the owner taps Done.
    let onDone: ([@Sendable () async -> Data?]) -> Void

    init(camera: any PhotoCapturing, onDone: @escaping ([@Sendable () async -> Data?]) -> Void) {
        _model = State(initialValue: BatchCameraModel(camera: camera))
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            Theme.viewfinder.ignoresSafeArea()
            content
            Theme.onViewfinder
                .opacity(flash ? 0.6 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact, trigger: model.shots.count)
        .task { await model.start() }
        .onDisappear { Task { await model.stop() } }
        .onChange(of: model.lastShotAt) {
            flash = true
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
        }
        .confirmationDialog(
            "Add \(model.shots.count) \(model.shots.count == 1 ? "photo" : "photos") to the inbox?",
            isPresented: $isConfirmingClose,
            titleVisibility: .visible
        ) {
            Button("Add to inbox") { finish() }
            Button("Discard", role: .destructive) { dismiss() }
        }
    }

    // MARK: Viewfinder

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .starting, .needsAccess:
            ProgressView().tint(Theme.onViewfinder)
        case .ready:
            if let session = model.camera.previewSession {
                CameraPreview(session: session).ignoresSafeArea()
            }
        case .denied:
            message(
                "FitMe can't use the camera",
                detail: "Allow camera access for FitMe in Settings, or add photos from your library instead.",
                action: ("Open Settings", {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                })
            )
        case .unavailable:
            message(
                "No camera here",
                detail: "This device has no camera. Add photos from your library instead.",
                action: nil
            )
        }
    }

    private func message(_ title: String, detail: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.largeTitle)
                .foregroundStyle(Theme.onViewfinder.opacity(0.8))
            Text(title).font(Theme.title(22)).foregroundStyle(Theme.onViewfinder)
            Text(detail)
                .font(.callout)
                .foregroundStyle(Theme.onViewfinder.opacity(0.75))
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.pill(.accent))
            }
        }
        .padding(32)
    }

    // MARK: Controls

    private var topBar: some View {
        HStack {
            Button {
                if model.shots.isEmpty {
                    dismiss()
                } else {
                    isConfirmingClose = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Theme.onViewfinder)
                    .frame(width: 44, height: 44)
                    .background(Theme.onViewfinder.opacity(0.15), in: .circle)
            }
            .accessibilityLabel("Close camera")
            Spacer()
            if !model.shots.isEmpty {
                Button("Done · \(model.shots.count)") { finish() }
                    .buttonStyle(.pill(.accent))
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            Text(model.errorMessage ?? hint)
                .opacity(model.state == .ready ? 1 : 0)
                .font(.footnote)
                .foregroundStyle(Theme.onViewfinder.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if model.state == .ready {
                HStack {
                    // Fixed slots either side keep the shutter centred, with or without a last shot.
                    Color.clear.frame(width: 64, height: 64).overlay { lastShot }
                    Spacer()
                    shutter
                    Spacer()
                    Color.clear.frame(width: 64, height: 64)
                }
                .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 12)
        .background(Theme.viewfinder.opacity(0.35))
    }

    private var hint: String {
        if model.shots.count >= BatchCameraModel.maxShots {
            return "That's a full batch. Tap Done, then shoot the next one."
        }
        return model.shots.isEmpty ? InboxView.photoTip : "One item per photo. Tap Done when you're finished."
    }

    private var shutter: some View {
        Button {
            Task { await model.shoot() }
        } label: {
            Circle()
                .fill(Theme.onViewfinder)
                .frame(width: 64, height: 64)
                .padding(6)
                .overlay(Circle().strokeBorder(Theme.onViewfinder, lineWidth: 3))
                .opacity(model.canShoot ? 1 : 0.4)
        }
        .disabled(!model.canShoot)
        .accessibilityLabel("Take photo")
    }

    @ViewBuilder
    private var lastShot: some View {
        if let data = model.shots.last, let image = UIImage(data: data) {
            Menu {
                Button("Remove last photo", systemImage: "trash", role: .destructive) { model.undoLastShot() }
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        Text("\(model.shots.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.onTerracotta)
                            .padding(5)
                            .background(Theme.terracotta, in: .circle)
                            .offset(x: 8, y: -8)
                    }
            }
            .accessibilityLabel("\(model.shots.count) photos taken")
        }
    }

    private func finish() {
        onDone(model.loaders)
        dismiss()
    }
}

/// The live viewfinder.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast - layerClass makes it this type
        }
    }
}
