// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Security
import SwiftUI
import WebKit

final class AutofillSuggestions {
    static let shared = AutofillSuggestions()
    var openSettings: (() -> Void)?

    private final class Request: NSObject {
        let token: String
        let kind: AutofillSaveKind
        let profileID: UUID
        let frame: WKFrameInfo
        let frameURL: URL
        let topURL: URL
        let world: WKContentWorld
        let bridge: String
        let documentID: String
        let formID: String
        let fieldID: String
        var rect = NSRect.zero

        init(token: String, kind: AutofillSaveKind, profileID: UUID, message: WKScriptMessage,
             frameURL: URL, topURL: URL, world: WKContentWorld, bridge: String,
             documentID: String, formID: String, fieldID: String) {
            self.token = token; self.kind = kind; self.profileID = profileID
            frame = message.frameInfo; self.frameURL = frameURL; self.topURL = topURL
            self.world = world; self.bridge = bridge
            self.documentID = documentID; self.formID = formID; self.fieldID = fieldID
        }
    }

    private let requests = NSMapTable<WKWebView, Request>.weakToStrongObjects()
    private weak var webView: WKWebView?
    private var presentationID = UUID()
    private var panel: AutofillSuggestionPanel?
    private var suggestions: [AutofillSuggestion] = []
    private let selection = AutofillSuggestionSelection()
    private var choose: ((UUID) -> Void)?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var securityObservers: [NSObjectProtocol] = []
    private var navigation: NSKeyValueObservation?
    private var loading: NSKeyValueObservation?
    private var isFilling = false
    private var geometryWatch: Task<Void, Never>?
    private let passwordAuthentication = PasswordFillAuthenticationCache()

