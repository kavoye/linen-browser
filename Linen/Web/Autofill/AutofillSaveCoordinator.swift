// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CryptoKit
import Observation
import WebKit

@Observable
final class AutofillSaveSession: NSObject {
    nonisolated struct Offer: Identifiable, Sendable {
        let id = UUID()
        let candidate: AutofillSaveCandidate
        let origin: String
        let isUpdate: Bool
        let fingerprint: String
    }

    private(set) var offers: [Offer] = []
    private(set) var isBusy = false
    private(set) var error: String?
    var isPopoverPresented = false
    private(set) var profileID = Profile.privateID
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var dismissed: [AutofillSaveKind: Set<String>] = [:]
    @ObservationIgnored private let fingerprintKey = SymmetricKey(size: .bits256)
    @ObservationIgnored private var expiry: Task<Void, Never>?
    struct UsernameStep {
        let origin: String
        let value: String
        let documentID: String
        let attemptID: UUID
        let date = Date.now
        var completed = false
    }
    @ObservationIgnored var username: UsernameStep?
    @ObservationIgnored let submissions = AutofillSubmissionTracker()

    var current: Offer? { offers.first }

    func attach(to webView: WKWebView, profileID: UUID) {
        clear()
        self.webView = webView
        self.profileID = profileID
        submissions.attach(to: self)
        dismissed = [:]
    }

    func clear() {
        revision += 1
        offers = []
        isPopoverPresented = false
        username = nil
        submissions.clear()
        error = nil
        expiry?.cancel()
        expiry = nil
    }

    func refreshPolicy() {
        revision += 1
        submissions.clear()
        offers.removeAll { !AutofillSaveCoordinator.shared.isEnabled($0.candidate.kind, profileID: profileID) }
        if offers.isEmpty { isPopoverPresented = false }
        if !AutofillSaveCoordinator.shared.isEnabled(.password, profileID: profileID) { username = nil }
    }

    func resetDismissals(kind: AutofillSaveKind) { dismissed[kind] = nil }

    func resetDismissalsForNavigation() {
        dismissed = [:]
    }

    func receive(_ candidates: [AutofillSaveCandidate], origin: String) {
        let revision = revision
        Task { [weak self] in
            guard let self else { return }
            for candidate in candidates {
                guard revision == self.revision else { return }
                await offer(candidate, origin: origin)
            }
        }
    }

