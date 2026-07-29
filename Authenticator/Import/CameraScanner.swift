import AVFoundation
import Foundation

/// Drives a live capture session and reports QR payloads as they are seen.
@Observable
@MainActor
final class CameraScanner: NSObject {
    enum Status: Equatable {
        case idle
        case denied
        case unavailable
        case running
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Payloads seen since the scanner started, in order of first sighting.
    private(set) var payloads: [String] = []

    let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()
    private var seen = Set<String>()
    private var isConfigured = false

    /// Requests permission if needed, then configures and starts the session.
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        case .denied, .restricted:
            status = .denied
            return
        @unknown default:
            status = .denied
            return
        }

        if !isConfigured {
            do {
                try configure()
                isConfigured = true
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        }

        guard !session.isRunning else { return }
        let session = self.session
        // startRunning blocks; keep it off the main actor.
        await Task.detached { session.startRunning() }.value
        status = .running
    }

    func stop() {
        guard session.isRunning else { return }
        let session = self.session
        Task.detached { session.stopRunning() }
    }

    /// Forget what has been seen, so re-scanning the same code reports it again.
    func reset() {
        seen.removeAll()
        payloads.removeAll()
    }

    private func configure() throws {
        // `.external` covers USB webcams and Continuity Camera, not just the built-in one.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        guard let device = discovery.devices.first else {
            status = .unavailable
            throw CameraError.noDevice
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)

        // Must come after addOutput — the available types are empty until then.
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr)
            ? [.qr] : []
    }

    enum CameraError: LocalizedError {
        case noDevice
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noDevice: "No camera was found."
            case .cannotAddInput: "The camera could not be opened."
            case .cannotAddOutput: "The camera could not be configured for scanning."
            }
        }
    }
}

extension CameraScanner: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let values = metadataObjects
            .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .compactMap(\.stringValue)
        guard !values.isEmpty else { return }

        MainActor.assumeIsolated {
            for value in values where seen.insert(value).inserted {
                payloads.append(value)
            }
        }
    }
}
