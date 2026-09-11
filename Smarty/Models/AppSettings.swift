import Foundation
import CoreGraphics

struct AppSettings: Codable, Equatable, Sendable {
    var provider: AIProvider
    var model: String
    var temperature: Double
    var captureInterval: TimeInterval
    var overlayOpacity: Double
    var overlayFontSize: Double
    var promptTemplate: String
    var selectedMicrophoneUID: String?
    var selectedDisplayID: UInt32?
    var streamingEnabled: Bool
    var launchAtLogin: Bool
    var clickThroughEnabled: Bool
    var positionLocked: Bool
    /// Requests best-effort window exclusion; recording apps may still capture Smarty.
    var blindModeEnabled: Bool
    /// When true, the status badge pulses while listening / thinking.
    var statusBlinkEnabled: Bool
    /// Menu bar item; the overlay can also be restored using ⌘⇧H or by reopening the app.
    /// Note the menu bar itself is never hidden by blind mode; turn this off for a clean share.
    var showMenuBarIcon: Bool
    /// Whisper = manual record/send; Stream = Listen + pause VAD (legacy session UI).
    var assistantMode: AssistantMode
    var overlayFrame: CodableRect?
    var minRequestInterval: TimeInterval
    var pauseDetectionSeconds: TimeInterval
    var maxContextTokens: Int
    var preferredProgrammingLanguage: PreferredProgrammingLanguage
    var interviewFocus: InterviewFocus
    var answerLength: AnswerLength
    /// The role the candidate is interviewing for — drives how every answer is framed.
    var roleProfile: RoleProfile

    static let defaultPromptTemplate = """
    You are a discreet interview assistant helping the candidate answer live interview questions.

    Follow the role brief supplied below: the candidate may be interviewing for any kind of job,
    not only software. Use that role's vocabulary, frameworks, and measures of success.

    Write answers as spoken conversational explanations the candidate can read aloud —
    like talking through the idea with the interviewer, not a stiff textbook description.
    First person. Natural cadence. Light everyday grammar is fine (contractions, short sentences).
    Domain terms must stay precise and correct — never invent or blur jargon.
    Markdown is welcome for structure, short lists, examples, and fenced code when it helps.
    Avoid bullet points for purely behavioral answers unless the interviewer asks for a list.
    Keep answers concise enough to speak in about 30–90 seconds (coding solutions may run longer).
    Avoid repeating previous responses.
    Do not invent specific employers, projects, metrics, or technologies that are not in the provided context.
    If information is missing, give a generic but believable professional answer.

    For coding / algorithm / DSA interviews (only when the role is a technical one):
    - Always give multiple solution variations when possible (usually 2–3), every time.
    - Typical set: (1) brute-force / straightforward, (2) optimal, (3) an alternate approach or tradeoff when useful.
    - For each variation: short spoken-style approach, time/space complexity, then a focused fenced code block.
    - Label variations clearly (e.g. Variation 1 — Brute force).
    - Prefer readable interview-style code over huge dumps.
    - Still follow all honesty and context rules above.

    For non-technical roles:
    - Do not volunteer code, algorithms, or complexity analysis.
    - Answer with the tools of that field: frameworks, process, metrics, case structure, or a worked calculation.

    For behavioral interviews:
    - Use STAR structure internally (Situation, Task, Action, Result).
    - Do NOT label the STAR sections out loud.
    - Produce responses that sound like natural speech.

    """ + InlineTechnicalExplanationFormat.rules

    static let `default` = AppSettings(
        provider: .openAI,
        model: "gpt-4o-mini",
        temperature: 0.7,
        captureInterval: 1.0,
        overlayOpacity: 0.92,
        overlayFontSize: 17,
        promptTemplate: defaultPromptTemplate,
        selectedMicrophoneUID: nil,
        selectedDisplayID: nil,
        streamingEnabled: false,
        launchAtLogin: false,
        clickThroughEnabled: false,
        positionLocked: false,
        blindModeEnabled: true,
        statusBlinkEnabled: true,
        showMenuBarIcon: true,
        assistantMode: .whisper,
        overlayFrame: nil,
        minRequestInterval: 1.0,
        pauseDetectionSeconds: 0.85,
        maxContextTokens: 6000,
        preferredProgrammingLanguage: .python,
        interviewFocus: .mixed,
        answerLength: .standard,
        roleProfile: .default
    )

