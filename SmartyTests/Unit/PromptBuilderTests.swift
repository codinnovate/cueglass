import XCTest
@testable import Smarty

final class PromptBuilderTests: XCTestCase {
    let builder = PromptBuilder()

    func testEmptyTemplateUsesDefault() {
        let snapshot = ContextSnapshot(
            summary: "",
            topic: "",
            transcript: "Tell me about yourself",
            ocr: "",
            conversation: [],
            maxTokens: 2000
        )
        let prompt = builder.build(systemTemplate: "   ", snapshot: snapshot)
        XCTAssertTrue(prompt.instructions.contains("interview assistant"))
        XCTAssertTrue(prompt.input.contains("Tell me about yourself"))
    }

    func testMergesOCRAndTranscript() {
        let snapshot = ContextSnapshot(
            summary: "Prior summary",
            topic: "Algorithms",
            transcript: "How would you reverse a linked list?",
            ocr: "Write a function reverseList",
            conversation: [ConversationMessage(role: .assistant, content: "Earlier answer")],
            maxTokens: 4000
        )
        let prompt = builder.build(systemTemplate: "Be concise.", snapshot: snapshot)
        XCTAssertTrue(prompt.instructions.hasPrefix("Be concise."))
        XCTAssertTrue(prompt.input.contains("Prior summary"))
        XCTAssertTrue(prompt.input.contains("Algorithms"))
        XCTAssertTrue(prompt.input.contains("reverseList"))
        XCTAssertTrue(prompt.input.contains("linked list"))
        XCTAssertTrue(prompt.input.contains("Earlier answer"))
    }

    func testRespectsTokenBudget() {
        let huge = String(repeating: "word ", count: 5000)
        let snapshot = ContextSnapshot(
            summary: huge,
            topic: huge,
            transcript: huge,
            ocr: huge,
            conversation: [],
            maxTokens: 200
        )
        let prompt = builder.build(systemTemplate: "x", snapshot: snapshot)
        // Budget floors at 500 tokens (~2000 chars) even when maxTokens is tiny.
        XCTAssertLessThan(prompt.input.count, huge.count)
        XCTAssertTrue(prompt.input.contains("…") || prompt.input.count <= 2500)
    }

    func testPreferredLanguageInjectedWhenNotAuto() {
        let snapshot = ContextSnapshot(
            summary: "",
            topic: "",
            transcript: "Write two sum",
            ocr: "",
            conversation: [],
            maxTokens: 2000
        )
        let withSwift = builder.build(
            systemTemplate: "Base.",
            snapshot: snapshot,
            preferredLanguage: .swift,
            interviewFocus: .coding,
            answerLength: .concise,
            role: RoleProfile(title: "Backend Engineer", field: .software)
        )
        XCTAssertTrue(withSwift.instructions.contains("prefer Swift"))
        XCTAssertTrue(withSwift.instructions.contains("Session focus: coding"))
        XCTAssertTrue(withSwift.instructions.contains("Answer length: concise"))

        let auto = builder.build(
            systemTemplate: "Base.",
            snapshot: snapshot,
            preferredLanguage: .auto,
            interviewFocus: .mixed,
            answerLength: .standard
        )
        XCTAssertFalse(auto.instructions.contains("prefer "))
        XCTAssertTrue(auto.instructions.contains("Session focus: mixed"))
    }

    func testRoleProfileFramesTheAnswer() {
        let snapshot = ContextSnapshot(
            summary: "",
            topic: "",
            transcript: "How do you prioritise a roadmap?",
            ocr: "",
            conversation: [],
            maxTokens: 2000
        )
        let role = RoleProfile(
            field: .product,
            notes: "Marketplace team, heavy on experimentation."
        )
        let prompt = builder.build(
            systemTemplate: "Base.",
            snapshot: snapshot,
            preferredLanguage: .swift,
            interviewFocus: .mixed,
            answerLength: .standard,
            role: role
        )

        XCTAssertTrue(prompt.instructions.contains("Field: product management"))
        XCTAssertTrue(prompt.instructions.contains("Marketplace team"))
        // Non-technical role: no language preference, no coding mandate.
        XCTAssertFalse(prompt.instructions.contains("prefer Swift"))
        XCTAssertTrue(prompt.instructions.contains("Do not treat this as a software engineering interview"))
        XCTAssertFalse(prompt.input.contains("solution variations"))
    }

    func testTechnicalRoleKeepsCodingMandate() {
        let snapshot = ContextSnapshot(
            summary: "",
            topic: "",
            transcript: "Reverse a linked list",
            ocr: "",
            conversation: [],
            maxTokens: 2000
        )
        let prompt = builder.build(
            systemTemplate: "Base.",
            snapshot: snapshot,
            preferredLanguage: .swift,
            interviewFocus: .coding,
            answerLength: .standard,
            role: RoleProfile(title: "Backend Engineer", field: .software)
        )

        XCTAssertTrue(prompt.instructions.contains("prefer Swift"))
        XCTAssertFalse(prompt.instructions.contains("Do not treat this as a software engineering interview"))
        XCTAssertTrue(prompt.input.contains("solution variations"))
    }

