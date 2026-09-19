// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

final class AutofillSubmissionTracker {
    struct PageState {
        let documentID: String
        let url: URL
        let ready: Bool
        let passwords: Int
        let challenges: Int
        let cards: Int
        let addresses: Int

        init?(_ value: Any?) {
            guard let value = value as? [String: Any],
                  let documentID = value["documentID"] as? String, UUID(uuidString: documentID) != nil,
                  let rawURL = value["url"] as? String, let url = URL(string: rawURL),
                  SavedPassword.origin(for: url) != nil,
                  let ready = value["ready"] as? Bool,
                  let passwords = value["passwords"] as? Int, let challenges = value["challenges"] as? Int,
                  let cards = value["cards"] as? Int, let addresses = value["addresses"] as? Int,
                  [passwords,challenges,cards,addresses].allSatisfy({ (0...400).contains($0) }) else { return nil }
            self.documentID = documentID; self.url = url; self.ready = ready
            self.passwords = passwords; self.challenges = challenges
            self.cards = cards; self.addresses = addresses
        }

        func stillContains(_ kind: AutofillSaveKind) -> Bool {
            switch kind {
            case .password: passwords > 0 || challenges > 0
            case .card: cards > 0
            case .contact: addresses > 0
            }
        }
    }

    private struct Attempt {
        let id: UUID
        let documentID: String
        let formID: String
        let origin: String
        let candidates: [AutofillSaveCandidate]
        let frame: WKFrameInfo
        let created = Date.now
        var completionDocumentID: String?
        var completionObservedAt: Date?
    }

    private weak var session: AutofillSaveSession?
    private var attempts: [UUID: Attempt] = [:]
    private var formDepartures: [String: Date] = [:]
    private var polling: Task<Void, Never>?
    private var generation = 0

    func attach(to session: AutofillSaveSession) { self.session = session }

    func clear() {
        generation += 1
        attempts = [:]
        formDepartures = [:]
        polling?.cancel(); polling = nil
    }

    func navigationRequested(_ action: WKNavigationAction) {
        switch action.navigationType {
        case .linkActivated, .backForward, .reload:
            if action.targetFrame?.isMainFrame != false {
                clear()
                session?.username = nil
            }
        case .formSubmitted, .formResubmitted:
            if let url = action.sourceFrame.request.url, let origin = SavedPassword.origin(for: url) {
                formDepartures = formDepartures.filter { Date.now.timeIntervalSince($0.value) < 5 }
                formDepartures[origin] = .now
            }
        default: break
        }
    }

    func stage(id: UUID, documentID: String, formID: String, origin: String,
               candidates: [AutofillSaveCandidate], frame: WKFrameInfo, source: String) {
        guard !candidates.isEmpty,
              ["submit", "interaction", "automatic", "pagehide"].contains(source) else { return }
        if source == "pagehide" {
            guard let date = formDepartures[origin], Date.now.timeIntervalSince(date) < 5 else { return }
        }
        attempts = attempts.filter { $0.value.documentID != documentID || $0.value.formID != formID }
        if attempts.count >= 12, let oldest = attempts.values.min(by: { $0.created < $1.created }) {
            attempts[oldest.id] = nil
        }
        let submittedAddresses = source == "submit" ? candidates.filter { $0.kind == .contact } : []
        if !submittedAddresses.isEmpty { session?.receive(submittedAddresses, origin: origin) }
        let pending = source == "submit" ? candidates.filter { $0.kind != .contact } : candidates
        guard !pending.isEmpty else { return }
        attempts[id] = Attempt(id: id, documentID: documentID, formID: formID,
                               origin: origin, candidates: pending, frame: frame)
        AutofillDiagnostics.note(.submissionPending, kind: candidates[0].kind)
        startPolling()
    }

    func discard(id: UUID, documentID: String, formID: String) {
        guard let attempt = attempts[id], attempt.documentID == documentID, attempt.formID == formID else { return }
        attempts[id] = nil
    }

    func complete(id: UUID, documentID: String, formID: String) {
        guard let attempt = attempts[id], attempt.documentID == documentID, attempt.formID == formID,
              Date.now.timeIntervalSince(attempt.created) < 120 else { return }
        finish(attempt)
    }

    private func finish(_ attempt: Attempt) {
        attempts[attempt.id] = nil
        guard let session else { return }
        AutofillDiagnostics.note(.submissionCompleted, kind: attempt.candidates[0].kind)
        session.receive(attempt.candidates, origin: attempt.origin)
    }

    private func startPolling() {
        guard polling == nil else { return }
        let generation = generation
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, generation == self.generation else { return }
                await inspectTransitions(generation: generation)
                guard generation == self.generation else { return }
                if attempts.isEmpty { polling = nil; return }
            }
        }
    }

    private func inspectTransitions(generation: Int) async {
        attempts = attempts.filter { Date.now.timeIntervalSince($0.value.created) < 120 }
        guard let view = session?.webView, !view.isLoading, view.window != nil,
              !view.isHiddenOrHasHiddenAncestor, view.hasOnlySecureContent,
              let topURL = view.url, SavedPassword.origin(for: topURL) != nil else { return }
        for attempt in Array(attempts.values) {
            let value = try? await view.callAsyncJavaScript(
                "return globalThis.__linenAutofillForms?.summary();", arguments: [:],
                in: attempt.frame.isMainFrame ? nil : attempt.frame, contentWorld: AutofillPage.world
            )
            guard generation == self.generation, attempts[attempt.id] != nil, view.url == topURL, !view.isLoading else { return }
            let state = PageState(value)
            if let state, state.documentID == attempt.documentID { continue }
            if attempt.frame.isMainFrame && state == nil { continue }
            guard let pages = await AutofillSaveCoordinator.shared.pageStates(in: view),
                  let main = pages.first,
                  pages.allSatisfy(\.ready),
                  !pages.contains(where: { $0.documentID == attempt.documentID }),
                  attempt.candidates.allSatisfy({ candidate in !pages.contains { $0.stillContains(candidate.kind) } }) else {
                attempts[attempt.id]?.completionDocumentID = nil
                attempts[attempt.id]?.completionObservedAt = nil
                continue
            }
            guard generation == self.generation, attempts[attempt.id] != nil,
                  view.url == topURL, !view.isLoading, view.hasOnlySecureContent else { return }
            let completionID = state?.documentID ?? main.documentID
            if let recorded = attempts[attempt.id], recorded.completionDocumentID == completionID,
               let first = recorded.completionObservedAt, Date.now.timeIntervalSince(first) >= 1 {
                finish(recorded)
            } else {
                attempts[attempt.id]?.completionDocumentID = completionID
                attempts[attempt.id]?.completionObservedAt = .now
            }
        }
    }
}
