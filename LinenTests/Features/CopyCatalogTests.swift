// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// Guards over the string catalog and the settings search index, so the copy
/// conventions in CONTRIBUTING.md are enforced rather than remembered: curly
/// apostrophes and em dashes in what the user reads, US English, no
/// "Are you sure" preambles, and one capitalization per label.
/// The repository checkout, found by walking up from this file until the
/// project file appears, so moving the test does not break the lookup.
private enum Repo {
    nonisolated static let root: URL = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let project = directory.appending(path: "Linen.xcodeproj").path
            if FileManager.default.fileExists(atPath: project) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return directory
    }()
}

/// The catalog is compiled away inside the app bundle, so the tests read the
/// source.
struct CopyCatalogTests {

    /// Every string the user can read: each key stands in for its own English
    /// text, and an entry with plural or device variations carries the real
    /// text in its values instead.
    private static let displayStrings: [String] = {
        let url = Repo.root.appending(path: "Linen/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { return [] }

        var collected: [String] = []
        for (key, value) in strings {
            guard let entry = value as? [String: Any] else { continue }
            let values = leafValues(of: entry)
            collected.append(contentsOf: values.isEmpty ? [key] : values)
        }
        return collected
    }()

    private static func leafValues(of node: [String: Any]) -> [String] {
        var found: [String] = []
        for (key, value) in node {
            if key == "value", let text = value as? String {
                found.append(text)
            } else if let nested = value as? [String: Any] {
                found.append(contentsOf: leafValues(of: nested))
            }
        }
        return found
    }

    @Test func theCatalogWasFoundAndIsNotEmpty() {
        #expect(Self.displayStrings.count > 500)
    }

    @Test func displayStringsUseTheCurlyApostrophe() {
        let offenders = Self.displayStrings.filter { string in
            string.contains(/[A-Za-z]'/) || string.contains(/'[A-Za-z]/)
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func displayStringsUseAnEmDashNotASpacedHyphen() {
        let offenders = Self.displayStrings.filter { $0.contains(" - ") }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func displayStringsUseUSEnglish() {
        let british: [String] = [
            "colour", "organisation", "behaviour", "favourite", "authorise",
            "customise", "minimise", "maximise", "dialogue", "cancelled",
            "grey ", "centred", "licence",
        ]
        let offenders = Self.displayStrings.filter { string in
            let lowered = string.lowercased()
            return british.contains { lowered.contains($0) }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func confirmationsAskDirectlyWithoutAPreamble() {
        let offenders = Self.displayStrings.filter { $0.contains("Are you sure") }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func webpageIsOneWord() {
        let offenders = Self.displayStrings.filter { $0.lowercased().contains("web page") }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// The page a tab returns to is a bookmark. "Pin" survives in two other
    /// senses only: the sidebar toggle that fixes the sidebar open, and the
    /// chip that puts an extension back on the toolbar.
    @Test func theTabsAnchorPageIsCalledABookmark() {
        let offenders = Self.displayStrings
            .filter { $0.contains(/\b[Uu]?n?[Pp]in(ned|s)?\b/) }
            .filter { $0 != "Pin Sidebar" && $0 != "Pin" }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// The placeholder teaches the one character that addresses the assistant,
    /// so it has to keep saying it.
    @Test func theAskFieldNamesItsTrigger() {
        #expect(AskSurface.Placement.startPage.placeholder.contains("@"))
        #expect(AskSurface.Placement.toolbar.placeholder.contains("@"))
    }

    /// Case pairs that are two different surfaces sharing words, not one
    /// label forking: a menu item beside a settings row title, or a label
    /// beside its mid-sentence `sentenceName` variant.
    private static let intentionalCasePairs: Set<String> = [
        "all time", "assistant access", "background scripts", "browsing history",
        "cached files", "cookies and site data", "local storage", "money transfers",
        "new tab", "on this mac", "posting and sending", "reset settings",
        "show sidebar", "software update", "start page",
    ]

    /// Two keys that differ only in case are one label about to fork - the
    /// tooltip spelled one way and the menu item another. Single words are
    /// exempt: their case is decided by where they sit in a sentence, and the
    /// codebase deliberately keeps `listName`/`sentenceName` variants.
    @Test func noLabelShipsInTwoCapitalizations() {
        var byFoldedText: [String: [String]] = [:]
        for string in Self.displayStrings
        where string.contains(" ") && !Self.intentionalCasePairs.contains(string.lowercased()) {
            byFoldedText[string.lowercased(), default: []].append(string)
        }
        let forks = byFoldedText.values.filter { Set($0).count > 1 }
        #expect(forks.isEmpty, "\(forks)")
    }
}

/// The settings search index re-states each row's caption, and the contract
/// on `SettingsEntry.detail` is that they stay the same sentence. Entries
/// that intentionally diverge - a page caption that interpolates the model's
/// name, a row with no caption at all - are listed here, so a new divergence
/// is a decision instead of an accident.
struct SettingsIndexParityTests {
    /// Anchors whose index text is allowed to differ from the page, with the
    /// reason recorded where the next reader will look. Most rows carry no
    /// static caption at all - the control is its own label, or the caption
    /// is computed from live state - so the index text is their only fixed
    /// description.
    private static let intentionalDivergence: Set<String> = [
        "general.agentOnly",        // the page caption names the chosen model
        "search.engine",            // the page caption names the chosen model
        "assistant.tools",          // the page caption names the chosen model
        "voice.readAloud",          // the page caption adds a System Settings link
        "general.importSafari",     // import rows describe themselves in the import section
        "general.importChrome",
        "about.updates",            // the About page renders version state, not a caption
        "about.acknowledgements",
        "profiles.launch",          // the picker row's caption names the current profile
        "extensions.installed",     // the extensions section renders its own header
        // No static caption on the page: the row is its own label.
        "general.startup", "general.newTab", "general.defaultBrowser",
        "search.custom", "appearance.theme", "profiles.list", "profiles.current",
        "provider.model", "provider.connected",
        "appearance.sidebar", "appearance.sidebarStyle", "advanced.reset",
        "privacy.history", "privacy.assistant",
        "websites.javascript", "websites.trackers", "websites.list",
        "websites.permissions", "downloads.folder", "downloads.ask",
        "downloads.list",
        // The page caption is computed from live state.
        "search.suggestions", "privacy.storage", "websites.autoplay",
        "provider.thinking",
    ]

    private nonisolated static func source(_ relativePath: String) -> String {
        (try? String(contentsOf: Repo.root.appending(path: relativePath), encoding: .utf8)) ?? ""
    }

    /// Every settings source that renders a row the index points at.
    private static let pageSourcePaths: [String] = [
        "Linen/Settings/Pages/GeneralSettings.swift",
        "Linen/Settings/Pages/AppearanceSettings.swift",
        "Linen/Settings/Pages/PrivacySettings.swift",
        "Linen/Settings/Pages/WebsiteSettings.swift",
        "Linen/Settings/Pages/DownloadsSettings.swift",
        "Linen/Settings/Pages/AdvancedSettings.swift",
        "Linen/Settings/SettingsView.swift",
        "Linen/Settings/Pages/ProfileSettings.swift",
        "Linen/Settings/Pages/IntelligenceSettings.swift",
        "Linen/Settings/Pages/SearchSettings.swift",
        "Linen/Settings/Pages/AssistantGrantsSection.swift",
        "Linen/Extensions/ExtensionsSettingsSection.swift",
        "Linen/Updates/UpdateBanner.swift",
    ]

    private static let pageSources: String = pageSourcePaths.map(source).joined(separator: "\n")

    @Test func everyPageSourceWasFound() {
        let missing = Self.pageSourcePaths.filter { Self.source($0).isEmpty }
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test func everyIndexDetailAppearsOnItsPage() {
        var drifted: [String] = []
        for entry in SettingsIndex.all where !Self.intentionalDivergence.contains(entry.id) {
            let detail = String(localized: entry.detail)
            if !Self.pageSources.contains(detail) {
                drifted.append("\(entry.id): \(detail)")
            }
        }
        #expect(drifted.isEmpty, "\(drifted)")
    }

    @Test func theDivergenceListStaysCurrent() {
        let known = Set(SettingsIndex.all.map(\.id))
        let stale = Self.intentionalDivergence.subtracting(known)
        #expect(stale.isEmpty, "\(stale)")
    }
}
