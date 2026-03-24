import SwiftUI

struct OverlayView: View {
    @Bindable var session: InterviewSessionManager
    let fontSize: Double
    let opacity: Double
    var assistantMode: AssistantMode = .whisper
    var blindModeEnabled: Bool = true
    var statusBlinkEnabled: Bool = true
    /// Floating overlay shows ✕; main window uses traffic lights instead.
    var showsCloseButton: Bool = true
    var onRequestTypingFocus: (() -> Void)? = nil
    var onAppearanceChange: (() -> Void)? = nil
    var onToggleBlind: (() -> Void)? = nil
    var onModeChange: ((AssistantMode) -> Void)? = nil
    var onCloseOverlay: (() -> Void)? = nil
    @State private var historyExpanded = false
    @State private var heardExpanded = true
    @State private var draftQuestion = ""
    @State private var micPulse = false
    @State private var showImageImporter = false
    @FocusState private var askFieldFocused: Bool

    private var isWhisper: Bool { assistantMode == .whisper }

    var body: some View {
        Group {
            if isWhisper {
                whisperChrome
            } else {
                streamChrome
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(opacity)
                .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
    }

    /// Ask + Screenshot sit below answers (not overlaid on top of them).
    private var whisperChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            modeSwitcher
            header
            Divider().opacity(0.35)
            answerSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !session.keyTerms.isEmpty {
                KeyTermsPanel(terms: session.keyTerms, fontSize: fontSize)
            }
            whisperUtilityRow
            askField
            VStack(spacing: 10) {
                whisperCaptureSection
                whisperScreenshotSection
            }
            .padding(.horizontal, 2)
        }
        .fileImporter(
            isPresented: $showImageImporter,
            allowedContentTypes: [.jpeg, .png, .heic],
            allowsMultipleSelection: true
        ) { result in
            handleImageImport(result)
        }
    }

