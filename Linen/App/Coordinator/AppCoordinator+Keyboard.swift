// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit

extension AppCoordinator {
    func installKeyMonitors() {
        installEscapeHandler()
        installTabSwitchHandler()
    }

    private func installTabSwitchHandler() {
        guard tabSwitchMonitor == nil else { return }
        tabSwitchMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.isKeyWindow else { return }
                self.tabSwitchModifiersChanged(event)
                self.noteLinkModifiers(event.modifierFlags)
            }
            return event
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.browser.endTabSwitching()
            }
        }
    }

    private func tabSwitchModifiersChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        guard flags.contains(.control) else {
            shiftStep.cancel()
            browser.endTabSwitching()
            return
        }
        guard event.keyCode == 56 || event.keyCode == 60 else { return }
        if flags.contains(.shift) {
            shiftStep.shiftDown(whileSwitching: browser.isSwitchingTabs)
        } else if shiftStep.shiftUp(), browser.isSwitchingTabs {
            browser.switchTab(forward: false)
        }
    }

    func noteLinkModifiers(_ flags: NSEvent.ModifierFlags) {
        let wanted = flags.intersection([.command, .shift, .option])
        guard wanted != linkModifiers else { return }
        linkModifiers = wanted
    }

    private func installEscapeHandler() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var claimed = false
            MainActor.assumeIsolated {
                claimed = self?.handleKey(event) ?? false
            }
            return claimed ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isKeyWindow else { return false }
        if browser.isSwitchingTabs {
            switch event.keyCode {
            case 53:
                browser.cancelTabSwitching()
                return true
            case 36, 76:
                browser.endTabSwitching()
                return true
            default:
                break
            }
        }
        if let responder = nativeWindow?.firstResponder, responder is NSText {
            return false
        }
        if peek.isOpen,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "o" {
            keepPeek()
            return true
        }
        guard event.keyCode == 53 else { return false }
        return handleEscape()
    }

    private func handleEscape() -> Bool {
        guard isKeyWindow else { return false }
        if let responder = nativeWindow?.firstResponder, responder is NSText {
            return false
        }
        if onboarding.isPresented {
            OnboardingUI.complete(model: onboarding, coordinator: self)
            return true
        }
        if overlays.isProfileSwitcherOpen {
            overlays.isProfileSwitcherOpen = false
            return true
        }
        if overlays.closeMinimalMenus() {
            return true
        }
        if closePeek() {
            return true
        }
        let closedInspector = sidePanel.close()
        if voiceConversation.isActive || state == .listening || state == .executing {
            voiceInput.cancel()
            stopAgent()
            return true
        }
        if answerSpeech.isSpeaking {
            speech.stopSpeaking()
            return true
        }
        if let tab = browser.activeTab, tab.isLoading {
            tab.stopLoading()
            return true
        }
        return closedInspector
    }
}
