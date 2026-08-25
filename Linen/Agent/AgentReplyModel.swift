// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

@MainActor
@Observable
final class AgentReplyModel {
    private(set) var text: String?
    private(set) var activity: String?
    private(set) var isStreaming = false
    private(set) var spaceID: UUID?
    private(set) var showsInChrome = true

    private var fadeTask: Task<Void, Never>?

    var isVisible: Bool {
        text != nil || activity != nil
    }

    func showsInChrome(inSpace spaceID: UUID?) -> Bool {
        guard let spaceID, spaceID == self.spaceID else { return true }
        return showsInChrome
    }

    func bind(toSpace spaceID: UUID, showsInChrome: Bool = true) {
        self.spaceID = spaceID
        self.showsInChrome = showsInChrome
    }

    func message(inSpace spaceID: UUID?) -> String? {
        guard showsInChrome, let spaceID, spaceID == self.spaceID else { return nil }
        if let activity, !activity.isEmpty {
            return activity
        }
        if let text, !text.isEmpty {
            return text
        }
        return nil
    }

    func beginStream() {
        fadeTask?.cancel()
        text = nil
        activity = nil
        isStreaming = true
    }

    func update(text: String) {
        self.text = text
    }

    func setActivity(_ activity: String?) {
        self.activity = activity
    }

    func endStream(retainFor seconds: Double = 12) {
        isStreaming = false
        activity = nil
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.text = nil
        }
    }

    func clear() {
        fadeTask?.cancel()
        text = nil
        activity = nil
        isStreaming = false
    }
}