    func offer(_ candidate: AutofillSaveCandidate, origin: String) async {
        guard AutofillSaveCoordinator.shared.isEnabled(candidate.kind, profileID: profileID) else { return }
        let bytes = (try? JSONEncoder().encode([origin, candidate.kind.rawValue] + candidate.values)) ?? Data()
        let fingerprint = Data(HMAC<SHA256>.authenticationCode(for: bytes, using: fingerprintKey)).base64EncodedString()
        guard dismissed[candidate.kind]?.contains(fingerprint) != true, !offers.contains(where: { $0.fingerprint == fingerprint }) else { return }
        let revision = revision
        let profileID = profileID
        let decision = await Task.detached {
            (try? AutofillSaveIndex.decision(for: candidate, origin: origin, profileID: profileID)) ?? .new
        }.value
        guard revision == self.revision, self.webView != nil,
              AutofillSaveCoordinator.shared.isEnabled(candidate.kind, profileID: profileID),
              dismissed[candidate.kind]?.contains(fingerprint) != true, !offers.contains(where: { $0.fingerprint == fingerprint }),
              decision != .unchanged, decision != .blocked else { return }
        let previousOfferID = current?.id
        offers.removeAll { $0.candidate.kind == candidate.kind }
        offers.append(Offer(candidate: candidate, origin: origin, isUpdate: decision == .update, fingerprint: fingerprint))
        if current?.id != previousOfferID { isPopoverPresented = true }
        AutofillDiagnostics.note(.saveOffered, kind: candidate.kind)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func dismiss(_ offer: Offer, rememberingChoice: Bool = true) {
        if rememberingChoice {
            var fingerprints = dismissed[offer.candidate.kind] ?? []
            if fingerprints.count >= 100 { fingerprints.removeAll() }
            fingerprints.insert(offer.fingerprint)
            dismissed[offer.candidate.kind] = fingerprints
        }
        offers.removeAll { $0.id == offer.id }
        isPopoverPresented = !offers.isEmpty
        error = nil
    }

    func never(_ offer: Offer) async {
        guard !isBusy, current?.id == offer.id else { return }
        isBusy = true
        let profileID = profileID
        defer { isBusy = false }
        do {
            try await Task.detached {
                try AutofillSaveIndex.block(kind: offer.candidate.kind, origin: offer.origin, profileID: profileID)
            }.value
            if self.profileID == profileID && current?.id == offer.id { dismiss(offer) }
        } catch {
            if self.profileID == profileID && current?.id == offer.id { self.error = String(localized: "Couldn’t remember this choice. Try again.") }
        }
    }

    func save(_ offer: Offer, replacement: AutofillSaveCandidate? = nil) async {
        guard !isBusy, current?.id == offer.id,
              AutofillSaveCoordinator.shared.isEnabled(offer.candidate.kind, profileID: profileID),
              let webView, webView.window != nil else { return }
        let candidate = replacement ?? offer.candidate
        guard candidate.kind == offer.candidate.kind else { return }
        if case .password(let password) = candidate, password.origin != offer.origin { return }
        isBusy = true
        error = nil
        let profileID = profileID
        defer { isBusy = false }
        do {
            switch candidate {
            case .password(let login):
                _ = try await AutofillVaults.passwords(for: profileID).update { SavedPassword.merging(login, into: $0) }
            case .card(let card):
                _ = try await AutofillVaults.cards(for: profileID).importCards([card], preservingMissingSecurityCodes: replacement == nil)
            case .contact(let contact):
                _ = try await AutofillVaults.contacts(for: profileID).update { contacts in
                    guard !contacts.contains(where: { AutofillSaveCandidate.contact($0).values == candidate.values }) else { return contacts }
                    guard contacts.count < 100 else { throw AutofillVaultError.invalidData }
                    return contacts + [contact]
                }
            }
            if self.profileID == profileID && current?.id == offer.id { dismiss(offer, rememberingChoice: false) }
        } catch {
            if self.profileID == profileID && current?.id == offer.id { self.error = String(localized: "Couldn’t save these details. Try again.") }
        }
    }
}

final class AutofillSaveCoordinator: NSObject, WKScriptMessageHandler {
    static let shared = AutofillSaveCoordinator()
    private static let world = AutofillPage.world
    private let sessions = NSMapTable<WKWebView, AutofillSaveSession>.weakToWeakObjects()
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private let frames = NSMapTable<WKWebView, FrameList>.weakToStrongObjects()
    private var observers: [NSObjectProtocol] = []
    private var sessionIsActive = true
    private var screenIsLocked = false
    private(set) var profileID = Profile.originalID

    private final class FrameList: NSObject {
        var values: [String: WKFrameInfo] = [:]
        var mainDocumentID: String?
    }

