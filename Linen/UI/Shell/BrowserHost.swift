// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import os
import SwiftUI

@MainActor
final class BrowserHost: NSObject, NSWindowDelegate {
    static let windowControlsInset: CGFloat = 84

    static let topBarHeight: CGFloat = 44

    private var frameKey: String {
        guard let coordinator else { return "linen.browser.window" }
        return "linen.browser.window.\(coordinator.windowID.uuidString)"
    }
    var nativeWindow: NSWindow? {
        window
    }

    private weak var coordinator: AppCoordinator?
    private let content: NSHostingView<BrowserRootView>
    private var window: BrowserWindow?

    private let frameToolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: "linen.browser.frame")
        toolbar.allowsUserCustomization = false
        return toolbar
    }()

    private(set) var isVisible = false

    private var bloom: Bloom?
    private var isBlooming = false
    private var minimumWidth = BrowserWindowMetrics.minWidth

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        content = NSHostingView(rootView: BrowserRootView(coordinator: coordinator))
        content.safeAreaRegions = []
        super.init()
        publish()
    }

    // MARK: - Visibility

    func show(activate: Bool = true) {
        let window = ensureWindow()
        if !activate {
            window.orderFront(nil)
            window.alignWindowControls()
            isVisible = true
            publish()
            return
        }

        Pipeline.log.notice("""
        window: asked to show, in the Dock \(window.isMiniaturized), \
        on screen \(window.isVisible), app active \(NSApp.isActive), app hidden \(NSApp.isHidden)
        """)

        let wasActive = NSApp.isActive
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        if !wasActive {
            NSApp.activate()
            if !NSApp.isActive {
                NSRunningApplication.current.activate(
                    options: [.activateAllWindows]
                )
            }
        }
        // `makeKeyAndOrderFront` leaves a window that is in the Dock in the Dock,
        // and a miniaturized window cannot be made key.
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if !window.isVisible || !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        window.alignWindowControls()
        isVisible = true
        publish()
    }

    // MARK: - Opening

    func seedBloom() {
        let window = ensureWindow()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let target = window.frame
        bloom = Bloom(target: target, minSize: window.minSize)
        isBlooming = true
        window.setFrameAutosaveName("")
        window.minSize = .zero
        window.setFrame(
            NSRect(
                x: target.midX - Self.bloomSize.width / 2,
                y: target.midY - Self.bloomSize.height / 2,
                width: Self.bloomSize.width,
                height: Self.bloomSize.height
            ),
            display: false
        )
    }

    func bloomOpen() {
        guard let window, let bloom else { return }
        self.bloom = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            window.animator().setFrame(bloom.target, display: true)
        } completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                window?.minSize = bloom.minSize
                guard let self else { return }
                self.isBlooming = false
                if let window = self.window {
                    self.applyMinimumWidth(to: window)
                }
                if self.coordinator?.profiles.isPrivate == false {
                    window?.setFrameAutosaveName(self.frameKey)
                }
            }
        }
    }

    func setMinimumWidth(_ width: CGFloat) {
        guard width != minimumWidth else { return }
        minimumWidth = width
        guard let window, !isBlooming else { return }
        applyMinimumWidth(to: window)
    }

    private func applyMinimumWidth(to window: NSWindow) {
        window.minSize = NSSize(width: minimumWidth, height: window.minSize.height)
        guard !window.styleMask.contains(.fullScreen), window.frame.width < minimumWidth else { return }
        var frame = window.frame
        frame.size.width = minimumWidth
        if let visible = window.screen?.visibleFrame, frame.maxX > visible.maxX {
            frame.origin.x = max(visible.minX, visible.maxX - frame.width)
        }
        window.setFrame(frame, display: true)
    }

    private struct Bloom {
        let target: NSRect
        let minSize: NSSize
    }

    private static let bloomSize = NSSize(width: 480, height: 360)

    // MARK: - Window

    private func ensureWindow() -> BrowserWindow {
        if let window {
            return window
        }

        let created = BrowserWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = "Linen"
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.toolbar = frameToolbar
        created.toolbarStyle = .unified
        created.titlebarSeparatorStyle = .none
        created.isOpaque = false
        created.backgroundColor = .clear
        created.minSize = NSSize(width: minimumWidth, height: 580)
        created.preservesContentDuringLiveResize = true
        created.collectionBehavior = [.fullScreenPrimary]
        created.isReleasedWhenClosed = false
        created.isMovableByWindowBackground = false
        created.tabbingMode = .disallowed
        created.isRestorable = false
        created.onSideButton = { [weak coordinator] forward in
            guard let tab = coordinator?.pageCommandTab else { return }
            if forward {
                tab.goForward()
            } else {
                tab.goBack()
            }
        }
        created.delegate = self
        dropSavedTilingState()
        if coordinator?.profiles.isPrivate == false {
            created.setFrameAutosaveName(frameKey)
        }
        if coordinator?.profiles.isPrivate == true || !created.setFrameUsingName(frameKey) {
            created.setFrame(Self.openingFrame(for: created), display: false)
        }
        applyMinimumWidth(to: created)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        content.frame = root.bounds
        content.autoresizingMask = [.width, .height]
        root.addSubview(content)
        root.addSubview(WebViewParkingShelf(frame: .zero))
        created.contentView = root
        SystemWindowShape.adopt(created)
        roundContentCorners(of: created)
        Self.hideTitlebarDecoration(of: created)

        window = created
        if let coordinator {
            coordinator.extensions.register(browser: coordinator.browser, window: created)
        }
        return created
    }

    /// Answers false when it hid nothing: the decoration is matched by private
    /// class name, and a rename would otherwise pass silently.
    @discardableResult
    static func hideTitlebarDecoration(of window: NSWindow) -> Bool {
        guard let frameView = window.contentView?.superview else { return false }
        var hidAny = false
        for container in frameView.subviews where container.className.hasSuffix("NSTitlebarContainerView") {
            for decoration in container.subviews where decoration.className.contains("TitlebarDecoration") {
                decoration.isHidden = true
                hidAny = true
            }
        }
        return hidAny
    }

    private func roundContentCorners(of window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }

        let isFullScreen = window.styleMask.contains(.fullScreen)
        layer.cornerRadius = isFullScreen ? 0 : SystemWindowShape.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = !isFullScreen
    }

    /// Removes the tiling slot from the autosaved frame. macOS 26 replays it
    /// and reopens the window tiled, ignoring the frame saved beside it.
    private func dropSavedTilingState() {
        let key = "NSWindow Frame \(frameKey)"
        let defaults = UserDefaults.standard
        guard let saved = defaults.string(forKey: key),
              let blob = saved.firstIndex(of: "{") else { return }
        defaults.set(String(saved[..<blob]), forKey: key)
    }

    private static func openingFrame(for window: NSWindow) -> NSRect {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return window.frame }
        let size = NSSize(
            width: min(visible.width, max(window.minSize.width, visible.width * 0.9)),
            height: min(visible.height, max(window.minSize.height, visible.height * 0.9))
        )
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Window delegate

    func windowDidBecomeKey(_ notification: Notification) {
        coordinator?.windowDidBecomeKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        coordinator?.windowDidResignKey()
    }

    func windowWillClose(_ notification: Notification) {
        isVisible = false
        publish()
        guard let coordinator else { return }
        coordinator.windowDidClose()
    }

    func windowWillMiniaturize(_ notification: Notification) {
        coordinator?.moveVideoToPictureInPicture()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.toolbar = nil
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        window?.toolbar = frameToolbar
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        if let window {
            roundContentCorners(of: window)
        }
        publish()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.alignWindowControls()
        if let window {
            roundContentCorners(of: window)
        }
        publish()
    }

    func windowDidResize(_ notification: Notification) {
        window?.alignWindowControls()
    }

    // MARK: - State out

    private var windowControlsInset: CGFloat {
        guard let window, window.styleMask.contains(.fullScreen) else {
            return Self.windowControlsInset
        }
        return 0
    }

    private func publish() {
        coordinator?.hostDidChange(visible: isVisible, controlsInset: windowControlsInset)
    }
}

