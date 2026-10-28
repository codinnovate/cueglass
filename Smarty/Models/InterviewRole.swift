import Foundation

/// Broad field of the role the candidate is interviewing for.
/// Drives how answers are framed and whether code belongs in an answer at all.
enum InterviewRoleField: String, Codable, CaseIterable, Sendable, Identifiable {
    case seniorAITrainer
    case videoAnnotationExpert
    case generalist
    case software
    case data
    case dataAnnotation
    case devops
    case security
    case research
    case product
    case design
    case marketing
    case sales
    case customerSuccess
    case finance
    case consulting
    case operations
    case people
    case healthcare
    case education
    case legal
    case writing
    case administrative
    case retail
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .seniorAITrainer: return "Senior AI trainer"
        case .videoAnnotationExpert: return "Video Annotation Expert"
        case .generalist: return "Generalist"
        case .software: return "Software engineering"
        case .data: return "Data / analytics / ML"
        case .dataAnnotation: return "Data annotation / AI training"
        case .devops: return "DevOps / infrastructure"
        case .security: return "Security"
        case .research: return "Research / science"
        case .product: return "Product management"
        case .design: return "Design / UX"
        case .marketing: return "Marketing / growth"
        case .sales: return "Sales / account management"
        case .customerSuccess: return "Customer success / support"
        case .finance: return "Finance / accounting"
        case .consulting: return "Consulting / strategy"
        case .operations: return "Operations / project management"
        case .people: return "People / HR / recruiting"
        case .healthcare: return "Healthcare / clinical"
        case .education: return "Education / teaching"
        case .legal: return "Legal / compliance"
        case .writing: return "Writing / content / editorial"
        case .administrative: return "Administrative / executive support"
        case .retail: return "Retail / hospitality / service"
        case .general: return "Other / general"
        }
    }

    /// True when code, complexity analysis, and a preferred programming language make sense.
    var expectsCoding: Bool {
        switch self {
        case .software, .data, .devops, .security: return true
        default: return false
        }
    }

    var promptGuidance: String {
        switch self {
        case .seniorAITrainer:
            return """
            Field: senior AI trainer. Frame answers around writing and updating guidelines, calibrating \
            annotators, reviewing quality, resolving disagreements against the rubric, coaching others, \
            and protecting data quality at volume. You train people and processes — you do not write \
            production software. Speak as a senior practitioner who owns quality, not as an engineer.
            """
        case .videoAnnotationExpert:
            return """
            Field: video annotation expert. Frame answers around watching clips, following the written \
            guideline exactly, and labeling what the rubric asks for (actions, objects, attributes, \
            timestamps, tracks, scene labels). Stay temporally consistent across frames. Tight boxes, \
            correct start/end times, no extra labels outside the ontology. If a clip is ambiguous, \
            occluded, blurry, off-screen, or out of taxonomy, flag it or use the allowed unsure/none \
            option — never guess. Accuracy and consistency beat speed. This is not a software interview; \
            do not give algorithms, Big-O, or code unless they explicitly ask.
            """
        case .generalist:
            return """
            Field: generalist. Expect a wide spread of AI training and ops work — text, image, or video \
            labeling, light QA, following new guidelines quickly, and switching projects. Frame answers \
            around adaptability, learning a rubric fast, staying consistent, flagging uncertainty, and \
            owning messy tasks end to end. Do not default to software engineering.
            """
        case .software:
            return "Field: software engineering. Expect coding, algorithms, system design, and engineering tradeoffs; use precise technical vocabulary."
        case .data:
            return "Field: data / analytics / ML. Frame answers around data quality, metrics definitions, statistics, experimentation, modelling tradeoffs, and pipelines. SQL and Python are the default tools."
        case .dataAnnotation:
            return """
            Field: data annotation / AI training. Frame answers around following written guidelines exactly, \
            handling ambiguous or edge-case items, staying consistent with other annotators, quality review \
            and feedback loops, and flagging uncertainty rather than guessing. Speed matters; accuracy and \
            consistency matter more. Some projects involve reading or rating code or writing — judge the work \
            against the rubric rather than rewriting it.
            """
        case .devops:
            return "Field: DevOps / infrastructure. Frame answers around reliability, CI/CD, observability, incident response, cost, and infrastructure-as-code."
        case .security:
            return "Field: security. Frame answers around threat models, risk, controls, detection, incident response, and compliance frameworks."
        case .research:
            return "Field: research / science. Frame answers around the research question, method and study design, data quality, interpreting results honestly with their limits, and explaining findings to non-specialists."
        case .product:
            return "Field: product management. Frame answers around users and their problems, discovery, prioritisation, success metrics, tradeoffs, and stakeholder alignment. Talk about outcomes, not implementation."
        case .design:
            return "Field: design / UX. Frame answers around user research, problem framing, design process, critique, accessibility, and how design decisions were validated."
        case .marketing:
            return "Field: marketing / growth. Frame answers around audience, positioning, channels, funnel stages, campaign results, and measurable growth outcomes."
        case .sales:
            return "Field: sales / account management. Frame answers around qualification, discovery questions, objection handling, pipeline, quota attainment, and relationship building."
        case .customerSuccess:
            return "Field: customer success / support. Frame answers around empathy, de-escalation, retention and churn, SLAs, and turning customer feedback into action."
        case .finance:
            return "Field: finance / accounting. Frame answers around accuracy, controls, reconciliation, forecasting, variance analysis, and the relevant standards or regulations."
        case .consulting:
            return "Field: consulting / strategy. Structure answers explicitly — clarify the question, lay out a framework or hypothesis, walk the analysis, then state a recommendation. Estimation and case questions are expected."
        case .operations:
            return "Field: operations / project management. Frame answers around process, throughput, bottlenecks, stakeholder communication, risk management, and delivery on schedule."
        case .people:
            return "Field: people / HR / recruiting. Frame answers around fairness, confidentiality, employment policy, candidate and employee experience, and difficult conversations."
        case .healthcare:
            return "Field: healthcare / clinical. Frame answers around patient safety, clinical reasoning, protocols and scope of practice, documentation, and working within a care team. Never give clinical advice as fact — describe how the candidate would act in the role."
        case .education:
            return "Field: education / teaching. Frame answers around learning objectives, differentiation, classroom management, assessment, and family or stakeholder communication."
        case .legal:
            return "Field: legal / compliance. Frame answers around issue spotting, applicable rules, risk assessment, documentation, and advising the business in plain language."
        case .writing:
            return "Field: writing / content / editorial. Frame answers around audience and voice, research and accuracy, structure, the editing and revision process, deadlines, and how the finished work performed."
        case .administrative:
            return "Field: administrative / executive support. Frame answers around calendar and inbox judgement, discretion with confidential information, juggling competing priorities, anticipating what people need, and keeping logistics on track."
        case .retail:
            return "Field: retail / hospitality / service. Frame answers around the customer experience, staying calm under pressure, handling complaints and difficult people, teamwork on shift, reliability, and safety or store standards."
        case .general:
            return "Field: general professional. Match the vocabulary and success measures of the role named above rather than defaulting to software engineering."
        }
    }
}

