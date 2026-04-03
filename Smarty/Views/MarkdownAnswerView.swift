import AppKit
import SwiftUI

/// Renders assistant answers with markdown prose + fenced code blocks (syntax tinted).
struct MarkdownAnswerView: View {
    let text: String
    let fontSize: Double
    var isPlaceholder: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let prose):
                    Text(Self.attributedProse(prose, fontSize: fontSize, secondary: isPlaceholder))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code, fontSize: fontSize)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Block {
        case prose(String)
        case code(language: String?, code: String)
    }

    private static func parseBlocks(_ raw: String) -> [Block] {
        guard !raw.isEmpty else { return [.prose("")] }
        var blocks: [Block] = []
        var proseLines: [String] = []
        var inCode = false
        var codeLanguage: String?
        var codeLines: [String] = []

        func flushProse() {
            let joined = proseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.prose(joined))
            }
            proseLines.removeAll()
        }

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    codeLanguage = nil
                    inCode = false
                } else {
                    flushProse()
                    let marker = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLanguage = marker.isEmpty ? nil : marker
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
            } else {
                proseLines.append(line)
            }
        }

        if inCode {
            // Unclosed fence — still show as code.
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        } else {
            flushProse()
        }

        return blocks.isEmpty ? [.prose(raw)] : blocks
    }

    private static func attributedProse(_ text: String, fontSize: Double, secondary: Bool) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if var markdown = try? AttributedString(
            markdown: text,
            options: options
        ) {
            let base = Font.system(size: fontSize)
            markdown.font = base
            if secondary {
                markdown.foregroundColor = .secondary
            }
            // Soft-style bold bracket explanations: **[simple explanation]**
            for run in markdown.runs {
                guard let intent = run.inlinePresentationIntent,
                      intent.contains(.stronglyEmphasized) else { continue }
                let slice = String(markdown[run.range].characters)
                let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { continue }
                markdown[run.range].foregroundColor = .secondary
                markdown[run.range].font = .system(size: fontSize, weight: .medium)
            }
            return markdown
        }
        var fallback = AttributedString(text)
        fallback.font = .system(size: fontSize)
        if secondary {
            fallback.foregroundColor = .secondary
        }
        return fallback
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").uppercased())
                    .font(.system(size: max(9, fontSize - 5), weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: max(10, fontSize - 4)))
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(code, language: language, fontSize: fontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum CodeHighlighter {
    static func highlight(_ source: String, language: String?, fontSize: Double) -> AttributedString {
        let lang = (language ?? "").lowercased()
        let keywords = keywordsFor(lang)
        let mono = Font.system(size: fontSize - 0.5, design: .monospaced)
        var output = AttributedString()

        for (lineIndex, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if lineIndex > 0 {
                output.append(AttributedString("\n"))
            }
            output.append(highlightLine(String(line), keywords: keywords, font: mono))
        }

        if output.characters.isEmpty {
            var empty = AttributedString(source)
            empty.font = mono
            return empty
        }
        return output
    }

    private static func highlightLine(_ line: String, keywords: Set<String>, font: Font) -> AttributedString {
        if commentPrefix(line) {
            var attr = AttributedString(line)
            attr.font = font
            attr.foregroundColor = commentColor
            return attr
        }

        var result = AttributedString()
        var index = line.startIndex

        while index < line.endIndex {
            if line[index] == "\"" || line[index] == "'" {
                let quote = line[index]
                var end = line.index(after: index)
                while end < line.endIndex {
                    if line[end] == "\\" {
                        end = line.index(end, offsetBy: 1, limitedBy: line.endIndex) ?? line.endIndex
                        if end < line.endIndex { end = line.index(after: end) }
                        continue
                    }
                    if line[end] == quote {
                        end = line.index(after: end)
                        break
                    }
                    end = line.index(after: end)
                }
                var chunk = AttributedString(String(line[index..<end]))
                chunk.font = font
                chunk.foregroundColor = stringColor
                result.append(chunk)
                index = end
                continue
            }

            if line[index].isNumber {
                var end = index
                while end < line.endIndex, line[end].isNumber || line[end] == "." || line[end] == "_" {
                    end = line.index(after: end)
                }
                var chunk = AttributedString(String(line[index..<end]))
                chunk.font = font
                chunk.foregroundColor = numberColor
                result.append(chunk)
                index = end
                continue
            }

            if line[index].isLetter || line[index] == "_" {
                var end = index
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" {
                    end = line.index(after: end)
                }
                let token = String(line[index..<end])
                var chunk = AttributedString(token)
                chunk.font = font
                if keywords.contains(token) {
                    chunk.foregroundColor = keywordColor
                    chunk.font = font.weight(.semibold)
                } else if token.first?.isUppercase == true {
                    chunk.foregroundColor = typeColor
                } else {
                    chunk.foregroundColor = .primary
                }
                result.append(chunk)
                index = end
                continue
            }

            var chunk = AttributedString(String(line[index]))
            chunk.font = font
            chunk.foregroundColor = punctColor
            result.append(chunk)
            index = line.index(after: index)
        }

        return result
    }

    private static func commentPrefix(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//")
            || trimmed.hasPrefix("#")
            || trimmed.hasPrefix("/*")
            || trimmed.hasPrefix("*")
            || trimmed.hasPrefix("--")
    }

    private static func keywordsFor(_ language: String) -> Set<String> {
        let common: Set<String> = [
            "if", "else", "for", "while", "return", "func", "function", "var", "let", "const",
            "class", "struct", "enum", "protocol", "import", "from", "as", "try", "catch",
            "throw", "async", "await", "true", "false", "null", "nil", "None", "True", "False",
            "public", "private", "static", "guard", "switch", "case", "break", "continue",
            "new", "this", "self", "in", "of", "type", "interface", "extends", "implements",
            "def", "print", "with", "yield", "lambda", "pass", "raise", "except", "finally",
            "package", "void", "int", "string", "bool", "boolean", "map", "filter", "reduce"
        ]
        switch language {
        case "swift":
            return common.union([
                "nonisolated", "actor", "some", "any", "where", "associatedtype", "inout",
                "mutating", "override", "final", "lazy", "weak", "unowned", "defer", "repeat"
            ])
        case "python", "py":
            return common.union(["elif", "nonlocal", "global", "assert", "del", "is", "not", "and", "or"])
        case "js", "javascript", "ts", "typescript":
            return common.union(["typeof", "instanceof", "export", "default", "undefined", "number"])
        case "java", "kotlin":
            return common.union(["protected", "abstract", "synchronized", "throws", "fun", "val", "object"])
        default:
            return common
        }
    }

    // Readable on both light and dark glass materials.
    private static let keywordColor = Color(red: 0.35, green: 0.55, blue: 0.95)
    private static let stringColor = Color(red: 0.86, green: 0.52, blue: 0.28)
    private static let numberColor = Color(red: 0.72, green: 0.55, blue: 0.90)
    private static let typeColor = Color(red: 0.35, green: 0.78, blue: 0.72)
    private static let commentColor = Color.secondary
    private static let punctColor = Color.primary.opacity(0.75)
}

