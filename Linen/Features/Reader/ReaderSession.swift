// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

@MainActor
@Observable
final class ReaderSession {
    enum Availability: Equatable {
        case unknown
        case available
        case unavailable
    }

    private(set) var availability = Availability.unknown
    private(set) var isActive = false
    private(set) var isOpening = false
    private(set) var article: ReaderArticle?
    private(set) var generation = 0

    @ObservationIgnored var driver: ReaderDriver?
    @ObservationIgnored weak var presentedView: WKWebView?
    @ObservationIgnored var onDeactivate: (() -> Void)?
    @ObservationIgnored var retryDelay: Duration = .milliseconds(1500)
    @ObservationIgnored private var probing: Int?

    var isAvailable: Bool {
        isActive || availability == .available
    }

    func pageChanged() {
        generation &+= 1
        availability = .unknown
        isOpening = false
        deactivate()
        article = nil
    }

    func probe() async {
        guard let driver, availability == .unknown, probing != generation else { return }
        let generation = generation
        probing = generation
        defer {
            if probing == generation {
                probing = nil
            }
        }
        var readerable = await driver.probe()
        if !readerable {
            try? await Task.sleep(for: retryDelay)
            guard self.generation == generation, availability == .unknown else { return }
            readerable = await driver.probe()
        }
        if !readerable {
            guard self.generation == generation, availability == .unknown else { return }
            readerable = await driver.watch()
        }
        guard self.generation == generation, availability == .unknown else { return }
        availability = readerable ? .available : .unavailable
    }

    func extract() async -> ReaderArticle? {
        guard let driver else { return nil }
        let generation = generation
        let extracted = await driver.extract()
        guard self.generation == generation else { return nil }
        if extracted != nil {
            availability = .available
        }
        return extracted
    }

    @discardableResult
    func open() async -> Bool {
        guard !isActive, !isOpening else { return isActive }
        isOpening = true
        let generation = generation
        let extracted = await extract()
        guard self.generation == generation else { return false }
        isOpening = false
        guard let extracted else {
            availability = .unavailable
            return false
        }
        article = extracted
        isActive = true
        return true
    }

    func close() {
        deactivate()
    }

    func toggle() {
        if isActive {
            close()
        } else {
            Task { await open() }
        }
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        let handler = onDeactivate
        onDeactivate = nil
        handler?()
    }
}
