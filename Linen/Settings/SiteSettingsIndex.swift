// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct SiteSettingsEntry: Identifiable, Equatable {
    let origin: String
    let host: String
    var permissions: [WebPermission: PermissionPolicy] = [:]
    var assistantAccess: AssistantAccessPolicy = .ask
    var keepsActive = false
    var blocksAutomaticPicture = false
    var allowsTrackers = false
    var autoplay: AutoplayPolicy?
    var popups: PopupPolicy?
    var assistantGrants: [SensitiveAction.Category] = []

    var id: String {
        origin
    }

    var displayName: String {
        SitePermissions.displayName(for: origin)
    }

    var isEmpty: Bool {
        permissions.isEmpty
            && assistantAccess == .ask
            && !keepsActive
            && !blocksAutomaticPicture
            && !allowsTrackers
            && autoplay == nil
            && popups == nil
            && assistantGrants.isEmpty
    }

    var summaryPhrases: [String] {
        var phrases: [String] = []

        let allowed = WebPermission.allCases
            .filter { permissions[$0] == .allow }
            .map { String(localized: $0.sentenceName) }
        if !allowed.isEmpty {
            phrases.append(String(localized: "\(allowed.formatted(.list(type: .and, width: .narrow))) allowed"))
        }

        let denied = WebPermission.allCases
            .filter { permissions[$0] == .deny }
            .map { String(localized: $0.sentenceName) }
        if !denied.isEmpty {
            phrases.append(String(localized: "\(denied.formatted(.list(type: .and, width: .narrow))) blocked"))
        }

        switch assistantAccess {
        case .ask:
            break
        case .readOnly:
            phrases.append(String(localized: "assistant may read"))
        case .control:
            phrases.append(String(localized: "assistant may control"))
        case .deny:
            phrases.append(String(localized: "assistant has no access"))
        }

        if !assistantGrants.isEmpty {
            let names = assistantGrants.map { String(localized: $0.listName) }
            phrases.append(String(localized: "\(names.formatted(.list(type: .and, width: .narrow))) without asking"))
        }

        if keepsActive {
            phrases.append(String(localized: "kept loaded"))
        }

        if blocksAutomaticPicture {
            phrases.append(String(localized: "no automatic Picture in Picture"))
        }

        if allowsTrackers {
            phrases.append(String(localized: "trackers allowed"))
        }

        switch autoplay {
        case .allow:
            phrases.append(String(localized: "auto-play allowed"))
        case .silent:
            phrases.append(String(localized: "auto-play muted"))
        case .block:
            phrases.append(String(localized: "auto-play blocked"))
        case nil:
            break
        }

        switch popups {
        case .allow:
            phrases.append(String(localized: "pop-ups allowed"))
        case .block, .blockAndNotify:
            phrases.append(String(localized: "pop-ups blocked"))
        case nil:
            break
        }

        return phrases
    }

    var summary: String {
        summaryPhrases.joined(separator: " · ")
    }
}

enum SiteSettingsIndex {
    static func host(of origin: String) -> String {
        let host = URL(string: origin)?.host() ?? origin
        return ContentBlocker.normalized(host)
    }

    static func entries(
        permissions: SitePermissions,
        grantsByHost: [(host: String, categories: [SensitiveAction.Category])],
        exemptHosts: Set<String>
    ) -> [SiteSettingsEntry] {
        var byOrigin: [String: SiteSettingsEntry] = [:]

        func entry(for origin: String) -> SiteSettingsEntry {
            byOrigin[origin] ?? SiteSettingsEntry(origin: origin, host: host(of: origin))
        }

        for permission in WebPermission.allCases {
            for origin in permissions.origins(for: permission) {
                var found = entry(for: origin)
                found.permissions[permission] = permissions.policy(for: origin, permission)
                byOrigin[origin] = found
            }
        }

        for origin in permissions.assistantOrigins {
            var found = entry(for: origin)
            found.assistantAccess = permissions.assistantAccess(for: origin)
            byOrigin[origin] = found
        }

        for origin in permissions.keptActiveOrigins {
            var found = entry(for: origin)
            found.keepsActive = true
            byOrigin[origin] = found
        }

        for origin in permissions.noAutomaticPictureOrigins {
            var found = entry(for: origin)
            found.blocksAutomaticPicture = true
            byOrigin[origin] = found
        }

        for origin in permissions.autoplayOrigins {
            var found = entry(for: origin)
            found.autoplay = permissions.autoplay(for: origin)
            byOrigin[origin] = found
        }

        for origin in permissions.popupOrigins {
            var found = entry(for: origin)
            found.popups = permissions.popups(for: origin)
            byOrigin[origin] = found
        }

        func origins(forHost host: String) -> [String] {
            let matching = byOrigin.keys.filter { self.host(of: $0) == host }
            return matching.isEmpty ? ["https://\(host)"] : Array(matching)
        }

        for host in exemptHosts.map(ContentBlocker.normalized) {
            for origin in origins(forHost: host) {
                var found = entry(for: origin)
                found.allowsTrackers = true
                byOrigin[origin] = found
            }
        }

        for grant in grantsByHost {
            let host = ContentBlocker.normalized(grant.host)
            for origin in origins(forHost: host) {
                var found = entry(for: origin)
                found.assistantGrants = grant.categories
                byOrigin[origin] = found
            }
        }

        return byOrigin.values
            .filter { !$0.isEmpty }
            .sorted { left, right in
                left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
            }
    }
}
