// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct MediaSidebarCard: View {
    let media: MediaCenter
    let coordinator: AppCoordinator
    @Binding var obscuredHeight: CGFloat

    private var goToSource: (() -> Void)? {
        guard let tabID = media.controlledTabID,
              let tab = coordinator.browser.tabs.first(where: { $0.id == tabID })
        else { return nil }
        return { coordinator.openTab(tab) }
    }

    private var playerVisibilityHelp: LocalizedStringResource {
        isPlayerHidden ? "Show Video" : "Hide Video"
    }

    private var showsLyricsButton: Bool {
        coordinator.settings.showsLyrics && !coordinator.sidePanel.isShowing(.lyrics)
    }

    private var pipHelp: LocalizedStringResource {
        media.model.isInNativePiP ? "Exit Picture in Picture" : "Picture in Picture"
    }

    private var titleFont: Font {
        .system(size: 11, weight: .medium)
    }

    @ViewBuilder
    private func pickerRow(_ tab: BrowserTab, isDocked: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { isDocked },
            set: { isOn in
                guard isOn else { return }
                coordinator.dockMedia(tab)
            }
        )) {
            Text(verbatim: tab.title)
        }
    }

    @ViewBuilder
    private var title: some View {
        let items = coordinator.mediaPickerTabs
        let docked = media.controlledTabID
        let playing = items.filter { $0.isPlayingAudio || $0.id == docked }
        let quiet = items.filter { !($0.isPlayingAudio || $0.id == docked) }
        if items.count > 1 {
            Menu {
                ForEach(playing) { tab in
                    pickerRow(tab, isDocked: docked == tab.id)
                }
                if !quiet.isEmpty {
                    Divider()
                    ForEach(quiet) { tab in
                        pickerRow(tab, isDocked: docked == tab.id)
                    }
                }
            } label: {
                Text(verbatim: media.model.title)
                    .font(titleFont)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.secondary)
            .help("Choose Which Tab to Control")
        } else {
            Text(verbatim: media.model.title)
                .font(titleFont)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }

    @Environment(\.sidebarStyle) private var sidebarStyle
    @Environment(\.sidebarWidth) private var sidebarWidth

    @State private var isPulledOut = false

    @State private var isPlayerHidden = false

    @State private var panelFrame: CGRect = .zero

    @State private var buttonFrame: CGRect = .zero

    private var isStowed: Bool {
        sidebarStyle != .full
    }

    private var isCompact: Bool {
        Self.isCompact(panelWidth: panelWidth)
    }

    nonisolated static let widthForRoomyControls: CGFloat = 210

    nonisolated static func isCompact(panelWidth: CGFloat) -> Bool {
        panelWidth < widthForRoomyControls
    }

    nonisolated static func panelWidth(sidebarWidth: CGFloat, isStowed: Bool) -> CGFloat {
        isStowed ? floatingWidth : max(sidebarWidth - 24, 150)
    }

    nonisolated static func controlsWidth(panelWidth: CGFloat) -> CGFloat {
        panelWidth - 2 * controlsInset(panelWidth: panelWidth)
    }

    nonisolated static func controlsInset(panelWidth: CGFloat) -> CGFloat {
        isCompact(panelWidth: panelWidth) ? 8 : 10
    }

    private var showsPlayer: Bool {
        !isStowed || isPulledOut
    }
    private var showsVideo: Bool {
        showsPlayer && !isPlayerHidden && !media.model.isInNativePiP
    }

    nonisolated static let floatingWidth: CGFloat = 300
    private nonisolated static let buttonHeight: CGFloat = 26

    var body: some View {
        inFlow
            .frame(maxWidth: .infinity, alignment: sidebarStyle == .full ? .leading : .center)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { buttonFrame = $0 }
            .overlay(alignment: .bottomLeading) { panel }
            .padding(.vertical, 4)
            .background {
                ClickOutsideCatcher(isActive: isStowed && isPulledOut, keepingOut: [panelFrame, buttonFrame]) {
                    isPulledOut = false
                }
                .allowsHitTesting(false)
            }
            .onChange(of: isStowed) { _, stowed in
                if !stowed {
                    isPulledOut = false
                }
            }
            .animation(Theme.Motion.drift, value: showsPlayer)
            .animation(Theme.Motion.drift, value: isStowed)
    }

    @ViewBuilder
    private var inFlow: some View {
        if isStowed {
            stowedButton
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let picture = media.model.pictureWebView, let crop = media.pictureCrop {
                MediaPlayerSurface(
                    media: media,
                    webView: picture,
                    crop: crop,
                    width: panelWidth,
                    cornerRadius: Theme.Radius.control,
                    isStowed: !showsVideo
                )
                .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
                .padding(.bottom, showsVideo ? 6 : 0)
            }

            if showsPlayer {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: isCompact ? 6 : 8) {
                        title

                        Spacer(minLength: 4)

                        if showsLyricsButton {
                            MediaButton(
                                systemName: "quote.bubble",
                                size: 9,
                                help: "Show Lyrics"
                            ) {
                                coordinator.toggleLyrics()
                            }
                        }

                        if media.model.pictureWebView != nil, !media.model.isInNativePiP {
                            MediaButton(
                                systemName: isPlayerHidden ? "eye.slash" : "eye",
                                size: 9,
                                help: playerVisibilityHelp
                            ) {
                                isPlayerHidden.toggle()
                            }
                        }

                        if media.model.hasVideo {
                            MediaButton(
                                systemName: media.model.isInNativePiP ? "pip.exit" : "pip.enter",
                                size: 9,
                                help: pipHelp
                            ) {
                                media.toggleNativePiP()
                            }
                        }

                        if let goToSource {
                            MediaButton(
                                systemName: "arrow.up.right",
                                size: 9,
                                help: "Go to the Tab Playing This",
                                action: goToSource
                            )
                        }

                        MediaButton(systemName: "xmark", size: 9, help: "Pause and Close") {
                            media.close()
                        }
                    }

                    MediaTimeline(media: media, isCompact: true)
                    MediaTransport(media: media, isCompact: isCompact)
                }
                .padding(.horizontal, Self.controlsInset(panelWidth: panelWidth))
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
                .contentShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
                .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: panelWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: isStowed ? -(Self.buttonHeight + 6) : 0)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }
        .onGeometryChange(for: CGFloat.self) { [isStowed, showsPlayer] proxy in
            let panelHeight = proxy.size.height
            if isStowed {
                return showsPlayer
                    ? panelHeight + Self.buttonHeight + 10
                    : Self.buttonHeight + 8
            }
            return panelHeight + 8
        } action: { obscuredHeight = $0 }
        .onDisappear { obscuredHeight = 0 }
    }

    private var panelWidth: CGFloat {
        Self.panelWidth(sidebarWidth: sidebarWidth, isStowed: isStowed)
    }

    private var stowedButton: some View {
        Button {
            isPulledOut.toggle()
        } label: {
            Image(systemName: media.model.isPlaying ? "waveform" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPulledOut ? Theme.accent : Color.secondary)
        .glassEffect(.regular, in: .capsule)
        .help(isPulledOut ? Text("Hide Player") : Text(verbatim: media.model.title))
    }
}

private struct ClickOutsideCatcher: NSViewRepresentable {
    let isActive: Bool
    let keepingOut: [CGRect]
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: Catcher, context: Context) {
        apply(to: nsView)
    }

    static func dismantleNSView(_ nsView: Catcher, coordinator: ()) {
        nsView.stop()
    }

    private func apply(to view: Catcher) {
        view.keepingOut = keepingOut
        view.onClickOutside = onClickOutside
        view.isActive = isActive
    }

    final class Catcher: NSView {
        var keepingOut: [CGRect] = []
        var onClickOutside: (() -> Void)?

        var isActive = false {
            didSet {
                guard isActive != oldValue else { return }
                if isActive {
                    start()
                } else {
                    stop()
                }
            }
        }

        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
                return event
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window, event.window === window, let content = window.contentView else { return }
            let inContent = content.convert(event.locationInWindow, from: nil)
            let point = content.isFlipped
                ? inContent
                : CGPoint(x: inContent.x, y: content.bounds.height - inContent.y)
            guard !keepingOut.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(point) }) else { return }
            onClickOutside?()
        }
    }
}
