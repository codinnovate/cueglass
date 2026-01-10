import SwiftUI

struct StatusBadge: View {
    let status: AppStatus
    var blinkEnabled: Bool = true
    /// Listen-armed even if status hasn't flipped yet.
    var isArmed: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if shouldBlink {
                TimelineView(.animation(minimumInterval: 0.55, paused: false)) { context in
                    let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .opacity(phase ? 1 : 0.22)
                }
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(statusLabel)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
    }

    private var shouldBlink: Bool {
        guard blinkEnabled else { return false }
        if isArmed { return true }
        switch status {
        case .listening, .thinking, .streaming:
            return true
        case .idle, .paused, .error:
            return false
        }
    }

    private var statusLabel: String {
        if isArmed, status == .listening || status == .idle {
            return "Armed"
        }
        return status.label
    }

    private var color: Color {
        if isArmed { return .green }
        switch status {
        case .idle: return .secondary
        case .listening: return .green
        case .thinking: return .orange
        case .streaming: return .blue
        case .paused: return .yellow
        case .error: return .red
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        StatusBadge(status: .listening, blinkEnabled: true, isArmed: true)
        StatusBadge(status: .thinking, blinkEnabled: true)
        StatusBadge(status: .streaming, blinkEnabled: false)
        StatusBadge(status: .error("No network"))
    }
    .padding()
}
