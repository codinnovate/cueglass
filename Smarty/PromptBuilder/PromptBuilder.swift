import Foundation

struct PromptBuilder: Sendable {
    func build(
        systemTemplate: String,
        snapshot: ContextSnapshot,
        preferredLanguage: PreferredProgrammingLanguage = .python,
        interviewFocus: InterviewFocus = .mixed,
        answerLength: AnswerLength = .standard
    ) -> (instructions: String, input: String) {
        var instructions = systemTemplate.trimmed.isEmpty
            ? AppSettings.defaultPromptTemplate
            : systemTemplate

        var guidance: [String] = [
            interviewFocus.promptGuidance,
            answerLength.promptGuidance
        ]
        if let languageLine = preferredLanguage.codingInstruction {
            guidance.append(languageLine)
        }
        instructions += "\n\n" + guidance.joined(separator: "\n")

        var sections: [String] = []

        if !snapshot.summary.isBlank {
            sections.append("## Prior context summary\n\(snapshot.summary)")
        }
        if !snapshot.topic.isBlank {
            sections.append("## Current interview topic\n\(snapshot.topic)")
        }
        if !snapshot.ocr.isBlank {
            sections.append("## Recent screen text (OCR)\n\(snapshot.ocr)")
        }
        if !snapshot.transcript.isBlank {
            sections.append("## Recent spoken transcript\n\(snapshot.transcript)")
        }

        if !snapshot.conversation.isEmpty {
            let history = snapshot.conversation.map { message in
                "\(message.role.rawValue.uppercased()): \(message.content)"
            }.joined(separator: "\n")
            sections.append("## Recent assistant answers\n\(history)")
        }

        sections.append(
            """
            ## Task
            Using the interview context above, craft the next answer for the candidate as spoken conversational words —
            an explanation they can read aloud, not a formal description. Prefer natural first-person talk.
            Light everyday grammar is fine; keep technical terms accurate.

            Prefer the spoken transcript as the question when both speech and OCR are present.
            Screen OCR is supporting context only unless the user explicitly asked to solve the screen.

            Speech transcripts may contain ASR errors, especially with accents or technical terms.
            Infer the intended interview question (e.g. "active fiber" / "virtual" → React Fiber vs Virtual DOM) using context; do not answer the garbled literal if a clear tech topic is obvious.

            If this is an algorithm, coding, or DSA problem (spoken, typed, or on-screen OCR):
            - Always provide multiple solution variations when possible (typically 2–3) — every time.
            - Include a brute-force/simple approach and an optimized approach at minimum; add a third alternate/tradeoff when useful.
            - For each variation: brief spoken-style approach, time/space complexity, then a focused fenced code block.
            - Label each variation clearly.
            - Use markdown as needed for structure, examples, and code.

            If this is behavioral or conversational (not a coding problem):
            - Respond with one natural first-person spoken answer only — no preamble, no labels, no markdown headings.
            """
        )

        var input = sections.joined(separator: "\n\n")
        let budget = max(500, snapshot.maxTokens - TokenEstimator.estimateTokens(in: instructions) - 200)
        input = TokenEstimator.truncateToTokenBudget(input, maxTokens: budget)
        return (instructions, input)
    }

    func summarizationPrompt(from snapshot: ContextSnapshot) -> (instructions: String, input: String) {
        let instructions = "Summarize the following interview context into a compact paragraph. Preserve key facts, questions, and prior answers. Omit fluff."
        let input = TokenEstimator.truncateToTokenBudget(snapshot.combinedRaw, maxTokens: 3500)
        return (instructions, input)
    }

    /// Compact guidance injected into the live technical answer path.
    static func sessionGuidance(
        language: PreferredProgrammingLanguage,
        focus: InterviewFocus,
        length: AnswerLength
    ) -> String {
        var lines = [focus.promptGuidance, length.promptGuidance]
        if let languageLine = language.codingInstruction {
            lines.append(languageLine)
        }
        return lines.joined(separator: "\n")
    }
}

actor ContextSummarizer {
    private let openAI: OpenAIClienting
    private let builder = PromptBuilder()

    init(openAI: OpenAIClienting) {
        self.openAI = openAI
    }

    func summarizeIfNeeded(
        apiKey: String,
        model: String,
        store: ContextStore,
        maxTokens: Int
    ) async {
        let needs = await store.needsSummarization(maxTokens: maxTokens)
        guard needs else { return }

        let snapshot = await store.snapshotForPrompt(maxTokens: maxTokens)
        let prompt = builder.summarizationPrompt(from: snapshot)

        do {
            let summary = try await openAI.complete(
                apiKey: apiKey,
                request: OpenAIRequest(
                    model: model,
                    instructions: prompt.instructions,
                    input: prompt.input,
                    temperature: 0.2,
                    stream: false
                )
            )
            await store.replaceSummary(summary)
            // Drop older conversation once summarized
            // Keep last few messages only — handled by store limits.
        } catch {
            AppLog.openai.error("Summarization failed: \(error.localizedDescription)")
            // Local fallback: truncate summary from existing text
            let fallback = TokenEstimator.truncateToTokenBudget(snapshot.combinedRaw, maxTokens: 400)
            await store.replaceSummary(fallback)
        }
    }
}
