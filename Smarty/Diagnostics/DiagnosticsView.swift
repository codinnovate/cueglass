import SwiftUI

/// Compact HUD showing live session, overlay, permission, and process state.
struct DiagnosticsView: View {
    static let width: CGFloat = 280

    let session: InterviewSessionManager
    let settingsStore: SettingsStore
    let monitor: DiagnosticsMonitor
    let level: DiagnosticsWindowLevel
    let isCollapsed: Bool
    let onSetLevel: (DiagnosticsWindowLevel) -> Void
    let onToggleCollapsed: () -> Void
    let onCopyReport: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !isCollapsed {
                Divider().opacity(0.4)
                sessionSection
                overlaySection
                permissionSection
                processSection
                if let error = session.lastErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(width: Self.width, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        )
        .environment(\.colorScheme, .dark)
        .contextMenu { menuItems }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            if isCollapsed {
                Text(session.status.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(cpuText) · \(memoryText)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Diagnostics")
                    .fontWeight(.semibold)
                Spacer(minLength: 4)
                Menu {
                    menuItems
                } label: {
                    Text(level.shortTitle)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Window level: \(level.title)")
            }
            headerButton(isCollapsed ? "chevron.down" : "chevron.up", help: isCollapsed ? "Expand" : "Collapse", action: onToggleCollapsed)
            headerButton("xmark", help: "Hide Diagnostics", action: onClose)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    @ViewBuilder
    private var menuItems: some View {
        Section("Window Level") {
            ForEach(DiagnosticsWindowLevel.allCases) { option in
                Button {
                    onSetLevel(option)
                } label: {
                    if option == level {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        }
        Divider()
        Button("Copy Report", action: onCopyReport)
        Button(isCollapsed ? "Expand" : "Collapse", action: onToggleCollapsed)
        Button("Hide Diagnostics", action: onClose)
    }

    // MARK: - Sections

    private var sessionSection: some View {
        let settings = settingsStore.settings
        return section("Session") {
            row("Status", session.status.label, color: statusColor)
            row("Running", yesNo(session.isRunning))
            row("Mode", settings.assistantMode.title)
            row("Provider", "\(settings.provider.displayName) · \(settings.model)")
            row("Mic", micText)
            row("Context", "\(session.answeredTurns.count) turns · \(session.history.count) msgs")
            if !session.pendingImages.isEmpty {
                row("Images", "\(session.pendingImages.count) pending")
            }
        }
    }

    private var overlaySection: some View {
        let settings = settingsStore.settings
        return section("Overlay") {
            row("Visible", yesNo(monitor.isOverlayVisible))
            row("Flags", [
                settings.blindModeEnabled ? "blind" : nil,
                settings.clickThroughEnabled ? "click-through" : nil,
                settings.positionLocked ? "locked" : nil
            ].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "—")
        }
    }

    private var permissionSection: some View {
        section("Permissions") {
            HStack(spacing: 10) {
                ForEach(PermissionKind.allCases) { kind in
                    let state = monitor.permissions[kind]
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Self.color(for: state))
                            .frame(width: 6, height: 6)
                        Text(Self.shortTitle(for: kind))
                    }
                    .help("\(kind.title): \(Self.label(for: state))")
                }
            }
        }
    }

    private var processSection: some View {
        let process = monitor.process
        return section("Process") {
            row("CPU", cpuText)
            row("Memory", memoryText)
            row("Threads", "\(process.threadCount)")
            row("Uptime", Self.format(duration: process.uptime))
            row("Displays", "\(monitor.displayCount)")
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            content()
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func row(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .foregroundStyle(color ?? .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private var micText: String {
        if session.isWhisperTranscribing { return "transcribing" }
        if session.isWhisperRecording { return session.isWhisperRecordingPaused ? "recording (paused)" : "recording" }
        if session.isMicMuted { return "muted" }
        return session.isListenArmed ? "armed" : "idle"
    }

    private var cpuText: String {
        String(format: "%.1f%%", monitor.process.cpuPercent)
    }

    private var memoryText: String {
        ByteCountFormatter.string(fromByteCount: Int64(monitor.process.memoryFootprintBytes), countStyle: .memory)
    }

    private var statusColor: Color {
        if session.isListenArmed { return .green }
        switch session.status {
        case .idle: return .gray
        case .listening: return .green
        case .thinking: return .orange
        case .streaming: return .blue
        case .paused: return .yellow
        case .error: return .red
        }
    }

    static func shortTitle(for kind: PermissionKind) -> String {
        switch kind {
        case .microphone: return "Mic"
        case .speechRecognition: return "Speech"
        case .screenRecording: return "Screen"
        }
    }

    static func label(for state: PermissionState?) -> String {
        switch state {
        case .granted: return "granted"
        case .denied: return "denied"
        case .needsRelaunch: return "needs relaunch"
        case .notDetermined, nil: return "not determined"
        }
    }

    private static func color(for state: PermissionState?) -> Color {
        switch state {
        case .granted: return .green
        case .denied: return .red
        case .needsRelaunch: return .orange
        case .notDetermined, nil: return .gray
        }
    }

    static func format(duration: TimeInterval) -> String {
        let total = Int(duration)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

/// Plain-text snapshot of the widget for bug reports. API keys are never included.
enum DiagnosticsReport {
    @MainActor
    static func make(
        session: InterviewSessionManager,
        settings: AppSettings,
        monitor: DiagnosticsMonitor,
        level: DiagnosticsWindowLevel,
        bundle: Bundle = .main,
        date: Date = Date()
    ) -> String {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let process = monitor.process
        let permissions = PermissionKind.allCases
            .map { "\($0.title)=\(DiagnosticsView.label(for: monitor.permissions[$0]))" }
            .joined(separator: ", ")

        return """
        Cueglass diagnostics — \(ISO8601DateFormatter().string(from: date))
        App \(version) (\(build)) · macOS \(os)
        Status: \(session.status.label) · running=\(session.isRunning) · mode=\(settings.assistantMode.rawValue)
        Provider: \(settings.provider.displayName) · model=\(settings.model) · streaming=\(settings.streamingEnabled)
        Mic: muted=\(session.isMicMuted) armed=\(session.isListenArmed) recording=\(session.isWhisperRecording) transcribing=\(session.isWhisperTranscribing)
        Context: turns=\(session.answeredTurns.count) messages=\(session.history.count) pendingImages=\(session.pendingImages.count)
        Overlay: visible=\(monitor.isOverlayVisible) blind=\(settings.blindModeEnabled) clickThrough=\(settings.clickThroughEnabled) locked=\(settings.positionLocked)
        Permissions: \(permissions)
        Process: cpu=\(String(format: "%.1f", process.cpuPercent))% memory=\(process.memoryFootprintBytes)B threads=\(process.threadCount) uptime=\(DiagnosticsView.format(duration: process.uptime))
        Displays: \(monitor.displayCount) · widget level=\(level.rawValue) (\(level.windowLevel.rawValue))
        Last error: \(session.lastErrorMessage ?? "none")
        """
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
