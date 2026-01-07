import Foundation

struct KeyTermCard: Identifiable, Equatable, Sendable {
    let id: UUID
    let term: String
    let definition: String
    let relatedQuestions: [String]

    init(
        id: UUID = UUID(),
        term: String,
        definition: String,
        relatedQuestions: [String] = []
    ) {
        self.id = id
        self.term = term
        self.definition = definition
        self.relatedQuestions = relatedQuestions
    }

    /// Parses a JSON array of term cards from model output (tolerates markdown fences).
    static func parse(from raw: String) -> [KeyTermCard] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let rows: [[String: Any]]
        if let array = json as? [[String: Any]] {
            rows = array
        } else if let object = json as? [String: Any],
                  let array = object["terms"] as? [[String: Any]] {
            rows = array
        } else {
            return []
        }

        return rows.compactMap { row in
            guard let term = (row["term"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !term.isEmpty else { return nil }
            let definition = (row["definition"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let related = (row["relatedQuestions"] as? [String])?
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
            return KeyTermCard(term: term, definition: definition, relatedQuestions: related)
        }
    }
}
