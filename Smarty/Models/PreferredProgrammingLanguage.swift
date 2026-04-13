import Foundation

enum PreferredProgrammingLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case python
    case javascript
    case typescript
    case java
    case csharp
    case go
    case rust
    case swift
    case kotlin
    case cpp
    case ruby
    case php
    case sql
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .python: return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .java: return "Java"
        case .csharp: return "C#"
        case .go: return "Go"
        case .rust: return "Rust"
        case .swift: return "Swift"
        case .kotlin: return "Kotlin"
        case .cpp: return "C++"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .sql: return "SQL"
        case .auto: return "Auto (let model choose)"
        }
    }

    /// Prompt fragment when a concrete language is preferred.
    var codingInstruction: String? {
        guard self != .auto else { return nil }
        return "When writing coding solutions, prefer \(displayName) unless the interviewer explicitly asks for a different language."
    }
}

enum InterviewFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    case behavioral
    case coding
    case systemDesign
    case mixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .behavioral: return "Behavioral"
        case .coding: return "Coding"
        case .systemDesign: return "System design"
        case .mixed: return "Mixed"
        }
    }

    var promptGuidance: String {
        switch self {
        case .behavioral:
            return "Session focus: behavioral. Prefer STAR-style spoken stories; de-emphasize code unless asked."
        case .coding:
            return "Session focus: coding / algorithms. Prefer approaches, complexity, and fenced code; keep behavioral stories short."
        case .systemDesign:
            return "Session focus: system design. Emphasize requirements, tradeoffs, components, data flow, and scaling; light code only when useful."
        case .mixed:
            return "Session focus: mixed. Match the answer style to whether the question is behavioral, coding, or system design."
        }
    }
}

enum AnswerLength: String, Codable, CaseIterable, Sendable, Identifiable {
    case concise
    case standard
    case deep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .concise: return "Concise"
        case .standard: return "Standard"
        case .deep: return "Deep"
        }
    }

    var promptGuidance: String {
        switch self {
        case .concise:
            return "Answer length: concise — aim for ~20–40 seconds of speech; one strong approach unless variations are essential."
        case .standard:
            return "Answer length: standard — about 30–90 seconds of speech; coding may include 2–3 variations when useful."
        case .deep:
            return "Answer length: deep — more thorough explanations, tradeoffs, and edge cases; coding may expand variations and complexity discussion."
        }
    }
}