    private init() {
        for centerAndName in [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification),
            (DistributedNotificationCenter.default(), NSNotification.Name("com.apple.screenIsLocked")),
        ] {
            securityObservers.append(centerAndName.0.addObserver(forName: centerAndName.1, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.passwordAuthentication.clear() }
            })
        }
    }

    func reset() {
        dismiss()
        requests.removeAllObjects()
        passwordAuthentication.clear()
    }

    func dismiss(in view: WKWebView? = nil) {
        if let view, webView !== view {
            return
        }
        presentationID = UUID()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        webView = nil
        suggestions = []
        choose = nil
        selection.keyboardID = nil
        navigation = nil; loading = nil
        geometryWatch?.cancel(); geometryWatch = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    func receive(_ message: WKScriptMessage, kind: AutofillSaveKind, profileID: UUID,
                 world: WKContentWorld, bridge: String) {
        guard let view = message.webView, let body = message.body as? [String: Any],
              let action = body["action"] as? String, let token = body["token"] as? String,
              UUID(uuidString: token) != nil else { return }
        if action == "dismiss" || action == "hide" {
            guard requests.object(forKey: view)?.token == token else { return }
            if action == "dismiss" { requests.removeObject(forKey: view) }
            dismiss(in: view)
            return
        }
        guard action == "select", !isFilling,
              let documentID = body["documentID"] as? String, UUID(uuidString: documentID) != nil,
              let formID = body["formID"] as? String, let formNumber = Int(formID), formNumber > 0,
              let fieldID = body["fieldID"] as? String, let fieldNumber = Int(fieldID), fieldNumber > 0,
              AutofillSaveCoordinator.shared.isEnabled(kind, profileID: profileID),
              let rawURL = body["url"] as? String, let frameURL = URL(string: rawURL),
              let topURL = view.url, SavedPassword.origin(for: topURL) != nil,
              let origin = SavedPassword.origin(for: frameURL), view.hasOnlySecureContent,
              message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == frameURL.host,
              (message.frameInfo.securityOrigin.port == 0 ? 443 : message.frameInfo.securityOrigin.port) == (frameURL.port ?? 443),
              Self.canPresent(in: view)
        else { return }

        if webView === view, let current = requests.object(forKey: view),
           current.token == token, current.kind == kind, current.profileID == profileID,
           current.documentID == documentID, current.fieldID == fieldID,
           current.formID == formID, current.frameURL == frameURL, current.topURL == topURL { return }

        dismiss()
        let request = Request(token: token, kind: kind, profileID: profileID, message: message,
                              frameURL: frameURL, topURL: topURL, world: world, bridge: bridge,
                              documentID: documentID, formID: formID, fieldID: fieldID)
        requests.setObject(request, forKey: view)
        webView = view
        let id = presentationID
        Task { [weak view] in
            guard let view else { return }
            guard let rect = try? await resolveFieldRect(body["rect"], request: request, in: view),
                  id == presentationID, requests.object(forKey: view) === request else { return }
            request.rect = rect
            AutofillDiagnostics.note(.fieldSelected, kind: kind)
            let records = try? await Task.detached {
                try AutofillSaveIndex.suggestions(kind: kind, origin: origin, profileID: profileID)
            }.value
            guard id == presentationID else { return }
            AutofillDiagnostics.note(records == nil ? .lookupFailed : .lookupCompleted, kind: kind, count: records?.count ?? 0)
            guard let records, !records.isEmpty,
                  (try? await validate(request, in: view, requiresFocus: true)) != nil,
                  id == presentationID, Self.canPresent(in: view) else { return }
            show(records, request: request, in: view)
        }
    }

    private func resolveFieldRect(_ value: Any?, request: Request, in view: WKWebView) async throws -> NSRect {
        guard var values = value as? [String: Double] else { throw ContactAutofillError.noField }
        if values["embedded"] == 1 {
            guard !request.frame.isMainFrame, let origin = SavedPassword.origin(for: request.frameURL),
                  let x = values["x"], let y = values["y"], let width = values["width"], let height = values["height"],
                  let viewportWidth = values["viewportWidth"], let viewportHeight = values["viewportHeight"],
                  [x, y, width, height, viewportWidth, viewportHeight].allSatisfy(\.isFinite),
                  viewportWidth > 0, viewportHeight > 0, x >= 0, y >= 0,
                  x + width <= viewportWidth, y + height <= viewportHeight else { throw ContactAutofillError.noField }
            let answer = try await view.callAsyncJavaScript(
                "return globalThis.__linenAutofillSuggestions?.frameBounds(origin);",
                arguments: ["origin": origin], in: nil, contentWorld: request.world
            )
            guard let frame = answer as? [String: Double],
                  let frameX = frame["x"], let frameY = frame["y"], let frameWidth = frame["width"], let frameHeight = frame["height"],
                  let topWidth = frame["viewportWidth"], let topHeight = frame["viewportHeight"] else { throw ContactAutofillError.noField }
            values = ["x": frameX + x * frameWidth / viewportWidth, "y": frameY + y * frameHeight / viewportHeight,
                      "width": width * frameWidth / viewportWidth, "height": height * frameHeight / viewportHeight,
                      "viewportWidth": topWidth, "viewportHeight": topHeight, ]
        }
        guard let rect = Self.fieldRect(values, in: view) else { throw ContactAutofillError.noField }
        return rect
    }

    private static func canPresent(in view: WKWebView) -> Bool {
        NSApp.isActive && view.window?.isKeyWindow == true && !view.isHiddenOrHasHiddenAncestor
    }

    private static func isFocused(_ view: WKWebView) -> Bool {
        guard NSApp.isActive, view.window?.isKeyWindow == true, !view.isHiddenOrHasHiddenAncestor,
              let responder = view.window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    private static func fieldRect(_ value: Any?, in view: WKWebView) -> NSRect? {
        guard let values = value as? [String: Double],
              let x = values["x"], let y = values["y"], let width = values["width"], let height = values["height"],
              let viewportWidth = values["viewportWidth"], let viewportHeight = values["viewportHeight"],
              [x, y, width, height, viewportWidth, viewportHeight].allSatisfy(\.isFinite),
              width > 2, height > 2, viewportWidth > 0, viewportHeight > 0,
              width <= viewportWidth * 2, height <= viewportHeight,
              x >= 0, y >= 0, x < viewportWidth, y + height <= viewportHeight else { return nil }
        let sx = view.bounds.width / viewportWidth, sy = view.bounds.height / viewportHeight
        let rect = NSRect(x: x * sx, y: view.isFlipped ? y * sy : view.bounds.height - (y + height) * sy,
                          width: min(width, viewportWidth - x) * sx, height: height * sy)
        return view.visibleRect.contains(rect) ? rect : nil
    }

    private func show(_ records: [AutofillSuggestion], request: Request, in view: WKWebView) {
        guard !records.isEmpty, let window = view.window else { return }
        let field = window.convertToScreen(view.convert(request.rect, to: nil))
        var page = window.convertToScreen(view.convert(view.visibleRect, to: nil)).intersection(window.frame)
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(NSPoint(x: field.midX, y: field.midY)) } ?? window.screen
        if let screen {
            page = page.intersection(screen.visibleFrame)
        }
        guard !page.isNull, !page.isEmpty, page.intersects(field) else { return }
        let width = min(360.0, page.width - 16)
        let availableBelow = max(0, field.minY - page.minY - 12)
        let availableAbove = max(0, page.maxY - field.maxY - 12)
        let desiredHeight = AutofillSuggestionLayout.height(for: records.count)
        let below = availableBelow >= desiredHeight || (availableAbove < desiredHeight && availableBelow >= availableAbove)
        let height = min(desiredHeight, below ? availableBelow : availableAbove)
        guard width >= 200, height >= AutofillSuggestionLayout.minimumHeight else { return }
        let frame = NSRect(x: max(page.minX + 8, min(field.minX, page.maxX - width - 8)),
                           y: below ? field.minY - height - 4 : field.maxY + 4, width: width, height: height)
        let panel = AutofillSuggestionPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityLabel(String(localized: "Autofill suggestions"))
        let content = NSHostingView(rootView: AutofillSuggestionList(
            kind: request.kind, origin: SavedPassword.origin(for: request.frameURL) ?? "",
            suggestions: records, selection: selection,
            choose: { [weak self] id in self?.choose?(id) },
            manage: { [weak self] in
                guard let self else { return }
                self.dismiss()
                self.openSettings?()
            }
        )
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipShape(.rect(cornerRadius: 10)))
        content.sizingOptions = []
        content.safeAreaRegions = []
        content.frame = NSRect(origin: .zero, size: frame.size)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        panel.contentMinSize = frame.size
        panel.contentMaxSize = frame.size
        panel.setFrame(frame, display: false)
        self.panel = panel
        suggestions = records
        choose = { [weak self, weak view] id in
            guard let self, let view, records.contains(where: { $0.id == id }) else { return }
            fill(id, request: request, in: view)
        }
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        AutofillDiagnostics.note(.dropdownShown, kind: request.kind, count: records.count)
        observe(view, window: window)
        let id = presentationID
        geometryWatch = Task { [weak view] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                    guard let view, id == presentationID, panel.isVisible else { return }
                    try await validate(request, in: view, requiresFocus: true)
                } catch {
                    if id == presentationID {
                        dismiss()
                    }
                    return
                }
            }
        }
    }

    private func observe(_ view: WKWebView, window: NSWindow) {
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.willMoveNotification, NSWindow.didResizeNotification, ] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
        navigation = view.observe(\.url) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        loading = view.observe(\.isLoading) { [weak self] view, _ in
            MainActor.assumeIsolated { if view.isLoading { self?.dismiss() } }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let panel else { return event }
        if event.window === panel {
            return event
        }
        if event.type == .leftMouseDown, let view = webView,
           event.window === view.window, let request = requests.object(forKey: view),
           request.rect.contains(view.convert(event.locationInWindow, from: nil)) {
            return event
        }
        guard event.type == .keyDown, let view = webView, Self.isFocused(view) else {
            dismiss(); return event
        }
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
            dismiss(); return event
        }
        switch event.keyCode {
        case 125, 126:
            guard !suggestions.isEmpty else { return event }
            let index = selection.keyboardID.flatMap { id in suggestions.firstIndex { $0.id == id } }
            let next = index.map { ($0 + (event.keyCode == 125 ? 1 : -1) + suggestions.count) % suggestions.count }
                ?? (event.keyCode == 125 ? 0 : suggestions.count - 1)
            selection.keyboardID = suggestions[next].id
            return nil
        case 36, 76:
            guard let id = selection.keyboardID else { dismiss(); return event }
            choose?(id)
            return nil
        case 53:
            dismiss(); return nil
        default:
            dismiss(); return event
        }
    }

    private func validate(_ request: Request, in view: WKWebView, requiresFocus: Bool = false) async throws {
        guard AutofillSaveCoordinator.shared.isEnabled(request.kind, profileID: request.profileID),
              requests.object(forKey: view) === request, view.url == request.topURL,
              view.hasOnlySecureContent, view.window != nil, !view.isHiddenOrHasHiddenAncestor else {
            throw ContactAutofillError.changedPage
        }
        let valid = try await view.callAsyncJavaScript(
            """
            const model = globalThis.__linenAutofillForms;
            const active = globalThis.__linenAutofillSuggestions?.active();
            if (model?.documentID !== documentID || !active || model.id(active) !== fieldID || model.group(active)?.id !== formID) return null;
            if (requiresFocus && !document.hasFocus()) return null;
            return globalThis[bridge]?.bounds(token, url);
            """,
            arguments: ["bridge": request.bridge, "token": request.token, "url": request.frameURL.absoluteString,
                        "requiresFocus": requiresFocus, "documentID": request.documentID,
                        "formID": request.formID, "fieldID": request.fieldID, ],
            in: request.frame, contentWorld: request.world
        )
        let rect = try await resolveFieldRect(valid, request: request, in: view)
        guard
              abs(rect.minX - request.rect.minX) < 2, abs(rect.minY - request.rect.minY) < 2,
              abs(rect.width - request.rect.width) < 2, abs(rect.height - request.rect.height) < 2,
              requests.object(forKey: view) === request,
              AutofillSaveCoordinator.shared.isEnabled(request.kind, profileID: request.profileID),
              view.url == request.topURL, view.hasOnlySecureContent,
              view.window != nil, !view.isHiddenOrHasHiddenAncestor else { throw ContactAutofillError.changedPage }
    }

    private func fill(_ id: UUID, request: Request, in view: WKWebView) {
        guard !isFilling else { return }
        isFilling = true
        dismiss()
        Task {
            defer {
                isFilling = false
                if requests.object(forKey: view) === request {
                    requests.removeObject(forKey: view)
                }
            }
            do {
                try await validate(request, in: view)
                let fields: [String: Any]
                switch request.kind {
                case .password:
                    let vault = AutofillVaults.passwords(for: request.profileID)
                    let documentID = try await topDocumentID(in: view, world: request.world)
                    guard let origin = SavedPassword.origin(for: request.frameURL) else { throw ContactAutofillError.changedPage }
                    let authentication = try await passwordAuthentication.session(
                        for: view, profileID: request.profileID, documentID: documentID, origin: origin,
                        create: { await vault.makeAuthenticationSession() }
                    )
                    let records: [SavedPassword]
                    do {
                        records = try await vault.records(using: authentication)
                    } catch {
                        passwordAuthentication.clear(in: view)
                        throw error
                    }
                    guard let login = records.first(where: { $0.id == id }),
                          login.origin == SavedPassword.origin(for: request.frameURL) else { throw ContactAutofillError.noField }
                    passwordAuthentication.markAuthenticated(authentication, in: view)
                    fields = ["username": login.username, "password": login.password]
                case .card:
                    guard let card = try await AutofillVaults.cards(for: request.profileID).cards().first(where: { $0.id == id }),
                          !card.isExpired() else { throw PaymentCardError.noField }
                    fields = ["number": card.number, "cardholder": card.cardholder, "securityCode": card.securityCode ?? "", "month": card.month ?? 0, "year": card.year ?? 0]
                case .contact:
                    guard let contact = try await AutofillVaults.contacts(for: request.profileID).records().first(where: { $0.id == id }) else { throw ContactAutofillError.noField }
                    fields = contact.fields
                }
                try await validate(request, in: view)
                let count = try await view.callAsyncJavaScript(
                    "if (globalThis.__linenAutofillForms?.documentID !== documentID) return 0; return globalThis[bridge]?.fill(token, url, fields) || 0;",
                    arguments: ["bridge": request.bridge, "token": request.token, "url": request.frameURL.absoluteString,
                                "fields": fields, "documentID": request.documentID, ],
                    in: request.frame, contentWorld: request.world
                )
                guard (count as? Int ?? 0) > 0 else { throw ContactAutofillError.noField }
                if request.kind == .password, let username = fields["username"] as? String,
                   let origin = SavedPassword.origin(for: request.frameURL) {
                    AutofillSaveCoordinator.shared.rememberFilledUsername(username, origin: origin,
                                                                         documentID: request.documentID, in: view)
                }
            } catch {
                let canceled: Bool
                switch error {
                case AutofillVaultError.keychain(let status), PaymentCardError.keychain(let status):
                    canceled = status == errSecUserCanceled || status == errSecAuthFailed
                default:
                    canceled = false
                }
                guard !canceled, requests.object(forKey: view) === request,
                      AutofillSaveCoordinator.shared.isEnabled(request.kind, profileID: request.profileID),
                      view.url == request.topURL, let window = view.window, !view.isHiddenOrHasHiddenAncestor else { return }
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn’t Fill Saved Details")
                alert.informativeText = String(localized: "Select the field again to try again.")
                await alert.beginSheetModal(for: window)
            }
        }
    }

    private func topDocumentID(in view: WKWebView, world: WKContentWorld) async throws -> String {
        let value = try await view.callAsyncJavaScript(
            "return globalThis.__linenAutofillForms?.documentID;", arguments: [:], in: nil, contentWorld: world
        )
        guard let documentID = value as? String, UUID(uuidString: documentID) != nil else {
            throw ContactAutofillError.changedPage
        }
        return documentID
    }
}