    private var streamChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            modeSwitcher
            header
            Divider().opacity(0.35)
            answerSection
            if !session.keyTerms.isEmpty {
                Divider().opacity(0.35)
                KeyTermsPanel(terms: session.keyTerms, fontSize: fontSize)
            }
            Divider().opacity(0.35)
            heardSection
            askField
            historySection
            controls
        }
        .fileImporter(
            isPresented: $showImageImporter,
            allowedContentTypes: [.jpeg, .png, .heic],
            allowsMultipleSelection: true
        ) { result in
            handleImageImport(result)
        }
    }

    private var modeSwitcher: some View {
        Picker("Mode", selection: Binding(
            get: { assistantMode },
            set: { mode in
                onModeChange?(mode)
            }
        )) {
            ForEach(AssistantMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Drag from the left cluster (grip + title).
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: fontSize - 1, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Cueglass")
                    .font(.system(size: fontSize + 4, weight: .semibold, design: .rounded))
                StatusBadge(
                    status: session.status,
                    blinkEnabled: statusBlinkEnabled,
                    isArmed: !isWhisper && session.isListenArmed
                )
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background {
                WindowDragRegion(isEnabled: !session.isPositionLocked)
            }
            .help(session.isPositionLocked ? "Position locked — unlock to drag" : "Drag here to move")

            Spacer(minLength: 8)

            if blindModeEnabled {
                Image(systemName: "eye.slash.fill")
                    .foregroundStyle(.green)
                    .help("Blind on — hidden from most screen shares")
            }
            if session.isMicMuted {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.orange)
                    .help("Mic muted")
            }
            if session.isClickThrough {
                Image(systemName: "hand.raised.slash")
                    .help("Click-through enabled")
            }

            if !isWhisper {
                Button {
                    Task { await session.toggleMicMute() }
                } label: {
                    Image(systemName: session.isMicMuted ? "mic.slash.fill" : "mic.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(session.isMicMuted ? Color.orange : Color.primary)
                .disabled(!session.isRunning && !session.isListenArmed)
                .help(session.isMicMuted ? "Unmute microphone" : "Mute microphone")
            }

            Button {
                onToggleBlind?()
            } label: {
                Image(systemName: blindModeEnabled ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(blindModeEnabled ? Color.green : Color.primary)
            .help(blindModeEnabled ? "Blind on — click to show in screen share" : "Blind off — click to hide from screen share")

            Button {
                session.setPositionLocked(!session.isPositionLocked)
                onAppearanceChange?()
            } label: {
                Image(systemName: session.isPositionLocked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.borderless)
            .help(session.isPositionLocked ? "Unlock position" : "Lock position")

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: fontSize))
            }
            .buttonStyle(.borderless)
            .help("Settings")

            if showsCloseButton {
                Button {
                    onCloseOverlay?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: fontSize))
                }
                .buttonStyle(.borderless)
                .help("Close overlay (⌘⇧H)")
            }
        }
        .foregroundStyle(.primary)
    }

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.answeredTurns.isEmpty ? "Answer" : "Answers")
                    .font(.system(size: fontSize - 2, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !session.answeredTurns.isEmpty {
                    Text("\(session.answeredTurns.count)")
                        .font(.system(size: max(9, fontSize - 6), weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear.frame(height: 1).id("answer-top")

                        if session.status == .thinking {
                            Text("Thinking…")
                                .font(.system(size: fontSize - 1))
                                .foregroundStyle(.secondary)
                                .id("thinking")
                        }

                        if session.answeredTurns.isEmpty {
                            MarkdownAnswerView(
                                text: placeholderAnswerText,
                                fontSize: fontSize,
                                isPlaceholder: true
                            )
                        } else {
                            // Newest answers first.
                            ForEach(session.answeredTurns.reversed()) { turn in
                                AnswerTurnBlock(
                                    turn: turn,
                                    fontSize: fontSize,
                                    tint: answerTint(for: turn.index)
                                )
                                .id(turn.id)
                            }
                        }
                    }
                }
                .frame(minHeight: isWhisper ? 160 : 220)
                .frame(maxHeight: .infinity)
                .layoutPriority(isWhisper ? 2 : 1)
                .onChange(of: session.answeredTurns.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("answer-top", anchor: .top)
                    }
                }
                .onChange(of: session.status) { _, status in
                    if status == .thinking {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("answer-top", anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(isWhisper ? 2 : 1)
    }

    private var heardSection: some View {
        HeardTranscriptView(
            text: session.liveTranscript,
            fontSize: fontSize,
            isActive: isHearing,
            isMuted: session.isMicMuted,
            isExpanded: $heardExpanded
        )
    }

    private var askField: some View {
        AskQuestionField(
            text: $draftQuestion,
            fontSize: fontSize,
            isBusy: false,
            canSubmitHeard: session.canSubmitHeard,
            pendingImages: session.pendingImages,
            isFocused: $askFieldFocused,
            onFocus: { onRequestTypingFocus?() },
            onAttachFiles: { showImageImporter = true },
            onPasteImage: {
                _ = session.pasteFromClipboard()
            },
            onRemoveImage: { id in
                session.removeImage(id: id)
            }
        ) {
            let question = draftQuestion
            draftQuestion = ""
            Task { await session.submitAskField(question) }
        }
    }

    private func handleImageImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                _ = session.addImage(fromFileURL: url)
            }
        case .failure:
            break
        }
    }

    private var isHearing: Bool {
        (session.isRunning || session.isListenArmed)
            && !session.isMicMuted
            && session.status != .paused
            && session.status != .idle
    }

    private var placeholderAnswerText: String {
        if isWhisper {
            if session.isWhisperTranscribing { return "Transcribing your question…" }
            if session.status == .thinking { return "Thinking…" }
            return "Tap the mic, ask the question, then Send — or use Screenshot below."
        }
        if session.isListenArmed {
            return "Armed — speak the question, then pause. Smarty answers only on that pause."
        }
        switch session.status {
        case .idle:
            return "Idle. Press Listen for the next question (Start keeps context only)."
        case .listening:
            return "Mic on for context. Press Listen when you want Smarty to answer the next pause."
        case .thinking:
            return "Thinking…"
        case .streaming:
            return "Thinking…"
        case .paused:
            return "Paused. Press Resume to continue."
        case .error(let message):
            return message
        }
    }

    private var whisperCaptureSection: some View {
        let recording = session.isWhisperRecording
        let canSend = session.canSendWhisperRecording
        let busy = session.isWhisperTranscribing || session.status == .thinking

        return VStack(spacing: 10) {
            // ChatGPT-style composer: soft pill, mic + status + send.
            HStack(spacing: 12) {
                Button {
                    Task { await session.toggleWhisperRecording() }
                } label: {
                    ZStack {
                        if recording {
                            Circle()
                                .stroke(Color.red.opacity(0.35), lineWidth: 2)
                                .frame(width: 52, height: 52)
                                .scaleEffect(micPulse ? 1.18 : 1.0)
                                .opacity(micPulse ? 0.35 : 0.9)
                        }
                        Circle()
                            .fill(recording ? Color.red : Color.primary.opacity(0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(recording ? Color.white : Color.primary)
                    }
                    .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .help(recording ? "Pause (optional) — or just tap Send" : "Start recording")

                VStack(alignment: .leading, spacing: 2) {
                    Text(whisperStatusLabel)
                        .font(.system(size: fontSize - 1, weight: .semibold, design: .rounded))
                        .foregroundStyle(recording ? Color.red : Color.primary)
                    Text(whisperHintLabel)
                        .font(.system(size: max(10, fontSize - 4)))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await session.sendWhisperRecording() }
                } label: {
                    Image(systemName: session.isWhisperTranscribing ? "ellipsis" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(canSend && !busy ? Color(nsColor: .windowBackgroundColor) : Color.secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(canSend && !busy ? Color.primary : Color.primary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend || busy)
                .help(recording ? "Stop recording and answer now" : "Send recording for an instant answer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.primary.opacity(recording ? 0.18 : 0.08), lineWidth: 1)
                    )
            }
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)

            if !session.liveTranscript.isEmpty, !recording || session.isWhisperTranscribing {
                Text(session.liveTranscript)
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: session.isWhisperRecording) { _, isRecording in
            if isRecording {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    micPulse = true
                }
            } else {
                micPulse = false
            }
        }
    }

    private var whisperStatusLabel: String {
        if session.isWhisperTranscribing { return "Transcribing" }
        if session.status == .thinking { return "Thinking" }
        if session.isWhisperRecording { return "Listening…" }
        if session.isWhisperRecordingPaused { return "Paused" }
        return "Ask anything"
    }

    private var whisperHintLabel: String {
        if session.isWhisperTranscribing { return "Turning speech into an interview answer" }
        if session.status == .thinking { return "Crafting your response" }
        if session.isWhisperRecording { return "Keep talking — tap Send when you’re done" }
        if session.isWhisperRecordingPaused { return "Tap Send, or mic to resume" }
        return "Tap the mic, then Send while recording"
    }

    private var whisperScreenshotSection: some View {
        Button {
            Task { await session.whisperScreenshotSolve() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshot")
                        .font(.system(size: fontSize - 1, weight: .semibold, design: .rounded))
                    Text("Solve what’s on screen")
                        .font(.system(size: max(10, fontSize - 4)))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(session.status == .thinking || session.isWhisperTranscribing)
    }

    private var whisperUtilityRow: some View {
        HStack(spacing: 8) {
            Button {
                session.copyCurrentAnswer()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(session.currentAnswer.isEmpty)

            Button {
                Task { await session.regenerate() }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .disabled(
                session.currentAnswer.isEmpty
                    || session.status == .thinking
                    || session.isWhisperTranscribing
            )

            Button {
                session.copyTranscriptMarkdown()
            } label: {
                Label("Export MD", systemImage: "square.and.arrow.up")
            }
            .disabled(session.answeredTurns.isEmpty)
            .help("Copy session transcript as Markdown")

            Button(role: .destructive) {
                session.clearContext()
            } label: {
                Label("Clear", systemImage: "trash")
            }

            Spacer()
        }
        .buttonStyle(.borderless)
        .font(.system(size: fontSize - 2))
        .controlSize(.small)
    }

    private var historySection: some View {
        DisclosureGroup(isExpanded: $historyExpanded) {
            if session.history.isEmpty {
                Text("No earlier answers yet.")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(session.history.reversed()) { message in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.role == .assistant ? "Answer" : "Context")
                                    .font(.system(size: fontSize - 3, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(message.content)
                                    .font(.system(size: fontSize - 2))
                                    .lineLimit(4)
                                    .textSelection(.enabled)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(.top, 4)
            }
        } label: {
            HStack(spacing: 6) {
                Text("History")
                    .font(.system(size: fontSize - 2, weight: .medium))
                if !session.history.isEmpty {
                    Text("\(session.history.count)")
                        .font(.system(size: max(9, fontSize - 5), weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if session.isRunning {
                    if session.status == .paused {
                        Button {
                            session.resume()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button {
                            session.pause()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.borderless)
                    }

                    Button {
                        Task { await session.stopSession() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        Task { await session.startSession() }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    Task { await session.toggleMicMute() }
                } label: {
                    Label(
                        session.isMicMuted ? "Unmute" : "Mute",
                        systemImage: session.isMicMuted ? "mic.slash.fill" : "mic.fill"
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(session.isMicMuted ? Color.orange : Color.primary)
                .disabled(!session.isRunning && !session.isListenArmed)
                .help(session.isMicMuted ? "Unmute microphone" : "Mute microphone (ignore speech)")

                Button {
                    session.copyCurrentAnswer()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(session.currentAnswer.isEmpty)

                Button {
                    session.copyTranscriptMarkdown()
                } label: {
                    Label("Export MD", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(session.answeredTurns.isEmpty)
                .help("Copy session transcript as Markdown")

                Button(role: .destructive) {
                    session.clearContext()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    Task { await session.regenerate() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .disabled(
                    session.currentAnswer.isEmpty
                        || session.status == .paused
                        || session.status == .thinking
                        || session.status == .streaming
                )

                Button {
                    Task { await session.listenOnce() }
                } label: {
                    Label(session.isListenArmed ? "Listening…" : "Listen", systemImage: session.isListenArmed ? "waveform" : "mic.fill")
                }
                .disabled(session.isListenArmed || session.status == .paused)
                .foregroundStyle(session.isListenArmed ? Color.green : Color.primary)

                Button {
                    Task { await session.screenshotSolve() }
                } label: {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                }
                .disabled(session.status == .thinking || session.status == .streaming)

                Spacer()
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: fontSize - 2))
        .controlSize(.small)
    }
}

/// Soft alternating tag colors for answer cards (odd → green, even → blue).
private func answerTint(for index: Int) -> Color {
    index % 2 == 1
        ? Color(red: 0.30, green: 0.72, blue: 0.48)
        : Color(red: 0.32, green: 0.55, blue: 0.92)
}

private struct AnswerTurnBlock: View {
    let turn: AnswerTurn
    let fontSize: Double
    var tint: Color = Color(red: 0.30, green: 0.72, blue: 0.48)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Q\(turn.index)")
                    .font(.system(size: max(10, fontSize - 4), weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: Capsule())
                Text(turn.question)
                    .font(.system(size: fontSize - 1, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            answerLane(
                title: "Technical (spoken)",
                subtitle: "Read this aloud",
                text: turn.technicalAnswer,
                pending: false
            )

            answerLane(
                title: "Simple",
                subtitle: "Quick understanding — not for reading aloud",
                text: turn.friendlyAnswer,
                pending: turn.isFriendlyPending
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func answerLane(title: String, subtitle: String, text: String, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: fontSize - 3, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("· \(subtitle)")
                    .font(.system(size: max(9, fontSize - 5)))
                    .foregroundStyle(.tertiary)
            }
            if pending {
                Text("Writing a simple version…")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
            } else if !text.isEmpty {
                MarkdownAnswerView(text: text, fontSize: fontSize, isPlaceholder: false)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    OverlayView(
        session: InterviewSessionManager.preview,
        fontSize: 14,
        opacity: 0.92
    )
    .frame(width: 440, height: 620)
    .padding()
}