    override private init() {
        super.init()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.sessionIsActive = false; self?.clear(); self?.refreshPolicy()
        } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.sessionIsActive = true; self?.refreshPolicy()
        } })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.screenIsLocked = true; self?.clear(); self?.refreshPolicy()
        } })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.screenIsLocked = false; self?.refreshPolicy()
        } })
    }

    func use(profileID: UUID) {
        clear()
        self.profileID = profileID
        refreshPolicy()
    }

    private func clear() {
        AutofillSuggestions.shared.reset()
        for session in sessions.objectEnumerator()?.allObjects as? [AutofillSaveSession] ?? [] { session.clear() }
    }

    func resetDismissals(kind: AutofillSaveKind, profileID: UUID) {
        for session in sessions.objectEnumerator()?.allObjects as? [AutofillSaveSession] ?? [] where session.profileID == profileID {
            session.resetDismissals(kind: kind)
        }
    }

    func rememberFilledUsername(_ value: String, origin: String, documentID: String, in webView: WKWebView) {
        guard let session = sessions.object(forKey: webView), !value.isEmpty, value.count <= 500,
              isEnabled(.password, profileID: session.profileID) else { return }
        var step = AutofillSaveSession.UsernameStep(origin: origin, value: value,
                                                    documentID: documentID, attemptID: UUID())
        step.completed = true
        session.username = step
    }

    func isEnabled(_ kind: AutofillSaveKind, profileID: UUID) -> Bool {
        guard sessionIsActive, !screenIsLocked, profileID == self.profileID, profileID != Profile.privateID else { return false }
        switch kind {
        case .password: return PasswordAutofill.shared.isEnabled
        case .card: return BrowserSettings.shared.fillsPaymentCards
        case .contact: return BrowserSettings.shared.fillsContacts
        }
    }

    func install(in webView: WKWebView, session: AutofillSaveSession) {
        session.attach(to: webView, profileID: profileID)
        sessions.setObject(session, forKey: webView)
        let controller = webView.configuration.userContentController
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        AutofillPage.install(in: controller)
        controller.addUserScript(WKUserScript(source: AutofillSaveScript.clientSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Self.world))
        controller.add(self, contentWorld: Self.world, name: "linenAutofillSave")
    }

    func refreshPolicy() {
        AutofillSuggestions.shared.reset()
        for webView in sessions.keyEnumerator().allObjects as? [WKWebView] ?? [] {
            sessions.object(forKey: webView)?.refreshPolicy()
            for frame in frames.object(forKey: webView)?.values.values.map({ $0 }) ?? [] { applyPolicy(in: webView, frame: frame) }
        }
    }

    private func applyPolicy(in webView: WKWebView, frame: WKFrameInfo) {
        guard let session = sessions.object(forKey: webView), session.webView === webView else { return }
        let origin = frame.securityOrigin
        let topURL = webView.url
        let secureFrame = origin.protocol == "https" && !origin.host.isEmpty
            && topURL.flatMap(SavedPassword.origin(for:)) != nil
        let policy = Dictionary(uniqueKeysWithValues: AutofillSaveKind.allCases.map {
            ($0.rawValue, secureFrame && isEnabled($0, profileID: session.profileID))
        })
        AutofillDiagnostics.note(policy["password"] == true ? .policyEnabled : .policyDisabled, kind: .password)
        Task {
            _ = try? await webView.callAsyncJavaScript("globalThis.__linenAutofillSave?.setPolicy(policy);", arguments: ["policy": policy], in: frame, contentWorld: Self.world)
        }
    }

    func pageStates(in webView: WKWebView) async -> [AutofillSubmissionTracker.PageState]? {
        guard let list = frames.object(forKey: webView), let mainID = list.mainDocumentID,
              let main = list.values[mainID] else { return nil }
        let entries = [(mainID, main)] + list.values.filter { $0.key != mainID }.map { ($0.key, $0.value) }
        var result: [AutofillSubmissionTracker.PageState] = []
        for (id, frame) in entries {
            let raw = try? await webView.callAsyncJavaScript(
                "return globalThis.__linenAutofillForms?.summary();", arguments: [:], in: frame, contentWorld: Self.world
            )
            guard frames.object(forKey: webView) === list, list.mainDocumentID == mainID else { return nil }
            guard let state = AutofillSubmissionTracker.PageState(raw), state.documentID == id,
                  frame.securityOrigin.protocol == state.url.scheme, frame.securityOrigin.host == state.url.host,
                  (frame.securityOrigin.port == 0 ? 443 : frame.securityOrigin.port) == (state.url.port ?? 443) else {
                if id == mainID { return nil }
                list.values[id] = nil
                continue
            }
            result.append(state)
        }
        return result
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, let session = sessions.object(forKey: webView), session.webView === webView, session.profileID == profileID,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "ready" {
            AutofillDiagnostics.note(.saveScriptReady, kind: .password)
            guard let documentID = body["documentID"] as? String, UUID(uuidString: documentID) != nil else { return }
            let list = frames.object(forKey: webView) ?? FrameList()
            if message.frameInfo.isMainFrame, list.mainDocumentID != documentID {
                list.mainDocumentID = documentID
                list.values = [:]
            }
            if list.values[documentID] == nil, list.values.count >= 100,
               let oldest = list.values.keys.first(where: { $0 != list.mainDocumentID }) {
                list.values[oldest] = nil
            }
            list.values[documentID] = message.frameInfo
            frames.setObject(list, forKey: webView)
            applyPolicy(in: webView, frame: message.frameInfo)
            return
        }
        guard webView.window != nil, !webView.isHiddenOrHasHiddenAncestor, webView.hasOnlySecureContent,
              let documentID = body["documentID"] as? String,
              frames.object(forKey: webView)?.values[documentID] != nil,
              let topURL = webView.url, SavedPassword.origin(for: topURL) != nil,
              let rawURL = body["url"] as? String, let url = URL(string: rawURL), let origin = SavedPassword.origin(for: url),
              message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == url.host,
              (message.frameInfo.securityOrigin.port == 0 ? 443 : message.frameInfo.securityOrigin.port) == (url.port ?? 443)
        else { return }
        if action == "diagnostic", let value = body["event"] as? String,
           let event = AutofillDiagnostics.Event(rawValue: value),
           [.editNoScope, .editDisabled, .editRecorded, .submitNoEdits, .submitInvalid, .submitCaptured].contains(event) {
            AutofillDiagnostics.note(event, kind: .password)
            return
        }
        guard let rawAttemptID = body["attemptID"] as? String, let attemptID = UUID(uuidString: rawAttemptID),
              let formID = body["formID"] as? String, let number = Int(formID), number > 0 else { return }
        if action == "discard" {
            if session.username?.attemptID == attemptID { session.username = nil }
            session.submissions.discard(id: attemptID, documentID: documentID, formID: formID)
            return
        }
        if action == "complete" {
            if session.username?.attemptID == attemptID { session.username?.completed = true }
            session.submissions.complete(id: attemptID, documentID: documentID, formID: formID)
            return
        }
        guard action == "stage", let source = body["source"] as? String,
              ["submit", "interaction", "automatic", "pagehide"].contains(source) else { return }
        if source != "pagehide", isEnabled(.password, profileID: session.profileID),
           let value = body["username"] as? String, !value.isEmpty, value.count <= 500 {
            session.username = AutofillSaveSession.UsernameStep(origin: origin, value: value,
                                                               documentID: documentID, attemptID: attemptID)
        }
        var candidates: [AutofillSaveCandidate] = []
        if isEnabled(.password, profileID: session.profileID), let login = body["password"] as? [String: String],
           let password = login["password"] {
            var username = login["username"] ?? ""
            if username.isEmpty, let remembered = session.username, remembered.origin == origin,
               (remembered.completed || remembered.documentID != documentID),
               Date.now.timeIntervalSince(remembered.date) < 300 { username = remembered.value }
            if let record = try? SavedPassword(website: origin, username: username, password: password) { candidates.append(.password(record)) }
        }
        if isEnabled(.card, profileID: session.profileID), let values = body["card"] as? [String: String],
           let number = values["cc-number"], number.count <= 32,
           let month = values["cc-exp-month"].flatMap(Int.init), let year = values["cc-exp-year"].flatMap(Int.init),
           let card = try? PaymentCard(number: number, cardholder: values["cc-name"] ?? "", month: month, year: year, securityCode: values["cc-csc"]), !card.isExpired() {
            candidates.append(.card(card))
        }
        if isEnabled(.contact, profileID: session.profileID), let values = body["contact"] as? [String: String],
           values.count <= 16, values.values.allSatisfy({ $0.count <= 500 }) {
            var contact = AutofillContact()
            contact.givenName = values["given-name"] ?? values["name"] ?? ""
            contact.familyName = values["family-name"] ?? ""
            contact.organization = values["organization"] ?? ""
            contact.email = values["email"] ?? ""
            contact.phone = values["tel"] ?? ""
            contact.street = values["street-address"] ?? [values["address-line1"], values["address-line2"], values["address-line3"]].compactMap { $0 }.joined(separator: "\n")
            contact.city = values["address-level2"] ?? ""
            contact.region = values["address-level1"] ?? ""
            contact.postalCode = values["postal-code"] ?? ""
            contact.countryCode = (values["country"] ?? "").uppercased()
            if contact.isValid, !contact.street.isEmpty, !contact.name.isEmpty || !contact.email.isEmpty { candidates.append(.contact(contact)) }
        }
        session.submissions.stage(id: attemptID, documentID: documentID, formID: formID, origin: origin,
                                  candidates: candidates, frame: message.frameInfo, source: source)
    }
}
