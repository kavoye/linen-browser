// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import WebKit

@MainActor
final class ExtensionPopups {
    private var anchors: [ObjectIdentifier: [String: NSView]] = [:]
    private var overflowAnchors: [ObjectIdentifier: NSView] = [:]
    private(set) var popover: NSPopover?
    private(set) var popupID: String?
    private(set) weak var window: ExtensionWindowAdapter?
    private var closeObserver: (any NSObjectProtocol)?
    private var lastDismissedID: String?
    private var lastDismissal = Date.distantPast
    private var reloadedForEmpty: Set<String> = []

    func register(_ view: NSView?, for id: String, in browser: BrowserModel) {
        anchors[ObjectIdentifier(browser), default: [:]][id] = view
    }

    func registerOverflow(_ view: NSView?, in browser: BrowserModel) {
        overflowAnchors[ObjectIdentifier(browser)] = view
    }

    func forgetAnchors(for id: String) {
        for key in anchors.keys {
            anchors[key]?[id] = nil
        }
    }

    func forget(_ browser: BrowserModel, window: ExtensionWindowAdapter) {
        let identifier = ObjectIdentifier(browser)
        anchors[identifier] = nil
        overflowAnchors[identifier] = nil
        if self.window === window {
            close()
        }
    }

    func anchor(for id: String, in browser: BrowserModel) -> NSView? {
        let key = ObjectIdentifier(browser)
        if let own = anchors[key]?[id], own.window != nil {
            return own
        }
        if let overflow = overflowAnchors[key], overflow.window != nil {
            return overflow
        }
        return nil
    }

    func handlesRepeatClick(on id: String) -> Bool {
        if let popover, popupID == id, popover.isShown {
            popover.performClose(nil)
            return true
        }
        return lastDismissedID == id && Date().timeIntervalSince(lastDismissal) < 0.3
    }

    func show(_ popover: NSPopover, for id: String, in window: ExtensionWindowAdapter, at anchor: NSView) {
        popover.behavior = .transient
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.popover = nil
                self.popupID = nil
                self.window = nil
                self.lastDismissedID = id
                self.lastDismissal = Date()
            }
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        Self.clip(popover)
        self.popover = popover
        popupID = id
        self.window = window
    }

    func isShowing(_ id: String, in window: ExtensionWindowAdapter) -> Bool {
        self.window === window && popupID == id && popover?.isShown == true
    }

    func close() {
        popover?.performClose(nil)
        popover = nil
        popupID = nil
        window = nil
    }

    func noteReloadForEmptyPage(_ id: String) -> Bool {
        reloadedForEmpty.insert(id).inserted
    }

    func reset() {
        anchors = [:]
        overflowAnchors = [:]
        reloadedForEmpty = []
        popover?.performClose(nil)
        popover = nil
        popupID = nil
    }

    private static func clip(_ popover: NSPopover) {
        guard let content = popover.contentViewController?.view,
              let frameView = content.window?.contentView?.superview
        else { return }

        guard let radius = plateCornerRadius(of: frameView) else {
            Pipeline.log.notice("""
                ext: popup left unclipped - \
                \(String(describing: type(of: frameView)), privacy: .public) \
                bounds \(NSStringFromRect(frameView.bounds), privacy: .public) \
                reports no plausible corner \
                (layer \(frameView.layer?.cornerRadius ?? -1, privacy: .public))
                """)
            return
        }

        content.wantsLayer = true
        content.layer?.cornerRadius = radius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        Pipeline.log.notice("ext: popup clipped to the plate's \(radius, privacy: .public)pt corner")
    }

    private static func plateCornerRadius(of frameView: NSView) -> CGFloat? {
        let limit = min(frameView.bounds.width, frameView.bounds.height) / 4
        guard limit > 1 else { return nil }

        for key in ["cornerRadius", "_cornerRadius"] {
            guard frameView.responds(to: NSSelectorFromString(key)),
                  let radius = frameView.value(forKey: key) as? CGFloat,
                  radius > 1, radius <= limit
            else { continue }
            return radius
        }
        if let radius = frameView.layer?.cornerRadius, radius > 1, radius <= limit {
            return radius
        }
        return nil
    }
}
