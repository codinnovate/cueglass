import SwiftUI

/// A tiny native LaTeX-math subset parser. Deliberately not a full TeX engine —
/// covers what interview answers actually use: frac, sqrt, sub/superscripts,
/// greek letters, and common relation/operator symbols.
indirect enum MathNode {
    case text(String)
    case sequence([MathNode])
    case superscript(base: MathNode, exp: MathNode)
    case subscript_(base: MathNode, sub: MathNode)
    case fraction(num: MathNode, den: MathNode)
    case sqrt(radicand: MathNode, index: MathNode?)
}

enum LaTeXMathParser {
    static func parse(_ latex: String) -> MathNode {
        var parser = Parser(chars: Array(latex))
        return .sequence(parser.parseSequence(until: nil))
    }

    /// Best-effort flattening to plain unicode text, for math embedded inline in prose.
    static func toPlainString(_ node: MathNode) -> String {
        switch node {
        case .text(let s):
            return s
        case .sequence(let nodes):
            return nodes.map(toPlainString).joined()
        case .superscript(let base, let exp):
            return toPlainString(base) + superscriptUnicode(toPlainString(exp))
        case .subscript_(let base, let sub):
            return toPlainString(base) + subscriptUnicode(toPlainString(sub))
        case .fraction(let num, let den):
            return "(" + toPlainString(num) + "/" + toPlainString(den) + ")"
        case .sqrt(let radicand, let index):
            let root = "√(" + toPlainString(radicand) + ")"
            guard let index else { return root }
            return toPlainString(index) + root
        }
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        var isAtEnd: Bool { i >= chars.count }

        mutating func skipSpaces() {
            while i < chars.count, chars[i] == " " { i += 1 }
        }

        mutating func parseSequence(until stop: Character?) -> [MathNode] {
            var nodes: [MathNode] = []
            while i < chars.count {
                if let stop, chars[i] == stop {
                    i += 1
                    break
                }
                var node = parseAtom()
                while i < chars.count, chars[i] == "^" || chars[i] == "_" {
                    let isSuper = chars[i] == "^"
                    i += 1
                    let script = parseAtom()
                    node = isSuper
                        ? .superscript(base: node, exp: script)
                        : .subscript_(base: node, sub: script)
                }
                nodes.append(node)
            }
            return nodes
        }

        mutating func parseAtom() -> MathNode {
            skipSpaces()
            guard i < chars.count else { return .text("") }
            let c = chars[i]

            if c == "{" {
                i += 1
                return .sequence(parseSequence(until: "}"))
            }

            if c == "\\" {
                i += 1
                var name = ""
                while i < chars.count, chars[i].isLetter {
                    name.append(chars[i])
                    i += 1
                }
                if name.isEmpty {
                    guard i < chars.count else { return .text("") }
                    let esc = chars[i]
                    i += 1
                    return .text(String(esc))
                }
                switch name {
                case "frac":
                    let num = parseAtom()
                    let den = parseAtom()
                    return .fraction(num: num, den: den)
                case "sqrt":
                    skipSpaces()
                    var index: MathNode?
                    if i < chars.count, chars[i] == "[" {
                        i += 1
                        var idx = ""
                        while i < chars.count, chars[i] != "]" {
                            idx.append(chars[i])
                            i += 1
                        }
                        if i < chars.count { i += 1 }
                        index = .text(idx)
                    }
                    return .sqrt(radicand: parseAtom(), index: index)
                case "left", "right", "big", "Big", "bigg", "Bigg":
                    skipSpaces()
                    guard i < chars.count else { return .text("") }
                    let delim = chars[i]
                    i += 1
                    return delim == "." ? .text("") : .text(String(delim))
                case "text", "mathrm", "mathbf", "operatorname", "textbf":
                    return parseAtom()
                case "quad", "qquad":
                    return .text("  ")
                default:
                    return .text(MathSymbols.map[name] ?? name)
                }
            }

            i += 1
            return .text(String(c))
        }
    }
}

