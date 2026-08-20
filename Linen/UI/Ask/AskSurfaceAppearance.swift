// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum AskSurfaceStatus: Equatable {
    case listening
    case warning
    case agent

    var color: Color {
        switch self {
        case .listening:
            Theme.danger
        case .warning:
            Theme.warning
        case .agent:
            Theme.accent
        }
    }
}

struct AskSurfaceBackdrop: View {
    let placement: AskSurface.Placement
    let status: AskSurfaceStatus?
    let isPrivate: Bool
    let isFocused: Bool
    let hasResults: Bool
    let overhangs: Bool
    let isThinking: Bool
    let isRunning: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: placement.cornerRadius)
                .fill(fillStyle)

            if let status {
                FluidWaves(color: status.color, motion: waveMotion)
                    .opacity(isThinking ? 0.7 : (isRunning || status == .listening ? 0.62 : 0.3))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: placement.cornerRadius))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fillStyle: AnyShapeStyle {
        if hasResults || overhangs {
            return AnyShapeStyle(scheme == .dark ? Color(white: 0.20) : .white)
        }
        if placement.usesMaterial {
            return AnyShapeStyle(Color.clear)
        }
        return AnyShapeStyle(isFocused ? Theme.Wash.hairline : Theme.Wash.faint)
    }

    private var waveMotion: FluidWaves.Motion {
        if isThinking {
            return .thinking
        }
        if isRunning || status == .listening {
            return .active
        }
        return .calm
    }
}

struct AskSurfaceBorder: View {
    let cornerRadius: CGFloat
    let isPrivate: Bool
    let status: AskSurfaceStatus?
    let isFocused: Bool

    var body: some View {
        if isPrivate {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    status == .listening ? Theme.danger.opacity(0.55) : Color.white.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var borderColor: Color {
        if status == .listening {
            return Theme.danger.opacity(0.55)
        }
        if status == .warning {
            return Theme.warning.opacity(0.45)
        }
        return isFocused ? Theme.chrome(0.2) : Theme.Wash.hover
    }
}

struct AskSurfaceMaterial: ViewModifier {
    let placement: AskSurface.Placement
    let tint: Color?
    let cornerRadius: CGFloat
    let isPrivate: Bool

    @Environment(\.colorScheme) private var scheme

    private var fill: Color {
        if isPrivate {
            return Color(red: 0.12, green: 0.11, blue: 0.15).opacity(0.92)
        }
        return scheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.80)
    }

    func body(content: Content) -> some View {
        if placement.usesMaterial {
            content.background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fill)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(tint.opacity(0.22))
                        }
                    }
                    .id(scheme)
                    .transition(.identity)
            }
        } else {
            content
        }
    }
}

extension PageSecurity {
    var symbol: String? {
        switch self {
        case .secure:
            "lock.fill"
        case .insecure:
            "lock.open.fill"
        case .mixed:
            "lock.trianglebadge.exclamationmark.fill"
        case .none:
            nil
        }
    }

    var tint: Color {
        switch self {
        case .secure:
            .green
        case .insecure:
            .red
        case .mixed:
            .orange
        case .none:
            .secondary
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .secure:
            "Connection is secure"
        case .mixed:
            "Parts of this page aren’t encrypted"
        case .insecure:
            "Connection is not secure"
        case .none:
            "No connection to check"
        }
    }
}

struct AskRestingLine: View {
    let placement: AskSurface.Placement
    let content: AskRestingContent
    let security: PageSecurity

    var body: some View {
        HStack(spacing: 5) {
            switch content {
            case .transcript(let live):
                Group {
                    if live.isEmpty {
                        Text("Listening…")
                    } else {
                        Text(verbatim: live)
                    }
                }
                .font(.system(size: placement.textSize, weight: .medium))
                .foregroundStyle(live.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.head)

            case .agent(let message):
                Text(verbatim: message)
                    .font(.system(size: placement.textSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(placement.messageLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .id(message)
                    .transition(.opacity)

            case .notice(let notice):
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                Text(verbatim: notice)
                    .font(.system(size: placement.textSize, weight: .medium))
                    .lineLimit(1)
                    .transition(.opacity)

            case .status(let status):
                Text(verbatim: status)
                    .font(.system(size: placement.textSize))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(1)
                    .truncationMode(.head)

            case .placeholder(let words):
                Text(verbatim: words)
                    .font(.system(size: placement.textSize))
                    .foregroundStyle(.tertiary)

            case .address(let host):
                if let symbol = security.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(security.tint)
                }
                Text(verbatim: host)
                    .font(.system(size: placement.textSize))
                    .foregroundStyle(security == .insecure ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct AskKeyHints: View {
    let typed: String
    let agentOnly: Bool
    let onReturn: () -> Void
    let onCommandReturn: () -> Void

    private var returnVerb: LocalizedStringResource {
        BrowserModel.looksLikeLocation(typed) ? "go" : "search"
    }

    private var agentOnlyReturnVerb: LocalizedStringResource {
        BrowserModel.looksLikeLocation(typed) ? "go" : "ask"
    }

    var body: some View {
        if typed.isEmpty {
            HStack(spacing: 4) {
                Text("hold")
                HStack(spacing: 3) {
                    ForEach(ActivationSettings.talk.caps, id: \.self) { KeyCap($0) }
                }
                Text("to speak")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        } else if typed.hasPrefix("@") {
            AskKeyHint(caps: ["↩"], verb: "ask", action: onReturn)
        } else if agentOnly {
            AskKeyHint(caps: ["↩"], verb: agentOnlyReturnVerb, action: onReturn)
        } else {
            HStack(spacing: 1) {
                AskKeyHint(caps: ["↩"], verb: returnVerb, action: onReturn)
                AskKeyHint(caps: ["⌘", "↩"], verb: "ask", action: onCommandReturn)
            }
        }
    }
}

private struct AskKeyHint: View {
    let caps: [String]
    let verb: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                ForEach(caps, id: \.self) { KeyCap($0) }
                Text(verb)
                    .font(Theme.Font.caption)
                    .foregroundStyle(hovering ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(hovering ? Theme.Wash.hairline : Theme.Wash.none, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .accessibilityLabel(Text(verb))
    }
}

struct AskActivityChip: View {
    let count: Int
    let isRunning: Bool
    let isOpen: Bool
    let action: () -> Void

    @State private var hovering = false

    private var helpText: LocalizedStringResource {
        isOpen ? "Hide Agent Activity (⌥⌘A)" : "Show Agent Activity (⌥⌘A)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isRunning ? Theme.accent : Color.secondary.opacity(0.55))
                    .frame(width: 5, height: 5)
                Text(count, format: .number)
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(isOpen || hovering ? Theme.Wash.selection : Theme.Wash.hairline, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(helpText))
        .accessibilityLabel("Agent Activity")
        .accessibilityValue(Text(count, format: .number))
    }
}
