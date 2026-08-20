// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct SiteControlsMenu: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    @State private var hovering = false
    @Environment(\.chromeIsLight) private var chromeIsLight

    private var tab: BrowserTab? {
        browser.activeTab
    }
    private var hasPage: Bool {
        !(tab?.urlString.isEmpty ?? true)
    }

    var body: some View {
        Menu {
            SiteControlsItems(browser: browser, coordinator: coordinator)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ChromeInk.glyph(onLight: chromeIsLight, hovering: hovering))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!hasPage)
        .opacity(hasPage ? 1 : 0.4)
        .onHover { hovering = $0 }
        .hoverVerified($hovering)
        .help("Site Settings")
    }

}

struct SiteControlsItems: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var tab: BrowserTab? {
        browser.activeTab
    }

    var body: some View {
        Button {
            guard let tab else { return }
            coordinator.copyLink(for: tab)
        } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
        }
        .disabled(tab.flatMap { coordinator.linkURL(for: $0) } == nil)

        Divider()

        if let tab, !tab.assistantAccess.origin.isEmpty {
            Menu {
                ForEach(AssistantAccessPolicy.allCases, id: \.self) { policy in
                    Button {
                        tab.assistantAccess.set(policy)
                    } label: {
                        if tab.assistantAccess.effectivePolicy == policy {
                            Label {
                                Text(policy.label)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        } else {
                            Text(policy.label)
                        }
                    }
                }
            } label: {
                Label("Assistant Access", systemImage: "sparkles")
            }

            Divider()
        }

        if let tab, !browser.keepActiveOrigin(for: tab).isEmpty {
            Button {
                browser.setKeepsActive(!browser.keepsActive(tab), for: tab)
            } label: {
                Label(
                    "Always Keep This Website Loaded",
                    systemImage: browser.keepsActive(tab) ? "checkmark" : "bolt"
                )
            }

            Divider()
        }

        Button {
            tab?.resetZoom()
        } label: {
            Label("Actual Size", systemImage: "1.magnifyingglass")
        }
        .disabled(!(tab?.isZoomed ?? false))
        Button {
            tab?.zoomIn()
        } label: {
            Label("Zoom In", systemImage: "plus.magnifyingglass")
        }
        Button {
            tab?.zoomOut()
        } label: {
            Label("Zoom Out", systemImage: "minus.magnifyingglass")
        }

        Divider()

        if let host = blockableHost {
            Button {
                let blocker = ContentBlocker.shared
                blocker.setExempt(!blocker.isExempt(host), for: host)
                tab?.webView.reload()
            } label: {
                if ContentBlocker.shared.isExempt(host) {
                    Label("Block Trackers on This Website", systemImage: "shield")
                } else {
                    Label("Allow Trackers on This Website", systemImage: "shield.slash")
                }
            }
        }

        Button {
            tab?.webView.reload()
        } label: {
            Label("Reload Page", systemImage: "arrow.clockwise")
        }
    }

    private var blockableHost: String? {
        guard BrowserSettings.shared.blocksTrackers,
              let host = tab.flatMap({ URL(string: $0.urlString)?.host() }),
              !host.isEmpty
        else { return nil }
        return host
    }
}

struct TabAudioBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var tab: BrowserTab? {
        guard let tab = browser.activeTab, tab.isPlayingAudio || tab.isMuted else { return nil }
        return tab
    }

    private enum Face: Equatable {
        case speaking
        case tab(muted: Bool)
        case absent
    }

    private var face: Face {
        if coordinator.isAgentSpeaking {
            return .speaking
        }
        guard let tab else { return .absent }
        return .tab(muted: tab.isMuted)
    }

    private func muteHelp(isMuted: Bool) -> LocalizedStringResource {
        isMuted ? "Unmute This Tab" : "Mute This Tab"
    }

    var body: some View {
        Group {
            if coordinator.isAgentSpeaking {
                ChromeIcon(
                    symbol: "speaker.wave.2.fill",
                    weight: .semibold,
                    tint: Theme.accent,
                    help: String(localized: "Stop Speaking")
                ) {
                    coordinator.stopAgentSpeech()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            } else if let tab {
                ChromeIcon(
                    symbol: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    weight: .semibold,
                    isSubdued: tab.isMuted,
                    help: String(localized: muteHelp(isMuted: tab.isMuted))
                ) {
                    coordinator.toggleMute(tab: tab)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: face)
    }
}