final class PasswordFillAuthenticationCache {
    private final class Entry: NSObject {
        let profileID: UUID
        let documentID: String
        let origin: String
        let session: AutofillAuthenticationSession
        var expiresAt: Date?

        init(profileID: UUID, documentID: String, origin: String, session: AutofillAuthenticationSession) {
            self.profileID = profileID
            self.documentID = documentID
            self.origin = origin
            self.session = session
        }
    }

    private let entries = NSMapTable<WKWebView, Entry>.weakToStrongObjects()
    private let duration: TimeInterval = 5 * 60
    private var generation = 0

    func session(for view: WKWebView, profileID: UUID, documentID: String, origin: String,
                 now: Date = .now, create: () async -> AutofillAuthenticationSession) async throws -> AutofillAuthenticationSession {
        if let entry = entries.object(forKey: view), entry.profileID == profileID,
           entry.documentID == documentID, entry.origin == origin,
           let expiresAt = entry.expiresAt, now < expiresAt {
            return entry.session
        }
        clear(in: view)
        let generation = generation
        let session = await create()
        guard self.generation == generation else {
            session.invalidate()
            throw ContactAutofillError.changedPage
        }
        entries.setObject(Entry(profileID: profileID, documentID: documentID, origin: origin, session: session), forKey: view)
        return session
    }

    func markAuthenticated(_ session: AutofillAuthenticationSession, in view: WKWebView, now: Date = .now) {
        guard let entry = entries.object(forKey: view), entry.session === session else { return }
        if entry.expiresAt == nil {
            entry.expiresAt = now.addingTimeInterval(duration)
        }
    }

    func clear(in view: WKWebView) {
        generation += 1
        entries.object(forKey: view)?.session.invalidate()
        entries.removeObject(forKey: view)
    }

    func clear() {
        generation += 1
        for entry in entries.objectEnumerator()?.allObjects.compactMap({ $0 as? Entry }) ?? [] {
            entry.session.invalidate()
        }
        entries.removeAllObjects()
    }
}

private final class AutofillSuggestionPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }
    override var canBecomeMain: Bool {
        false
    }
}
