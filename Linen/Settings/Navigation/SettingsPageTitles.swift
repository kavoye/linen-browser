// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
enum SettingsPageTitles {
    static func title(of url: URL, coordinator: AppCoordinator) -> String? {
        guard let category = SystemPages.settingsCategory(of: url) else { return nil }
        let path = SystemPages.settingsPath(of: url)
        guard !path.isEmpty, let title = title(category, path: path, coordinator: coordinator) else {
            return String(localized: category.title)
        }
        return title
    }

    private static func title(_ category: SettingsCategory, path: [String], coordinator: AppCoordinator) -> String? {
        switch category {
        case .autofill:
            return autofill(path)
        case .privacy where path == ["website-data"]:
            return String(localized: "Website data")
        case .advanced where path == ["webkit-features"]:
            return String(localized: "Feature flags")
        case .about where path == ["acknowledgements"]:
            return String(localized: "Acknowledgements")
        case .websites:
            return website(path)
        case .provider:
            return assistant(path, coordinator: coordinator)
        default:
            return nil
        }
    }

    private static func autofill(_ path: [String]) -> String? {
        switch AutofillDestination(rawValue: path[0]) {
        case .passwords:
            String(localized: "Passwords")
        case .cards:
            String(localized: "Payment cards")
        case .contacts:
            String(localized: "Contacts and addresses")
        case nil:
            nil
        }
    }

    private static func website(_ path: [String]) -> String? {
        if path.count == 1, let permission = WebPermission(rawValue: path[0]) {
            return String(localized: permission.label)
        }
        guard path.count >= 2, path[0] == "site" else { return nil }
        let scheme = path.count == 3 ? path[2] : "https"
        return SitePermissions.displayName(for: "\(scheme)://\(path[1])")
    }

    private static func assistant(_ path: [String], coordinator: AppCoordinator) -> String? {
        switch path {
        case ["add"]:
            return String(localized: "Add a provider")
        case ["add", "custom"]:
            return String(localized: "Custom endpoint")
        case ["tools"]:
            return String(localized: "Tools")
        case ["allowed-websites"]:
            return String(localized: "Allowed without asking")
        case ["memory"]:
            return String(localized: "Memory")
        case ["connections"]:
            return String(localized: "External connections")
        default:
            break
        }
        let providers = coordinator.settingsWorkspace.intelligence.providers
        guard let provider = providers.first(where: { $0.id == path[0] }) else { return nil }
        guard path.count > 1 else { return provider.name }
        if path[1] == "tools" {
            return String(localized: "Tools")
        }
        if path[1] == "edit" {
            return String(localized: "Edit endpoint")
        }
        guard let page = OpenAISettingsPage(slug: path[1]) else { return provider.name }
        let subpage = path.dropFirst(2).first
        if page == .connections, subpage == "edit" {
            let id = path.dropFirst(3).first.flatMap { UUID(uuidString: $0) }
            let servers = OpenAISettingsStore.load(providerID: provider.id).mcpServers
            if let label = servers.first(where: { $0.id == id })?.label {
                return label
            }
        }
        return String(localized: page.subpageTitle(subpage) ?? page.title)
    }
}