    init(
        provider: AIProvider,
        model: String,
        temperature: Double,
        captureInterval: TimeInterval,
        overlayOpacity: Double,
        overlayFontSize: Double,
        promptTemplate: String,
        selectedMicrophoneUID: String?,
        selectedDisplayID: UInt32?,
        streamingEnabled: Bool,
        launchAtLogin: Bool,
        clickThroughEnabled: Bool,
        positionLocked: Bool,
        blindModeEnabled: Bool,
        statusBlinkEnabled: Bool,
        showMenuBarIcon: Bool = true,
        assistantMode: AssistantMode,
        overlayFrame: CodableRect?,
        minRequestInterval: TimeInterval,
        pauseDetectionSeconds: TimeInterval,
        maxContextTokens: Int,
        preferredProgrammingLanguage: PreferredProgrammingLanguage,
        interviewFocus: InterviewFocus,
        answerLength: AnswerLength,
        roleProfile: RoleProfile = .default
    ) {
        self.provider = provider
        self.model = model
        self.temperature = temperature
        self.captureInterval = captureInterval
        self.overlayOpacity = overlayOpacity
        self.overlayFontSize = overlayFontSize
        self.promptTemplate = promptTemplate
        self.selectedMicrophoneUID = selectedMicrophoneUID
        self.selectedDisplayID = selectedDisplayID
        self.streamingEnabled = streamingEnabled
        self.launchAtLogin = launchAtLogin
        self.clickThroughEnabled = clickThroughEnabled
        self.positionLocked = positionLocked
        self.blindModeEnabled = blindModeEnabled
        self.statusBlinkEnabled = statusBlinkEnabled
        self.showMenuBarIcon = showMenuBarIcon
        self.assistantMode = assistantMode
        self.overlayFrame = overlayFrame
        self.minRequestInterval = minRequestInterval
        self.pauseDetectionSeconds = pauseDetectionSeconds
        self.maxContextTokens = maxContextTokens
        self.preferredProgrammingLanguage = preferredProgrammingLanguage
        self.interviewFocus = interviewFocus
        self.answerLength = answerLength
        self.roleProfile = roleProfile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? d.provider
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? d.temperature
        captureInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .captureInterval) ?? d.captureInterval
        overlayOpacity = try c.decodeIfPresent(Double.self, forKey: .overlayOpacity) ?? d.overlayOpacity
        overlayFontSize = try c.decodeIfPresent(Double.self, forKey: .overlayFontSize) ?? 17
        promptTemplate = try c.decodeIfPresent(String.self, forKey: .promptTemplate) ?? d.promptTemplate
        selectedMicrophoneUID = try c.decodeIfPresent(String.self, forKey: .selectedMicrophoneUID)
        selectedDisplayID = try c.decodeIfPresent(UInt32.self, forKey: .selectedDisplayID)
        streamingEnabled = try c.decodeIfPresent(Bool.self, forKey: .streamingEnabled) ?? d.streamingEnabled
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        clickThroughEnabled = try c.decodeIfPresent(Bool.self, forKey: .clickThroughEnabled) ?? d.clickThroughEnabled
        positionLocked = try c.decodeIfPresent(Bool.self, forKey: .positionLocked) ?? d.positionLocked
        blindModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .blindModeEnabled) ?? true
        statusBlinkEnabled = try c.decodeIfPresent(Bool.self, forKey: .statusBlinkEnabled) ?? true
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        assistantMode = try c.decodeIfPresent(AssistantMode.self, forKey: .assistantMode) ?? .whisper
        overlayFrame = try c.decodeIfPresent(CodableRect.self, forKey: .overlayFrame)
        minRequestInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .minRequestInterval) ?? d.minRequestInterval
        pauseDetectionSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .pauseDetectionSeconds) ?? d.pauseDetectionSeconds
        maxContextTokens = try c.decodeIfPresent(Int.self, forKey: .maxContextTokens) ?? d.maxContextTokens
        preferredProgrammingLanguage = try c.decodeIfPresent(PreferredProgrammingLanguage.self, forKey: .preferredProgrammingLanguage) ?? d.preferredProgrammingLanguage
        interviewFocus = try c.decodeIfPresent(InterviewFocus.self, forKey: .interviewFocus) ?? d.interviewFocus
        answerLength = try c.decodeIfPresent(AnswerLength.self, forKey: .answerLength) ?? d.answerLength
        roleProfile = try c.decodeIfPresent(RoleProfile.self, forKey: .roleProfile) ?? d.roleProfile
    }
}

struct CodableRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
