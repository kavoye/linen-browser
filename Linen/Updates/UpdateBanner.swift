// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct UpdateBanner: View {
    let updates: UpdateController

    @Environment(\.sidebarStyle) private var sidebarStyle
    @State private var hovering = false

    private var model: UpdateModel {
        updates.model
    }

    private var isOpen: Bool {
        hovering || isTransferring
    }

    var body: some View {
        Group {
            if model.isBannerVisible {
                if sidebarStyle == .icons {
                    badge
                } else {
                    card
                }
            }
        }
    }

    // MARK: - The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)

                Text(title)
                    .font(Theme.Font.control)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isOpen {
                    dismiss
                }
            }

            if isOpen, let caption {
                Text(caption)
                    .font(.system(size: 10.5, design: captionIsVersions ? .monospaced : .default))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
                    .padding(.leading, 17)
            }

            if isOpen, let actionTitle {
                SettingsButton(title: actionTitle, isProminent: isPrimaryAction) {
                    act()
                }
                .padding(.top, 9)
                .padding(.leading, 17)
            }

            if isTransferring {
                ProgressBar(value: model.isProgressKnown ? model.progress : nil, tint: tint)
                    .padding(.top, 9)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(tint.opacity(isOpen ? 0.45 : 0.3), lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.24), value: isOpen)
        .transition(.identity)
    }

    private var badge: some View {
        Button(action: act) {
            Image(systemName: glyph)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint, in: Circle())
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasAction)
        .help(title)
        .transition(.identity)
    }

    private var dismiss: some View {
        CloseButton(help: String(localized: "Dismiss")) {
            updates.dismiss()
        }
    }

    private func act() {
        if isFailure {
            updates.checkNow()
        } else {
            updates.proceed()
        }
    }

    // MARK: - Wording and colour

    private var isFailure: Bool {
        if case .failed = model.phase {
            return true
        }
        return false
    }

    private var isTransferring: Bool {
        model.phase == .downloading || model.phase == .extracting || model.phase == .installing
    }

    private var hasAction: Bool {
        actionTitle != nil
    }

    private var isPrimaryAction: Bool {
        model.phase == .readyToInstall
    }

    private var tint: Color {
        isFailure ? .orange : Theme.accent
    }

    private var glyph: String {
        switch model.phase {
        case .readyToInstall, .installing:
            "arrow.up"
        case .upToDate:
            "checkmark"
        case .failed:
            "exclamationmark"
        default:
            "arrow.down"
        }
    }

    private var title: String {
        UpdatePhrasing.title(model)
    }

    private var captionIsVersions: Bool {
        model.phase == .available || model.phase == .upToDate
    }

    private var caption: String? {
        UpdatePhrasing.caption(model)
    }

    private var actionTitle: LocalizedStringResource? {
        switch model.phase {
        case .available:
            "Download"
        case .readyToInstall:
            "Install and Relaunch"
        case .failed:
            "Try Again"
        default:
            nil
        }
    }
}

// MARK: - The same state, in Settings

struct UpdateRow: View {
    let updates: UpdateController

    private var model: UpdateModel {
        updates.model
    }

    private var isFailure: Bool {
        if case .failed = model.phase {
            return true
        }
        return false
    }

    private var statusColor: AnyShapeStyle {
        if isFailure {
            return AnyShapeStyle(Theme.warning)
        }
        if model.phase == .available || model.phase == .readyToInstall {
            return AnyShapeStyle(Theme.accent)
        }
        return AnyShapeStyle(.tertiary)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Software Update")
                    .font(Theme.Font.title)

                Text(statusTitle)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            UpdateActionButton(model: model, action: act)
        }
        .padding(.horizontal, SettingsMetrics.rowPaddingH)
        .padding(.vertical, SettingsMetrics.rowPaddingV)
        .animation(Theme.Motion.settle, value: model.phase)
        .onAppear { model.isShownInSettings = true }
        .onDisappear { model.isShownInSettings = false }
    }

    private var statusTitle: LocalizedStringResource {
        switch model.phase {
        case .available:
            "Version \(model.version) is available"
        case .downloading:
            "Downloading update"
        case .extracting:
            "Preparing update"
        case .readyToInstall:
            "Ready to install"
        case .installing:
            "Installing update"
        case .upToDate:
            "Up to date"
        case .failed:
            "Couldn’t check for updates"
        case .checking:
            "Checking for updates"
        case .idle:
            "Installed version \(UpdateFeed.currentVersion)"
        }
    }

    private func act() {
        if model.phase == .available || model.phase == .readyToInstall {
            updates.proceed()
        } else {
            updates.checkNow()
        }
    }
}

private struct UpdateActionButton: View {
    let model: UpdateModel
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                widthReservation