enum SystemWindowShape {
    static var cornerRadius: CGFloat {
        if let measured {
            return measured
        }
        let radius = measure()
        measured = radius
        return radius
    }

    static func adopt(_ window: NSWindow) {
        guard let radius = radius(of: window) else { return }
        measured = radius
    }

    private static var measured: CGFloat?

    private static let assumedCornerRadius: CGFloat = 16

    private static func measure() -> CGFloat {
        let probe = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        probe.contentView = NSView()
        guard let radius = radius(of: probe) else {
            Pipeline.log.warning("no window frame would report its corner radius; using the app's own")
            return assumedCornerRadius
        }
        return radius
    }

    private static func radius(of window: NSWindow) -> CGFloat? {
        guard let frameView = window.contentView?.superview else { return nil }
        for key in ["cornerRadius", "_cornerRadius"] {
            guard frameView.responds(to: NSSelectorFromString(key)),
                  let radius = frameView.value(forKey: key) as? CGFloat,
                  radius > 1
            else { continue }
            return radius
        }
        return radiusFromMask(of: frameView)
    }

    private static func radiusFromMask(of frameView: NSView) -> CGFloat? {
        var image: NSImage?
        for key in ["_cornerMask", "cornerMask"] {
            guard frameView.responds(to: NSSelectorFromString(key)) else { continue }
            image = frameView.value(forKey: key) as? NSImage
            if image != nil {
                break
            }
        }
        guard let image,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 1, image.size.width > 0
        else { return nil }

        let scale = CGFloat(bitmap.pixelsWide) / image.size.width
        let limit = min(bitmap.pixelsWide, bitmap.pixelsHigh) / 2
        var missing: CGFloat = 0
        for y in 0..<limit {
            for x in 0..<limit {
                missing += 1 - (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1)
            }
        }
        let radius = (missing / continuousCornerUnitArea).squareRoot() / scale
        guard radius > 1 else { return nil }
        return radius
    }

