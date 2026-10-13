// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct TabPictureBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var tab: BrowserTab? {
        guard let tab = browser.activeTab, tab.hasVideo, !tab.isDeferred,
              tab.internalPage == nil
        else { return nil }
        return tab
    }

    private enum Face: Equatable {
        case video(out: Bool)
        case absent
    }

    private var face: Face {
        guard let tab else { return .absent }
        return .video(out: tab.isPictureOut)
    }

    private func pictureHelp(isOut: Bool) -> LocalizedStringResource {
        isOut ? "Exit Picture in Picture" : "Picture in Picture"
    }

    var body: some View {
        Group {
            if let tab {
                let isOut = tab.isPictureOut
                ChromeIcon(
                    symbol: isOut ? "pip.exit" : "pip.enter",
                    weight: .semibold,
                    help: String(localized: pictureHelp(isOut: isOut))
                ) {
                    coordinator.togglePictureInPicture(for: tab)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: face)
    }
}

struct PopupBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    private var blocked: (tab: BrowserTab, url: URL)? {
        guard let tab = browser.activeTab, let url = tab.popups.blocked else { return nil }
        return (tab, url)
    }

    var body: some View {
        Group {
            if let blocked {
                ChromeIcon(
                    symbol: "macwindow.badge.plus",
                    weight: .semibold,
                    tint: Theme.systemAccent,
                    help: String(localized: "Show Blocked Pop-up")
                ) {
                    blocked.tab.popups.clear()
                    coordinator.openNewTab(url: blocked.url)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: blocked?.url)
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
        if coordinator.answerSpeech.isSpeaking {
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
            if coordinator.answerSpeech.isSpeaking {
                ChromeIcon(
                    symbol: "speaker.wave.2.fill",
                    weight: .semibold,
                    tint: Theme.systemAccent,
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
                    tint: tab.isMuted ? nil : Theme.systemAccent,
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
