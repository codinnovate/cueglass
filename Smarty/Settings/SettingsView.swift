import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        TabView {
            APISettingsSection()
                .tabItem { Label("API", systemImage: "key") }

            CaptureSettingsSection()
                .tabItem { Label("Capture", systemImage: "rectangle.dashed.badge.record") }

            OverlaySettingsSection()
                .tabItem { Label("Overlay", systemImage: "menubar.rectangle") }

            PromptSettingsSection()
                .tabItem { Label("Prompt", systemImage: "text.alignleft") }

            GeneralSettingsSection()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(20)
        .environment(appEnvironment)
        .onAppear {
            appEnvironment.overlayManager.applyScreenShareExclusionToAllWindows()
        }
        .onChange(of: appEnvironment.settingsStore.settings) { _, _ in
            appEnvironment.overlayManager.refresh(session: appEnvironment.session)
        }
    }
}

struct APISettingsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var revealKey = false
    @State private var draftKey = ""
    @State private var saveMessage: String?
    @State private var saveIsError = false

    private var store: SettingsStore { appEnvironment.settingsStore }

    var body: some View {
        Form {
            Section("OpenAI") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if revealKey {
                            TextField("sk-...", text: $draftKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $draftKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(revealKey ? "Hide" : "Show") {
                            revealKey.toggle()
                        }
                    }

                    HStack {
                        Button("Save API Key") {
                            saveKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && !store.hasAPIKey)

                        if store.hasAPIKey {
                            Label("Key saved in Keychain", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        } else {
                            Label("No key saved yet", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                    }

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(saveIsError ? .red : .secondary)
                    }

                    Text("Paste your key, then click Save. The Start button stays disabled until a key is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Model", selection: Binding(
                    get: { store.settings.model },
                    set: { value in store.update { $0.model = value } }
                )) {
                    ForEach(AppSettings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                HStack {
                    Text("Temperature")
                    Slider(
                        value: Binding(
                            get: { store.settings.temperature },
                            set: { value in store.update { $0.temperature = value } }
                        ),
                        in: 0...1,
                        step: 0.05
                    )
                    Text(store.settings.temperature, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                Text("Answers load in one shot (streaming to the overlay is disabled for a snappier UI).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Request Throttling") {
                HStack {
                    Text("Min interval (sec)")
                    TextField(
                        "",
                        value: Binding(
                            get: { store.settings.minRequestInterval },
                            set: { value in store.update { $0.minRequestInterval = max(0.5, value) } }
                        ),
                        format: .number
                    )
                    .frame(width: 70)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            draftKey = store.apiKey
            saveMessage = nil
        }
    }

    private func saveKey() {
        switch store.saveAPIKey(draftKey) {
        case .success:
            draftKey = store.apiKey
            saveIsError = false
            saveMessage = store.hasAPIKey ? "API key saved." : "API key cleared."
        case .failure(let error):
            saveIsError = true
            saveMessage = error.localizedDescription
        }
    }
}

struct CaptureSettingsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var displays: [DisplayInfo] = []
    @State private var microphones: [MicrophoneInfo] = []

    private var store: SettingsStore { appEnvironment.settingsStore }

    var body: some View {
        Form {
            Section("Screen") {
                HStack {
                    Text("Capture interval (sec)")
                    Slider(
                        value: Binding(
                            get: { store.settings.captureInterval },
                            set: { value in
                                store.update { $0.captureInterval = value }
                                Task {
                                    await appEnvironment.screenCapture.updateInterval(value)
                                }
                            }
                        ),
                        in: 0.5...5,
                        step: 0.25
                    )
                    Text(store.settings.captureInterval, format: .number.precision(.fractionLength(2)))
                        .frame(width: 40, alignment: .trailing)
                }

                Picker("Display", selection: Binding(
                    get: { store.settings.selectedDisplayID ?? displays.first?.id },
                    set: { value in store.update { $0.selectedDisplayID = value } }
                )) {
                    Text("Default").tag(Optional<UInt32>.none)
                    ForEach(displays) { display in
                        Text("\(display.name) (\(display.width)×\(display.height))")
                            .tag(Optional(display.id))
                    }
                }
            }

            Section("Microphone") {
                Picker("Input", selection: Binding(
                    get: { store.settings.selectedMicrophoneUID },
                    set: { value in store.update { $0.selectedMicrophoneUID = value } }
                )) {
                    Text("System Default").tag(Optional<String>.none)
                    ForEach(microphones) { mic in
                        Text(mic.name).tag(Optional(mic.id))
                    }
                }

                HStack {
                    Text("Pause detection (sec)")
                    TextField(
                        "",
                        value: Binding(
                            get: { store.settings.pauseDetectionSeconds },
                            set: { value in store.update { $0.pauseDetectionSeconds = max(0.4, value) } }
                        ),
                        format: .number
                    )
                    .frame(width: 70)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            displays = (try? await appEnvironment.screenCapture.availableDisplays()) ?? []
            microphones = await SpeechRecognitionService().availableMicrophones()
        }
    }
}

struct OverlaySettingsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    private var store: SettingsStore { appEnvironment.settingsStore }

    var body: some View {
        Form {
            Section("Appearance") {
                HStack {
                    Text("Opacity")
                    Slider(
                        value: Binding(
                            get: { store.settings.overlayOpacity },
                            set: { value in store.update { $0.overlayOpacity = value } }
                        ),
                        in: 0.4...1.0,
                        step: 0.05
                    )
                }

                HStack {
                    Text("Font size")
                    Slider(
                        value: Binding(
                            get: { store.settings.overlayFontSize },
                            set: { value in
                                store.update { $0.overlayFontSize = value }
                                appEnvironment.overlayManager.refresh(session: appEnvironment.session)
                            }
                        ),
                        in: 12...24,
                        step: 1
                    )
                    Text(Int(store.settings.overlayFontSize), format: .number)
                        .frame(width: 30, alignment: .trailing)
                }
                Text("Default is 17. Applies to answers, key terms, and overlay chrome.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Picker("Assistant mode", selection: Binding(
                    get: { store.settings.assistantMode },
                    set: { mode in
                        Task { await appEnvironment.session.setAssistantMode(mode) }
                        appEnvironment.overlayManager.refresh(session: appEnvironment.session)
                    }
                )) {
                    ForEach(AssistantMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Whisper = record + Send. Stream = Listen with pause detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Blind mode (hide from screen share)", isOn: Binding(
                    get: { store.settings.blindModeEnabled },
                    set: { value in
                        appEnvironment.overlayManager.setBlindMode(value, session: appEnvironment.session)
                    }
                ))
                Text("On by default. Uses window sharing exclusion so Zoom/Meet usually won’t show Cueglass.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Status blink", isOn: Binding(
                    get: { store.settings.statusBlinkEnabled },
                    set: { value in
                        store.update { $0.statusBlinkEnabled = value }
                        appEnvironment.overlayManager.refresh(session: appEnvironment.session)
                    }
                ))
                Text("Pulses the status badge while listening or thinking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Click-through", isOn: Binding(
                    get: { store.settings.clickThroughEnabled },
                    set: { value in
                        store.update { $0.clickThroughEnabled = value }
                        appEnvironment.session.setClickThrough(value)
                    }
                ))
                Toggle("Lock position", isOn: Binding(
                    get: { store.settings.positionLocked },
                    set: { value in
                        store.update { $0.positionLocked = value }
                        appEnvironment.session.setPositionLocked(value)
                    }
                ))
            }

            Section("Shortcuts") {
                LabeledContent("Show / Hide Overlay", value: "⌘⇧H")
                LabeledContent("Pause / Resume", value: "⌘⇧P")
                LabeledContent("Start Session", value: "⌘⇧S")
            }
        }
        .formStyle(.grouped)
    }
}

struct PromptSettingsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    private var store: SettingsStore { appEnvironment.settingsStore }

    var body: some View {
        Form {
            Section("Session Presets") {
                Picker("Interview focus", selection: Binding(
                    get: { store.settings.interviewFocus },
                    set: { value in store.update { $0.interviewFocus = value } }
                )) {
                    ForEach(InterviewFocus.allCases) { focus in
                        Text(focus.displayName).tag(focus)
                    }
                }

                Picker("Answer length", selection: Binding(
                    get: { store.settings.answerLength },
                    set: { value in store.update { $0.answerLength = value } }
                )) {
                    ForEach(AnswerLength.allCases) { length in
                        Text(length.displayName).tag(length)
                    }
                }

                Picker("Preferred language", selection: Binding(
                    get: { store.settings.preferredProgrammingLanguage },
                    set: { value in store.update { $0.preferredProgrammingLanguage = value } }
                )) {
                    ForEach(PreferredProgrammingLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Text("Used for coding solutions. Auto lets the model pick.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System Prompt") {
                TextEditor(
                    text: Binding(
                        get: { store.settings.promptTemplate },
                        set: { value in store.update { $0.promptTemplate = value } }
                    )
                )
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 280)

                HStack {
                    Button("Reset to Default") {
                        store.resetPromptTemplate()
                    }
                    Spacer()
                    HStack {
                        Text("Max context tokens")
                        TextField(
                            "",
                            value: Binding(
                                get: { store.settings.maxContextTokens },
                                set: { value in store.update { $0.maxContextTokens = max(1000, value) } }
                            ),
                            format: .number
                        )
                        .frame(width: 80)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettingsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var launchError: String?

    private var store: SettingsStore { appEnvironment.settingsStore }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { enabled in
                        do {
                            try appEnvironment.launchAtLogin.setEnabled(enabled)
                            store.update { $0.launchAtLogin = enabled }
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }
                ))
                if let launchError {
                    Text(launchError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Data") {
                Button("Export Transcript as Markdown") {
                    appEnvironment.session.copyTranscriptMarkdown()
                }
                .disabled(appEnvironment.session.answeredTurns.isEmpty)

                Button("Clear Recent History", role: .destructive) {
                    appEnvironment.session.clearContext()
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                Text("Blind mode uses NSWindow.sharingType = .none. Most meeting apps hide Cueglass; some full-display ScreenCaptureKit capturers on macOS 15+ may still show composited pixels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.shared)
        .frame(width: 600, height: 520)
}
