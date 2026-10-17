// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum StartPageSection: String, CaseIterable, Identifiable {
    case suggestions
    case recentTasks
    case frequentSites
    case history
    case downloads

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .suggestions:
            "Suggestions"
        case .recentTasks:
            "Recent Tasks"
        case .frequentSites:
            "Frequently Visited"
        case .history:
            "History"
        case .downloads:
            "Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .suggestions:
            "sparkles"
        case .recentTasks:
            "clock.arrow.circlepath"
        case .frequentSites:
            "chart.bar"
        case .history:
            "clock"
        case .downloads:
            "arrow.down"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .suggestions:
            "Things to try"
        case .recentTasks:
            "Repeat a recent task"
        case .frequentSites:
            "Websites you visit most"
        case .history:
            "Recently visited pages"
        case .downloads:
            "Recent files"
        }
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable {
    case release
    case preview

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .release:
            "Release"
        case .preview:
            "Preview"
        }
    }

    var caption: LocalizedStringResource {
        switch self {
        case .release:
            "Linen updates when a version is ready for everyone."
        case .preview:
            "Linen updates to preview builds, ahead of the release."
        }
    }
}

enum TabArchiveDelay: String, CaseIterable, Identifiable {
    case twelveHours
    case day
    case week
    case never

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .twelveHours:
            LocalizedStringResource("settings.archiveTabs.twelveHours", defaultValue: "12 hours")
        case .day:
            LocalizedStringResource("settings.archiveTabs.day", defaultValue: "A day")
        case .week:
            LocalizedStringResource("settings.archiveTabs.week", defaultValue: "A week")
        case .never:
            LocalizedStringResource("settings.archiveTabs.never", defaultValue: "Never")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .twelveHours:
            12 * 3600
        case .day:
            86_400
        case .week:
            7 * 86_400
        case .never:
            nil
        }
    }
}

enum TabSleep: String, CaseIterable, Identifiable {
    case never
    case whenMemoryIsLow
    case afterInactivity

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .never:
            LocalizedStringResource("settings.tabSleep.never", defaultValue: "Never")
        case .whenMemoryIsLow:
            LocalizedStringResource("settings.tabSleep.whenMemoryIsLow", defaultValue: "When memory is low")
        case .afterInactivity:
            LocalizedStringResource("settings.tabSleep.afterInactivity", defaultValue: "After an hour of inactivity")
        }
    }

    var idleInterval: TimeInterval? {
        self == .afterInactivity ? 3600 : nil
    }
}

enum HistoryRetention: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year
    case forever

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .day:
            "A day"
        case .week:
            "A week"
        case .month:
            "A month"
        case .year:
            "A year"
        case .forever:
            "Forever"
        }
    }

    var maximumAge: TimeInterval? {
        switch self {
        case .day:
            86_400
        case .week:
            7 * 86_400
        case .month:
            30 * 86_400
        case .year:
            365 * 86_400
        case .forever:
            nil
        }
    }
}
