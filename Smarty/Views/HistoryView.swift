import SwiftUI

struct HistoryView: View {
    let messages: [ConversationMessage]
    let fontSize: Double
    var onExportMarkdown: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if onExportMarkdown != nil {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        onExportMarkdown?()
                    } label: {
                        Label("Export Markdown", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: fontSize - 2))
                    .disabled(messages.isEmpty)
                    .help("Copy session transcript as Markdown")
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        Text("No answers yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(messages.reversed()) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role == .assistant ? "Answer" : "Prompt")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(message.content)
                                    .font(.system(size: fontSize))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    HistoryView(
        messages: [
            ConversationMessage(role: .assistant, content: "I'd start by clarifying constraints, then sketch the approach.")
        ],
        fontSize: 13
    )
    .padding()
}