    func testDataAnnotationRoleIsFramedForRubricWork() {
        let guidance = PromptBuilder.sessionGuidance(
            language: .python,
            focus: .mixed,
            length: .standard,
            role: RoleProfile(title: "AI Training Specialist", field: .dataAnnotation)
        )
        XCTAssertTrue(guidance.contains("Field: data annotation"))
        XCTAssertTrue(guidance.contains("guidelines"))
        // Auto: annotation is non-technical by default, so code stays out.
        XCTAssertFalse(guidance.contains("prefer Python"))
    }

    func testCodingPreferenceOverridesTheField() {
        // Annotation project that does involve code — force it back on.
        let forcedOn = RoleProfile(
            title: "AI Training Specialist",
            field: .dataAnnotation,
            codingPreference: .include
        )
        XCTAssertTrue(forcedOn.expectsCoding)
        XCTAssertFalse(forcedOn.promptGuidance.contains("Do not volunteer code"))

        // Software role where the candidate wants prose only.
        let forcedOff = RoleProfile(title: "Engineering Manager", field: .software, codingPreference: .exclude)
        XCTAssertFalse(forcedOff.expectsCoding)
        XCTAssertTrue(forcedOff.promptGuidance.contains("Do not volunteer code"))

        // Auto still follows the field.
        XCTAssertTrue(RoleProfile(field: .software).expectsCoding)
        XCTAssertFalse(RoleProfile(field: .generalist).expectsCoding)
        XCTAssertFalse(RoleProfile().expectsCoding)
    }

    func testAnnotationPromptOverridesDefaultSoftwareField() {
        let leftoverSoftwarePicker = RoleProfile(
            field: .software,
            notes: "This is an AI data annotation assessment."
        )
        XCTAssertEqual(leftoverSoftwarePicker.effectiveField, .dataAnnotation)
        XCTAssertFalse(leftoverSoftwarePicker.expectsCoding)
        XCTAssertTrue(leftoverSoftwarePicker.promptGuidance.contains("data annotation"))
        XCTAssertTrue(leftoverSoftwarePicker.promptGuidance.contains("not Software engineering"))

        let explicitSoftware = RoleProfile(field: .software)
        XCTAssertEqual(explicitSoftware.effectiveField, .software)
        XCTAssertTrue(explicitSoftware.expectsCoding)
    }

    func testMixedFocusAvoidsSoftwareFramingForAnnotation() {
        let guidance = PromptBuilder.sessionGuidance(
            language: .python,
            focus: .mixed,
            length: .standard,
            role: RoleProfile(title: "AI Training Specialist", field: .dataAnnotation)
        )
        XCTAssertTrue(guidance.contains("Do not slip into software-engineering"))
        XCTAssertFalse(guidance.contains("coding, or system design"))
    }

    func testEveryFieldHasGuidanceAndACategory() {
        for field in InterviewRoleField.allCases {
            XCTAssertTrue(field.promptGuidance.hasPrefix("Field: "), "\(field.rawValue) guidance")
            XCTAssertFalse(field.displayName.isEmpty, "\(field.rawValue) name")
            XCTAssertTrue(
                InterviewRoleCategory(rawValue: field.category.rawValue) != nil,
                "\(field.rawValue) category"
            )
        }
        // Every field appears in exactly one picker group.
        let grouped = InterviewRoleCategory.allCases.flatMap(\.fields)
        XCTAssertEqual(grouped.count, InterviewRoleField.allCases.count)
        XCTAssertEqual(Set(grouped), Set(InterviewRoleField.allCases))
        XCTAssertEqual(InterviewRoleField.seniorAITrainer.displayName, "Senior AI trainer")
        XCTAssertEqual(InterviewRoleField.videoAnnotationExpert.displayName, "Video Annotation Expert")
        XCTAssertEqual(InterviewRoleField.generalist.displayName, "Generalist")
        XCTAssertEqual(InterviewRoleCategory.aiTraining.fields.first, .seniorAITrainer)
    }

    func testSessionGuidanceCarriesRole() {
        let guidance = PromptBuilder.sessionGuidance(
            language: .python,
            focus: .behavioral,
            length: .concise,
            role: RoleProfile(title: "Registered Nurse", field: .healthcare)
        )
        XCTAssertTrue(guidance.contains("Field: healthcare"))
        XCTAssertFalse(guidance.contains("prefer Python"))
    }
}
