import SwiftUI

/// Replaces the whole interface while locked. This is a full view swap rather than a
/// blur, so no code or secret exists in the hierarchy at all.
struct LockScreenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Authenticator is locked")
                .font(.title2.bold())

            Text(unlockPrompt)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.lock.state == .authenticating {
                ProgressView()
            } else {
                Button("Unlock") {
                    Task { await model.lock.unlock() }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }

            if let error = model.lock.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Prompt as soon as the lock screen appears, so launching goes straight
            // to Touch ID without an extra click.
            await model.lock.unlock()
        }
    }

    private var unlockPrompt: String {
        switch model.lock.availability {
        case .touchID:
            "Use Touch ID to see your codes."
        case .passwordOnly:
            "Enter your login password to see your codes."
        case .unavailable(let reason):
            reason
        }
    }
}
