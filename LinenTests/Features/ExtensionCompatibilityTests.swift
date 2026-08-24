// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct ExtensionCompatibilityTests {
    private func makePackage(manifest: String, scripts: [String: String] = [:]) throws -> URL {
        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("compat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: package.appendingPathComponent("manifest.json"))
        for (name, source) in scripts {
            try Data(source.utf8).write(to: package.appendingPathComponent(name))
        }
        return package
    }

    @Test func aPermissionWebKitKeepsIsNotReported() throws {
        let package = try makePackage(
            manifest: #"{"permissions":["storage","tabs"]}"#
        )
        defer { try? FileManager.default.removeItem(at: package) }

        let report = ExtensionCompatibility.report(
            forPackageAt: package,
            accepting: ["storage", "tabs"]
        )
        #expect(report.isEmpty)
    }

    @Test func aPermissionWebKitDropsIsReported() throws {
        let package = try makePackage(
            manifest: #"{"permissions":["storage","privacy","sidePanel"]}"#
        )
        defer { try? FileManager.default.removeItem(at: package) }

        let report = ExtensionCompatibility.report(
            forPackageAt: package,
            accepting: ["storage"]
        )
        #expect(report.namespaces == ["privacy", "sidePanel"])
    }

    @Test func aPermissionWebKitLearnsLaterStopsBeingReported() throws {
        let package = try makePackage(
            manifest: #"{"permissions":["storage","sidePanel"]}"#
        )
        defer { try? FileManager.default.removeItem(at: package) }

        let today = ExtensionCompatibility.report(
            forPackageAt: package,
            accepting: ["storage"]
        )
        #expect(today.namespaces == ["sidePanel"])

        let laterOS = ExtensionCompatibility.report(
            forPackageAt: package,
            accepting: ["storage", "sidePanel"]
        )
        #expect(laterOS.isEmpty)
    }

    @Test func aMissingEventOnAPresentNamespaceIsReported() {
        let source = "chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});"
        #expect(ExtensionCompatibility.report(scanning: source).members
            == ["webNavigation.onHistoryStateUpdated"])
    }

    @Test func anEventWebKitHasIsNotReported() {
        let source = """
            chrome.webNavigation.onCompleted.addListener(() => {});
            chrome.tabs.onUpdated.addListener(() => {});
            """
        #expect(ExtensionCompatibility.report(scanning: source).isEmpty)
    }

    @Test func aBundlerPathIsNotMistakenForAnAPI() {
        let source = "import x from './vendor/webextension-polyfill/browser.esm.js';"
        #expect(ExtensionCompatibility.report(scanning: source).isEmpty)
    }

    @Test func onlyTheBackgroundEntryPointsAreScannedForEvents() throws {
        let package = try makePackage(
            manifest: #"{"background":{"service_worker":"bg.js"}}"#,
            scripts: [
                "bg.js": "chrome.runtime.onSuspend.addListener(() => {});",
                "content.js": "chrome.tabs.onZoomChange.addListener(() => {});",
            ]
        )
        defer { try? FileManager.default.removeItem(at: package) }

        let report = ExtensionCompatibility.report(forPackageAt: package, accepting: [])
        #expect(report.members == ["runtime.onSuspend"])
    }

    @Test func theEventListStopsAssertingOnAnUnmeasuredSystem() {
        let measured = ExtensionCompatibility.membersMeasuredThroughMacOS
        #expect(ExtensionCompatibility.membersAreKnown(
            on: OperatingSystemVersion(majorVersion: measured, minorVersion: 9, patchVersion: 0)
        ))
        #expect(!ExtensionCompatibility.membersAreKnown(
            on: OperatingSystemVersion(majorVersion: measured + 1, minorVersion: 0, patchVersion: 0)
        ))
    }

    @Test func eventsOnOneNamespaceShareALine() {
        let report = ExtensionCompatibility.Report(
            namespaces: ["privacy"],
            members: [
                "runtime.onSuspend",
                "runtime.onUpdateAvailable",
                "webNavigation.onHistoryStateUpdated",
            ]
        )
        #expect(report.summaries == [
            "privacy",
            "runtime: onSuspend, onUpdateAvailable",
            "webNavigation: onHistoryStateUpdated",
        ])
    }

    @Test func theInstallSheetSaysWhatIsMissing() {
        let body = ExtensionConsent.body(
            hosts: ["example.com"],
            abilities: [],
            unsupported: ExtensionCompatibility.Report(
                namespaces: ["privacy"],
                members: ["webNavigation.onHistoryStateUpdated"]
            )
        )
        #expect(body.contains("privacy"))
        #expect(body.contains("webNavigation: onHistoryStateUpdated"))
    }

    @Test func aCleanExtensionAddsNothingToTheSheet() {
        let body = ExtensionConsent.body(hosts: ["example.com"], abilities: [])
        #expect(!body.contains("may not work"))
    }
}