                Text(title)
                    .font(.system(size: 12, weight: isProminent ? .semibold : .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: model.progress))
                    .foregroundStyle(label)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: SettingsMetrics.controlHeight)
            .background { background }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .disabled(!isActionable)
        .onHover { hovering = isActionable && $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .animation(Theme.Motion.drift, value: model.progress)
    }

    private var widthReservation: some View {
        ZStack {
            ForEach(Self.everyTitle, id: \.self) { text in
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .hidden()
            }
        }
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.controlRadius)
        return ZStack(alignment: .leading) {
            shape.fill(baseFill)

            if let progress {
                GeometryReader { proxy in
                    tint.opacity(0.3)
                        .frame(width: proxy.size.width * progress)
                }
            } else if isBusy {
                Sweep(tint: tint)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    // MARK: - What the phase makes of it

    private var isFailure: Bool {
        if case .failed = model.phase {
            return true
        }
        return false
    }

    private var isBusy: Bool {
        switch model.phase {
        case .checking, .downloading, .extracting, .installing:
            true
        default:
            false
        }
    }

    private var isActionable: Bool {
        !isBusy
    }

    private var isProminent: Bool {
        model.phase == .available || model.phase == .readyToInstall
    }

    private var progress: Double? {
        guard model.isProgressKnown else { return nil }
        switch model.phase {
        case .downloading, .extracting:
            return min(1, max(0, model.progress))
        default:
            return nil
        }
    }

    private var share: String {
        Self.share(of: progress ?? 0)
    }

    private static func share(of value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private var tint: Color {
        isFailure ? .orange : Theme.accent
    }

    private var baseFill: Color {
        if isFailure {
            return Theme.warning.opacity(hovering ? 0.16 : 0.1)
        }
        if isProminent {
            return Theme.chrome(hovering ? 0.17 : 0.13)
        }
        if isBusy {
            return SettingsMetrics.fill
        }
        return hovering ? SettingsMetrics.fillHover : SettingsMetrics.fill
    }

    private var border: Color {
        if isFailure {
            return Theme.warning.opacity(0.5)
        }
        if isProminent {
            return Theme.accent.opacity(hovering ? 0.6 : 0.4)
        }
        return hovering ? SettingsMetrics.borderHover : SettingsMetrics.border
    }

    private var label: AnyShapeStyle {
        if isFailure {
            return AnyShapeStyle(Theme.warning)
        }
        if isBusy {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle(.primary)
    }

    private var title: String {
        switch model.phase {
        case .checking:
            String(localized: "Checking…")
        case .available:
            String(localized: "Download")
        case .downloading:
            if model.isProgressKnown {
                String(localized: "update.banner.downloadingShare", defaultValue: "Downloading \(share)")
            } else {
                String(localized: "Downloading…")
            }
        case .extracting:
            if model.isProgressKnown {
                String(localized: "update.banner.preparingShare", defaultValue: "Preparing \(share)")
            } else {
                String(localized: "Preparing…")
            }
        case .readyToInstall:
            String(localized: "Install and Relaunch")
        case .installing:
            String(localized: "Installing…")
        case .failed:
            String(localized: "Try Again")
        case .idle, .upToDate:
            String(localized: "Check for Updates")
        }
    }

    private static var everyTitle: [String] {
        [
            String(localized: "Check for Updates"),
            String(localized: "Checking…"),
            String(localized: "Download"),
            String(localized: "update.banner.downloadingShare", defaultValue: "Downloading \(share(of: 1))"),
            String(localized: "Downloading…"),
            String(localized: "update.banner.preparingShare", defaultValue: "Preparing \(share(of: 1))"),
            String(localized: "Preparing…"),
            String(localized: "Install and Relaunch"),
            String(localized: "Installing…"),
            String(localized: "Try Again"),
        ]
    }
}

private struct Sweep: View {
    let tint: Color

    @State private var slide = false

    var body: some View {
        GeometryReader { proxy in
            tint.opacity(0.22)
                .frame(width: proxy.size.width * 0.4)
                .offset(x: slide ? proxy.size.width * 0.6 : 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                slide = true
            }
        }
    }
}

enum UpdatePhrasing {
    static func title(_ model: UpdateModel, idle: String = "") -> String {
        switch model.phase {
        case .available:
            String(localized: "Update to \(model.version)")
        case .downloading:
            String(localized: "Downloading \(model.version)")
        case .extracting:
            String(localized: "Preparing \(model.version)")
        case .readyToInstall:
            String(localized: "Update \(model.version) ready")
        case .installing:
            String(localized: "Installing")
        case .upToDate:
            String(localized: "Up to date")
        case .failed:
            String(localized: "Couldn’t check for updates")
        case .checking:
            String(localized: "Checking…")
        case .idle:
            idle
        }
    }

    static func caption(_ model: UpdateModel) -> String? {
        switch model.phase {
        case .available:
            "\(UpdateFeed.currentVersion) → \(model.version)"
        case .readyToInstall:
            String(localized: "Installing restarts Linen")
        case .failed(let message):
            message
        default:
            nil
        }
    }
}

private struct ProgressBar: View {
    let value: Double?
    let tint: Color

    @State private var slide = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Wash.hover)

                Capsule()
                    .fill(tint)
                    .frame(width: fillWidth(in: proxy.size.width))
                    .offset(x: value == nil ? slideOffset(in: proxy.size.width) : 0)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .onAppear {
            guard value == nil else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                slide = true
            }
        }
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard let value else { return width * 0.35 }
        return max(0, min(1, value)) * width
    }

    private func slideOffset(in width: CGFloat) -> CGFloat {
        slide ? width * 0.65 : 0
    }
}
