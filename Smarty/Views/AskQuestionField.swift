import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Rounded liquid-glass ask field (cornerRadius 16 ≈ rounded-2xl).
/// Submit sends typed text, or — if empty — confirms the Heard transcript as “I’m done.”
struct AskQuestionField: View {
    @Binding var text: String
    var fontSize: Double = 14
    var isBusy: Bool = false
    /// Allow send with empty text when live transcript is ready (manual pause / answer now).
    var canSubmitHeard: Bool = false
    var pendingImages: [ImageAttachment] = []
    var isFocused: FocusState<Bool>.Binding
    var onFocus: (() -> Void)? = nil
    var onAttachFiles: () -> Void
    var onPasteImage: () -> Void
    var onRemoveImage: (UUID) -> Void
    var onSubmit: () -> Void

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !isBusy && (hasText || canSubmitHeard || !pendingImages.isEmpty)
    }

    private var prompt: String {
        if !pendingImages.isEmpty {
            return canSubmitHeard ? "Ask about the image… or ↑" : "Ask about the image…"
        }
        return canSubmitHeard ? "Ask… or press ↑ to answer what was heard" : "Ask a question…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pendingImages.isEmpty {
                thumbnailStrip
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    onFocus?()
                    onAttachFiles()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: fontSize + 2))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help("Attach image")

                TextField(prompt, text: $text, axis: .vertical)
                    .font(.system(size: fontSize))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused(isFocused)
                    .disabled(isBusy)
                    .onSubmit {
                        guard canSend else { return }
                        onSubmit()
                    }
                    .onChange(of: isFocused.wrappedValue) { _, focused in
                        if focused {
                            onFocus?()
                        }
                    }

                Button {
                    onFocus?()
                    guard canSend else { return }
                    onSubmit()
                } label: {
                    Image(systemName: isBusy ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: fontSize + 8))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      ? (pendingImages.isEmpty ? "Answer from what was heard" : "Ask with attached image")
                      : "Ask")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .onPasteCommand(of: [.png, .jpeg, .tiff, .fileURL]) { _ in
            onPasteImage()
        }
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let thumb = attachment.thumbnail() {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color.secondary.opacity(0.2)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button {
                            onRemoveImage(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
        }
    }
}