private func superscriptUnicode(_ s: String) -> String {
    String(s.map { MathSymbols.superscripts[$0] ?? $0 })
}

private func subscriptUnicode(_ s: String) -> String {
    String(s.map { MathSymbols.subscripts[$0] ?? $0 })
}

enum MathSymbols {
    static let map: [String: String] = [
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓",
        "leq": "≤", "geq": "≥", "le": "≤", "ge": "≥", "neq": "≠", "approx": "≈",
        "equiv": "≡", "sim": "∼", "propto": "∝",
        "infty": "∞", "partial": "∂", "nabla": "∇",
        "cdots": "⋯", "ldots": "…", "dots": "…", "vdots": "⋮", "ddots": "⋱",
        "rightarrow": "→", "to": "→", "leftarrow": "←", "leftrightarrow": "↔",
        "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔",
        "sum": "∑", "prod": "∏", "int": "∫", "oint": "∮",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "supset": "⊃",
        "cup": "∪", "cap": "∩", "emptyset": "∅", "forall": "∀", "exists": "∃",
        "wedge": "∧", "vee": "∨", "neg": "¬", "lnot": "¬",
        "degree": "°", "prime": "′",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ",
        "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω"
    ]

    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶",
        "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ",
        "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ",
        "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ",
        "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ"
    ]

    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆",
        "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ",
        "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ",
        "u": "ᵤ", "v": "ᵥ", "x": "ₓ"
    ]
}

/// Renders a display-math block (`$$...$$`, `\[...\]`) as real stacked typesetting.
struct MathBlockView: View {
    let latex: String
    let fontSize: Double

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            MathNodeView(node: LaTeXMathParser.parse(latex), fontSize: fontSize * 1.05)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

private struct MathNodeView: View {
    let node: MathNode
    var fontSize: Double
    var color: Color = .primary

    var body: some View {
        switch node {
        case .text(let s):
            Text(s)
                .font(.system(size: fontSize, design: .serif))
                .foregroundStyle(color)

        case .sequence(let nodes):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, n in
                    MathNodeView(node: n, fontSize: fontSize, color: color)
                }
            }

        case .superscript(let base, let exp):
            HStack(alignment: .top, spacing: 0) {
                MathNodeView(node: base, fontSize: fontSize, color: color)
                MathNodeView(node: exp, fontSize: fontSize * 0.62, color: color)
                    .offset(y: -fontSize * 0.32)
                    .padding(.trailing, 1)
            }

        case .subscript_(let base, let sub):
            HStack(alignment: .bottom, spacing: 0) {
                MathNodeView(node: base, fontSize: fontSize, color: color)
                MathNodeView(node: sub, fontSize: fontSize * 0.62, color: color)
                    .offset(y: fontSize * 0.18)
                    .padding(.trailing, 1)
            }

        case .fraction(let num, let den):
            VStack(spacing: 2) {
                MathNodeView(node: num, fontSize: fontSize * 0.82, color: color)
                Rectangle().fill(color).frame(height: 1)
                MathNodeView(node: den, fontSize: fontSize * 0.82, color: color)
            }
            .fixedSize()
            .padding(.horizontal, 2)

        case .sqrt(let radicand, let index):
            HStack(alignment: .top, spacing: 0) {
                if let index {
                    MathNodeView(node: index, fontSize: fontSize * 0.55, color: color)
                        .offset(y: -fontSize * 0.1)
                }
                Text("√")
                    .font(.system(size: fontSize * 1.05, design: .serif))
                    .foregroundStyle(color)
                MathNodeView(node: radicand, fontSize: fontSize, color: color)
                    .padding(.top, fontSize * 0.08)
                    .overlay(Rectangle().fill(color).frame(height: 1), alignment: .top)
                    .padding(.horizontal, 1)
            }
        }
    }
}
