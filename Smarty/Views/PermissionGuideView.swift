import SwiftUI

struct PermissionGuideView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var micOK = false
    @State private var speechOK = false
    @State private var screenOK = false
    @State private var micHint: String?
    @State private var screenHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions")
                        .font(.title2.weight(.semibold))
                    Text("Smarty needs microphone (OpenAI speech-to-text) and screen recording for OCR. Frames stay in memory and are never saved.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .keyboardShortcut(.cancelAction)
            }

            permissionRow(
                kind: .microphone,
                granted: micOK,
                detail: micOK ? "Granted" : (micHint ?? "Required"),
                request: {
                    micOK = await appEnvironment.permissions.requestMicrophone()
                    refreshMicHint()
                }
            )
            permissionRow(
                kind: .speechRecognition,
                granted: speechOK,
                detail: speechOK ? "Granted" : "Optional (listening uses OpenAI STT)",
                request: {
                    speechOK = await appEnvironment.permissions.requestSpeechRecognition()
                }
            )
            permissionRow(
                kind: .screenRecording,
                granted: screenOK,
                detail: screenOK ? "Granted" : (screenHint ?? "Required"),
                request: {
                    screenOK = await appEnvironment.permissions.requestScreenRecording()
                    refreshScreenHint()
                }
            )

            if let micHint, !micOK {
                Text(micHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let screenHint, !screenOK {
                Text(screenHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Request Missing") {
                    Task {
                        if !micOK {
                            micOK = await appEnvironment.permissions.requestMicrophone()
                        }
                        if !speechOK {
                            speechOK = await appEnvironment.permissions.requestSpeechRecognition()
                        }
                        if !screenOK {
                            screenOK = await appEnvironment.permissions.requestScreenRecording()
                        }
                        refreshMicHint()
                        refreshScreenHint()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh Status") {
                    refreshStatus()
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        micOK = appEnvironment.permissions.state(for: .microphone) == .granted
        speechOK = appEnvironment.permissions.state(for: .speechRecognition) == .granted
        screenOK = appEnvironment.permissions.screenCapturePreflight()
        refreshMicHint()
        refreshScreenHint()
    }

    private func refreshMicHint() {
        guard !micOK else {
            micHint = nil
            return
        }
        micHint = """
        Enable Smarty under System Settings → Privacy & Security → Microphone. If it stays off after Allow, Stop the app in Xcode and Run again (Hardened Runtime needs the audio-input entitlement — now included).
        """
    }

    private func refreshScreenHint() {
        guard !screenOK else {
            screenHint = nil
            return
        }
        screenHint = """
        Toggle ON in Settings is not enough until this process restarts. Stop Smarty → enable Smarty in Screen Recording → Stop → Run again.
        """
    }

    private func permissionRow(
        kind: PermissionKind,
        granted: Bool,
        detail: String,
        request: @escaping () async -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Allow") {
                Task { await request() }
            }
            Button("Settings") {
                appEnvironment.permissions.openSystemSettings(for: kind)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    PermissionGuideView()
        .environment(AppEnvironment.shared)
        .frame(width: 460, height: 420)
}
