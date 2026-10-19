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
    let isThinking: Bool
    let isRunning: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: placement.cornerRadius, style: .continuous)
                .fill(fillStyle)

            if let status {
                FluidWaves(color: status.color, motion: waveMotion)
                    .opacity(isThinking ? 0.42 : (isRunning || status == .listening ? 0.36 : 0.2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: placement.cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fillStyle: AnyShapeStyle {
        AnyShapeStyle(Color.clear)
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

    var body: some View {
        if isPrivate {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    status == .listening ? Theme.danger.opacity(0.55) : Color.white.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
        return .clear
    }
}

struct AskSurfaceMaterial: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let isPrivate: Bool

    @Environment(\.colorScheme) private var scheme

    /// macOS cross-fades a material's own `.tint` below SwiftUI, so the glass is
    /// held constant and every colour is painted over it instead.
    private var wash: Color {
        if isPrivate {
            return Color(red: 0.12, green: 0.11, blue: 0.15).opacity(0.94)
        }
        guard let tint else { return .clear }
        return tint.opacity(scheme == .dark ? 0.13 : 0.09)
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(wash)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension PageSecurity {
    var symbol: String? {
        switch self {
        case .secure:
            "lock.fill"
        case .pending:
            "lock"
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
        case .pending:
            .secondary
        case .insecure:
            .red
        case .mixed:
            .orange
        case .none:
            .secondary
        }
    }

}

struct AskRestingLine: View {
    let placement: AskSurface.Placement
    let content: AskRestingContent
    let security: PageSecurity
    let notice: ChromeNotice

    @Environment(\.chromeIsLight) private var chromeIsLight

    private func noticeStyle(symbol: String?) -> AnyShapeStyle {
        if symbol != nil {
            return ChromeInk.glyph(onLight: chromeIsLight)
        }
        return security == .insecure ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

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

            case .notice(let message, let symbol):
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: placement.textSize - 1, weight: .semibold))
                        .foregroundStyle(notice.isWarning ? AnyShapeStyle(Theme.warning) : ChromeInk.glyph(onLight: chromeIsLight))
                        .noticePop(notice)
                        .transition(.opacity)
                }
                Text(verbatim: message)
                    .font(.system(size: placement.textSize, weight: .medium))
                    .foregroundStyle(noticeStyle(symbol: symbol))
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

            case .address(let host, let pageSymbol):
                if let pageSymbol {
                    Image(systemName: pageSymbol)
                        .font(.system(size: placement.textSize - 1, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let symbol = security.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(security.tint)
                }
                Text(verbatim: host)
                    .font(.system(size: placement.textSize))
                    .foregroundStyle(ChromeInk.glyph(onLight: chromeIsLight))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
