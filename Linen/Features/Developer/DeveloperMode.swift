// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Network
import WebKit

nonisolated enum DeveloperMode {
    private static let localSuffixes = [".localhost", ".test", ".local"]

    static func host(of url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else { return nil }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host == "0.0.0.0" {
            return true
        }
        if let address = IPv4Address(host) {
            return address.rawValue.first == 127
        }
        if let address = IPv6Address(host) {
            return address.isLoopback
        }
        return localSuffixes.contains { host.hasSuffix($0) }
    }
}

struct DeveloperTools: Equatable {
    enum Appearance: CaseIterable {
        case system
        case light
        case dark

        var title: LocalizedStringResource {
            switch self {
            case .system:
                "Match System"
            case .light:
                "Light"
            case .dark:
                "Dark"
            }
        }

        var appearance: NSAppearance? {
            switch self {
            case .system:
                nil
            case .light:
                NSAppearance(named: .aqua)
            case .dark:
                NSAppearance(named: .darkAqua)
            }
        }
    }

    var showsFrameRate = false
    var outlinesElements = false
    var appearance = Appearance.system

    var hasOverlays: Bool {
        showsFrameRate || outlinesElements
    }
}

extension BrowserTab {
    var usesDeveloperMode: Bool {
        context.settings.usesDeveloperMode(for: URL(string: urlString))
    }

    func updateDeveloperTools(_ change: (inout DeveloperTools) -> Void) {
        let hadOverlays = developerTools.hasOverlays
        change(&developerTools)
        applyDeveloperAppearance()
        if hadOverlays || developerTools.hasOverlays {
            runOverlayScript(usesDeveloperMode ? developerTools : DeveloperTools())
        }
    }

    func applyDeveloperAppearance() {
        let appearance = usesDeveloperMode ? developerTools.appearance.appearance : nil
        guard webView.appearance != appearance else { return }
        webView.appearance = appearance
    }

    func applyDeveloperOverlays() {
        guard usesDeveloperMode, developerTools.hasOverlays else { return }
        runOverlayScript(developerTools)
    }

    private func runOverlayScript(_ tools: DeveloperTools) {
        webView.callAsyncJavaScript(
            DeveloperOverlayScript.source,
            arguments: ["fps": tools.showsFrameRate, "outlines": tools.outlinesElements],
            in: nil,
            in: .defaultClient,
            completionHandler: nil
        )
    }
}

private enum DeveloperOverlayScript {
    static let source = """
    const state = window.__linenDeveloper ??= {};
    if (fps && !state.fps) {
        const badge = document.createElement("div");
        badge.style.cssText = "position:fixed;top:8px;left:8px;z-index:2147483647;pointer-events:none;"
            + "padding:4px 7px;border-radius:6px;background:rgba(0,0,0,.7);color:#fff;"
            + "font:600 11px/1.2 ui-monospace,monospace;";
        document.documentElement.appendChild(badge);
        let frames = 0, start = performance.now(), running = true;
        const tick = (now) => {
            if (!running) return;
            frames += 1;
            if (now - start >= 500) {
                badge.textContent = Math.round(frames * 1000 / (now - start)) + " fps";
                frames = 0;
                start = now;
            }
            requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
        state.fps = () => { running = false; badge.remove(); };
    } else if (!fps && state.fps) {
        state.fps();
        delete state.fps;
    }
    if (outlines && !state.outlines) {
        const style = document.createElement("style");
        style.textContent = "* { outline: 1px solid rgba(255, 59, 48, .5) !important; outline-offset: -1px !important; }";
        document.documentElement.appendChild(style);
        state.outlines = () => style.remove();
    } else if (!outlines && state.outlines) {
        state.outlines();
        delete state.outlines;
    }
    """
}
