// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import Testing

@testable import Linen

@MainActor
struct ExternalAppPermissionTests {
    private let slack = ExternalAppPermission(scheme: "slack", bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")
    private let origin = "https://slack.com"

    private func store() -> SitePermissions {
        SitePermissions(storageURL: TestFiles.directory.appending(path: "ExternalAppTests-\(UUID().uuidString).json"))
    }

    @Test func aSavedChoiceSurvivesReloadAndCanBeRevoked() async {
        let file = TestFiles.directory.appending(path: "ExternalAppTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let permissions = SitePermissions(storageURL: file)
        permissions.allowExternalApp(slack, for: origin)
        await permissions.waitForPendingSave()
        let restored = SitePermissions(storageURL: file)
        #expect(restored.externalApps(for: origin) == [slack])
        #expect(SitePermissions.changedSiteCount(in: file) == 1)
        restored.removeExternalApp(slack, for: origin)
        await restored.waitForPendingSave()
        #expect(SitePermissions(storageURL: file).externalApps(for: origin).isEmpty)
    }

    @Test func choicesAreScopedToTheOriginSchemeAndInstalledApp() {
        let policy = TabExternalAppPolicy(store: store())
        policy.remember(slack, from: origin)
        #expect(policy.allows(slack, from: origin))
        for otherOrigin in ["http://slack.com", "https://slack.com:8443", "https://other.slack.com", ""] {
            #expect(!policy.allows(slack, from: otherOrigin))
        }
        #expect(!policy.allows(.init(scheme: "other", bundleIdentifier: slack.bundleIdentifier, name: "Slack"), from: origin))
        #expect(!policy.allows(.init(scheme: "slack", bundleIdentifier: "other.app", name: "Slack"), from: origin))
        #expect(!TabExternalAppPolicy(store: store()).allows(slack, from: origin))
    }

    @Test func privateChoicesStayInThePrivateTab() async {
        let permissions = store()
        let policy = TabExternalAppPolicy(store: permissions, isPrivate: true)
        policy.remember(slack, from: origin)
        #expect(policy.allows(slack, from: origin))
        #expect(permissions.externalApps(for: origin).isEmpty)
        #expect(!TabExternalAppPolicy(store: permissions, isPrivate: true).allows(slack, from: origin))
        await permissions.waitForPendingSave()
    }

    @Test func resettingAllWebsiteSettingsClearsAppChoices() {
        let permissions = store()
        permissions.allowExternalApp(slack, for: origin)
        permissions.removeEverything()
        #expect(permissions.externalApps(for: origin).isEmpty)
    }

    @Test func oldPermissionFilesStillLoad() throws {
        let file = TestFiles.directory.appending(path: "ExternalAppTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{\"assistantAccess\":{\"https://slack.com\":\"control\"}}".utf8).write(to: file)
        let permissions = SitePermissions(storageURL: file)
        #expect(permissions.assistantAccess(for: origin) == .control)
        #expect(permissions.externalApps(for: origin).isEmpty)
    }
}

@MainActor
@Suite(.serialized, .exclusiveExternalApp)
struct ExternalAppConfirmationTests {
    private func withOpening(
        _ body: (TabExternalAppPolicy, SitePermissions, URL) async throws -> Void
    ) async rethrows {
        let store = SitePermissions(storageURL: TestFiles.directory.appending(path: "ExternalAppTests-\(UUID().uuidString).json"))
        ExternalApp.resolverForTesting = { _ in
            .init(url: URL(filePath: "/Applications/Slack.app"), name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        }
        defer {
            ExternalApp.openerForTesting = nil
            ExternalApp.resolverForTesting = nil
            ExternalApp.presenterForTesting = nil
        }
        try await body(TabExternalAppPolicy(store: store), store, URL(string: "slack://open?code=secret")!)
    }

    @Test func rememberingAnAllowedRequestSkipsTheNextPrompt() async {
        await withOpening { policy, store, url in
            var prompts = 0
            var opened: [URL] = []
            ExternalApp.openerForTesting = { opened.append($0) }
            ExternalApp.presenterForTesting = { alert in
                prompts += 1
                #expect(alert.messageText == "Open Slack?")
                #expect(alert.informativeText.contains("slack.com"))
                #expect(!alert.informativeText.contains("secret"))
                #expect(alert.buttons.first?.title == "Open Slack")
                #expect(alert.suppressionButton?.state == .off)
                alert.suppressionButton?.state = .on
                return .alertFirstButtonReturn
            }
            for _ in 0..<2 {
                await ExternalApp.offerToOpen(url, from: "https://slack.com", policy: policy, in: nil)
            }
            #expect(prompts == 1)
            #expect(opened == [url, url])
            #expect(store.externalApps(for: "https://slack.com").count == 1)
        }
    }

    @Test func cancellingNeverOpensOrSavesEvenWithTheCheckboxSelected() async {
        await withOpening { policy, store, url in
            var opened = false
            ExternalApp.openerForTesting = { _ in opened = true }
            ExternalApp.presenterForTesting = { alert in
                alert.suppressionButton?.state = .on
                return .alertSecondButtonReturn
            }
            await ExternalApp.offerToOpen(url, from: "https://slack.com", policy: policy, in: nil)
            #expect(!opened)
            #expect(store.externalApps(for: "https://slack.com").isEmpty)
        }
    }

    @Test func openingOnceAsksAgainAndUnknownSourcesCannotBeRemembered() async {
        await withOpening { policy, store, url in
            var prompts = 0
            ExternalApp.openerForTesting = { _ in }
            ExternalApp.presenterForTesting = { alert in
                prompts += 1
                if prompts == 3 {
                    #expect(!alert.showsSuppressionButton)
                }
                return .alertFirstButtonReturn
            }
            for origin in ["https://slack.com", "https://slack.com", ""] {
                await ExternalApp.offerToOpen(url, from: origin, policy: policy, in: nil)
            }
            #expect(prompts == 3)
            #expect(store.externalAppRecords.isEmpty)
        }
    }

    @Test func aMissingApplicationDoesNotOpenOrOfferToRememberTheLink() async {
        await withOpening { policy, store, url in
            var opened = false
            var shown = false
            ExternalApp.resolverForTesting = { _ in nil }
            ExternalApp.openerForTesting = { _ in opened = true }
            ExternalApp.presenterForTesting = { alert in
                shown = true
                #expect(alert.messageText == "No app can open this link.")
                #expect(!alert.showsSuppressionButton)
                return .alertFirstButtonReturn
            }
            await ExternalApp.offerToOpen(url, from: "https://slack.com", policy: policy, in: nil)
            #expect(shown)
            #expect(!opened)
            #expect(store.externalAppRecords.isEmpty)
        }
    }
}