/// Menu grouping for the field picker — a flat list of every field is too long to scan.
enum InterviewRoleCategory: String, CaseIterable, Sendable, Identifiable {
    case aiTraining
    case technical
    case business
    case peopleAndService
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aiTraining: return "AI Training & Annotation"
        case .technical: return "Technical"
        case .business: return "Business & Strategy"
        case .peopleAndService: return "People & Service"
        case .other: return "Other Fields"
        }
    }

    var fields: [InterviewRoleField] {
        switch self {
        case .aiTraining:
            return [.seniorAITrainer, .videoAnnotationExpert, .generalist, .dataAnnotation]
        default:
            return InterviewRoleField.allCases.filter { $0.category == self }
        }
    }
}

extension InterviewRoleField {
    var category: InterviewRoleCategory {
        switch self {
        case .seniorAITrainer, .videoAnnotationExpert, .generalist, .dataAnnotation:
            return .aiTraining
        case .software, .data, .devops, .security, .research:
            return .technical
        case .product, .design, .marketing, .sales, .finance, .consulting, .operations:
            return .business
        case .customerSuccess, .people, .healthcare, .education, .retail, .administrative:
            return .peopleAndService
        case .legal, .writing, .general:
            return .other
        }
    }
}

/// Whether coding, algorithms, and complexity belong in answers.
/// `auto` follows the field; the explicit cases exist because roles like data annotation
/// or a startup generalist can go either way.
enum CodingPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto
    case include
    case exclude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (match field)"
        case .include: return "Always include"
        case .exclude: return "Never include"
        }
    }
}