/// Live mic transcript with auto-scroll to the latest words.
struct HeardTranscriptView: View {
    let text: String
    let fontSize: Double
    var isActive: Bool = false
    var isMuted: Bool = false
    @Binding var isExpanded: Bool

    init(
        text: String,
        fontSize: Double,
        isActive: Bool = false,
        isMuted: Bool = false,
        isExpanded: Binding<Bool> = .constant(true)
    ) {
        self.text = text
        self.fontSize = fontSize
        self.isActive = isActive
        self.isMuted = isMuted
        self._isExpanded = isExpanded
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayText)
                        .font(.system(size: fontSize - 1, design: .rounded))
                        .foregroundStyle(text.isEmpty || isMuted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .id("heard-bottom")
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .padding(.top, 4)
                .onChange(of: text) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("heard-bottom", anchor: .bottom)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isMuted ? "mic.slash.fill" : (isActive ? "waveform" : "ear"))
                    .symbolEffect(.variableColor.iterative, isActive: isActive && !isMuted)
                    .foregroundStyle(isMuted ? .orange : (isActive ? Color.accentColor : .secondary))
                Text("Heard")
                    .font(.system(size: fontSize - 2, weight: .medium))
                    .foregroundStyle(.secondary)
                if isMuted {
                    Text("MUTED")
                        .font(.system(size: max(9, fontSize - 6), weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                } else if isActive {
                    Text("LIVE")
                        .font(.system(size: max(9, fontSize - 6), weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
        .tint(.secondary)
    }

    private var displayText: String {
        if isMuted { return "Mic muted — speech ignored. Screen OCR stays context-only." }
        if text.isEmpty { return "Waiting for speech…" }
        return text
    }
}
