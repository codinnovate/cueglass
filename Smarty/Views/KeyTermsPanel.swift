import SwiftUI

/// Definitions + related follow-ups for important terms in the latest answer.
struct KeyTermsPanel: View {
    let terms: [KeyTermCard]
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(.secondary)
                Text("Key terms")
                    .font(.system(size: fontSize - 2, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            // Cap height + avoid animated intrinsic-size thrash (was crashing NSHostingView Auto Layout).
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(terms) { card in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 4) {
                                if !card.definition.isEmpty {
                                    Text(card.definition)
                                        .font(.system(size: fontSize - 2))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if !card.relatedQuestions.isEmpty {
                                    Text("Related questions")
                                        .font(.system(size: max(9, fontSize - 5), weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 2)
                                    ForEach(card.relatedQuestions, id: \.self) { question in
                                        Text("· \(question)")
                                            .font(.system(size: fontSize - 2))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        } label: {
                            Text(card.term)
                                .font(.system(size: fontSize - 1, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}
