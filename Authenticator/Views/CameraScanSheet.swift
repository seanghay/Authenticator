import SwiftUI

struct CameraScanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var scanner = CameraScanner()
    @State private var found: [Account] = []
    @State private var problems: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan QR Code")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            preview
                .frame(width: 480, height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            statusLine

            HStack {
                Button("Reset") {
                    scanner.reset()
                    found.removeAll()
                    problems.removeAll()
                }
                .disabled(found.isEmpty && problems.isEmpty)

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add \(found.count) Account\(found.count == 1 ? "" : "s")") {
                    model.commitImport(found)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(found.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            await scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
        .onChange(of: scanner.payloads) { _, payloads in
            let result = ImportCoordinator.accounts(fromPayloads: payloads)
            found = result.accounts
            problems = result.problems
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch scanner.status {
        case .running:
            CameraPreviewView(session: scanner.session)
        case .denied:
            message(
                "Camera access is off",
                detail: "Allow camera access for Authenticator in System Settings › Privacy & Security › Camera.",
                icon: "video.slash"
            )
        case .unavailable:
            message("No camera found", detail: "Connect a camera, or import a screenshot instead.", icon: "video.slash")
        case .failed(let reason):
            message("Camera error", detail: reason, icon: "exclamationmark.triangle")
        case .idle:
            message("Starting camera…", detail: "", icon: "video")
        }
    }

    private func message(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle)
            Text(title).font(.headline)
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var statusLine: some View {
        if !found.isEmpty {
            Label(
                "Found \(found.count) account\(found.count == 1 ? "" : "s"): \(found.map(\.displayTitle).joined(separator: ", "))",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let problem = problems.first {
            Label(problem, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Point the camera at a QR code.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