/// The role the candidate is currently interviewing for.
/// Injected into every answer prompt so replies match the field, not just software.
struct RoleProfile: Codable, Equatable, Sendable {
    /// Free text job title, e.g. "Senior Product Manager".
    var title: String
    var field: InterviewRoleField
    /// Optional company name.
    var company: String
    /// Optional pasted job description, seniority, stack, or anything else worth knowing.
    var notes: String
    /// Manual override for whether code belongs in answers.
    var codingPreference: CodingPreference

    static let `default` = RoleProfile()

    init(
        title: String = "",
        field: InterviewRoleField = .general,
        company: String = "",
        notes: String = "",
        codingPreference: CodingPreference = .auto
    ) {
        self.title = title
        self.field = field
        self.company = company
        self.notes = notes
        self.codingPreference = codingPreference
    }

    /// Decoded key by key so a profile saved by an older build (before `codingPreference`,
    /// or naming a field this build removed) still loads instead of throwing away every setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        field = try c.decodeIfPresent(InterviewRoleField.self, forKey: .field) ?? .general
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        codingPreference = try c.decodeIfPresent(CodingPreference.self, forKey: .codingPreference) ?? .auto
    }

    /// True when Field is still the generic default and no extra prompt was written.
    var isUnset: Bool {
        field == .general && notes.isBlank
    }

    /// Field used for prompting. If Field is still general/software, the optional prompt can
    /// name annotation work and pull answers out of a software-engineering default.
    var effectiveField: InterviewRoleField {
        if let inferred = Self.inferredField(fromPrompt: notes),
           field == .software || field == .general || field == inferred {
            return inferred
        }
        return field
    }

    /// True when coding solutions and a preferred programming language are relevant.
    var expectsCoding: Bool {
        switch codingPreference {
        case .auto: return effectiveField.expectsCoding
        case .include: return true
        case .exclude: return false
        }
    }

    /// Short one-line label for UI.
    var displaySummary: String {
        effectiveField.displayName
    }

    /// Prompt fragment describing the role.
    var promptGuidance: String {
        var lines: [String] = ["Role the candidate is interviewing for: \(displaySummary)."]
        if effectiveField != field {
            lines.append(
                "The extra prompt describes \(effectiveField.displayName) work — frame every answer for that, "
                + "not \(field.displayName)."
            )
        }
        lines.append(effectiveField.promptGuidance)
        lines.append(
            "Answer the way a strong candidate for this role would speak — use that role's vocabulary, "
            + "frameworks, and measures of success. Do not default to software engineering framing."
        )
        if !expectsCoding {
            lines.append(
                "Do not treat this as a software engineering interview. Do not volunteer code, algorithm variations, "
                + "or time/space complexity, and ignore any earlier instruction that demands multiple coding "
                + "variations. If a hands-on exercise comes up, answer it with the tools of this field "
                + "(guidelines, a rubric, a process, a calculation, a spreadsheet or SQL query) and only when asked."
            )
        }
        if !notes.isBlank {
            let extra = TokenEstimator.truncateToTokenBudget(notes.trimmed, maxTokens: 400)
            lines.append("Additional instructions from the candidate — follow these:\n\(extra)")
        }
        return lines.joined(separator: "\n")
    }

    /// Best-effort field from the optional extra prompt.
    static func inferredField(fromPrompt prompt: String) -> InterviewRoleField? {
        let text = prompt.lowercased()
        guard !text.isBlank else { return nil }

        let rules: [(InterviewRoleField, [String])] = [
            (
                .videoAnnotationExpert,
                ["video annotat", "video label", "timestamp", "bounding box", "clip labeling"]
            ),
            (
                .seniorAITrainer,
                ["senior ai trainer", "ai trainer", "train annotator", "calibrat"]
            ),
            (
                .dataAnnotation,
                [
                    "annotat", "data label", "labeler", "labelling", "labeling",
                    "ai training", "rlhf", "sft rater", "preference rank", "rating task"
                ]
            )
        ]
        for (field, needles) in rules where needles.contains(where: { text.contains($0) }) {
            return field
        }
        return nil
    }
}