    private static let continuousCornerUnitArea: CGFloat = {
        let side = 64
        let radius: CGFloat = 16
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 1 - .pi / 4 }
        layer.render(in: context)
        guard let rendered = context.makeImage() else { return 1 - .pi / 4 }
        let reference = NSBitmapImageRep(cgImage: rendered)
        var missing: CGFloat = 0
        for y in 0..<(side / 2) {
            for x in 0..<(side / 2) {
                missing += 1 - (reference.colorAt(x: x, y: y)?.alphaComponent ?? 1)
            }
        }
        guard missing > 0 else { return 1 - .pi / 4 }
        return missing / (radius * radius)
    }()
}

struct BrowserRootView: View {
    let coordinator: AppCoordinator

    var body: some View {
        BrowserView(browser: coordinator.browser, coordinator: coordinator)
            .disclosureGroupStyle(ClickableDisclosureStyle())
            .writingToolsAffordanceVisibility(.hidden)
            .environment(\.windowControlsInset, coordinator.windowControlsInset)
            .environment(\.profileFavicons, coordinator.browser.context.favicons)
            .environment(\.assistantProviderID, coordinator.selectedProvider.id)
            .onChange(of: coordinator.windowTitle) { _, _ in
                coordinator.updateWindowAppearance()
            }
            .onChange(of: coordinator.handoffURL) { _, _ in
                coordinator.updateHandoff()
            }
            .onChange(of: coordinator.windowMinimumWidth, initial: true) { _, _ in
                coordinator.updateWindowMinimum()
            }
    }
}

extension EnvironmentValues {
    @Entry var windowControlsInset: CGFloat = 0
}

nonisolated enum BrowserWindowMetrics {
    static let minWidth: CGFloat = 680

    static func minWidth(dockedSidebarWidth: CGFloat?, isPanelVisible: Bool) -> CGFloat {
        guard isPanelVisible else { return minWidth }
        let besidePanel = (dockedSidebarWidth ?? 0) + SidePanelMetrics.pageMinWidth
        return max(minWidth, besidePanel + SidePanelMetrics.minWidth)
    }
}

private final class BrowserWindow: NSWindow {
    var onSideButton: ((Bool) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            guard event.buttonNumber == 3 || event.buttonNumber == 4 else { break }
            if event.type == .otherMouseDown {
                onSideButton?(event.buttonNumber == 4)
            }
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = firstResponder as? NSTextView, editor.isEditable,
           ShortcutPriority.textEditorAnswersFirst(event) {
            editor.keyDown(with: event)
            return true
        }
        if ShortcutPriority.menuAnswersFirst(event),
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if WebKeyEcho.shouldSilenceUnhandledKey(from: firstResponder) {
            return
        }
        super.keyDown(with: event)
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        alignWindowControls()
    }

    private static let leadingInset: CGFloat = 14

    func alignWindowControls() {
        BrowserHost.hideTitlebarDecoration(of: self)
        guard !styleMask.contains(.fullScreen) else { return }
        guard let close = standardWindowButton(.closeButton) else { return }
        let dx = Self.leadingInset - close.frame.origin.x

        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(kind), let titlebar = button.superview else { continue }
            let fromTop = BrowserHost.topBarHeight / 2 - button.frame.height / 2
            let y = titlebar.bounds.height - fromTop - button.frame.height
            let x = button.frame.origin.x + dx
            guard abs(button.frame.origin.y - y) > 0.5 || abs(dx) > 0.5 else { continue }
            button.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            guard let window, window.isMovable else {
                super.mouseDown(with: event)
                return
            }
            if event.clickCount == 2 {
                Self.performDoubleClickAction(on: window)
                return
            }
            window.performDrag(with: event)
        }

        private static func performDoubleClickAction(on window: NSWindow) {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize":
                window.performMiniaturize(nil)
            case "None":
                break
            default:
                window.performZoom(nil)
            }
        }
    }
}
