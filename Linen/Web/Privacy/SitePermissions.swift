// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import SwiftUI

nonisolated enum WebPermission: String, Codable, CaseIterable, Sendable {
    case location
    case camera
    case microphone
    case notifications

    var label: LocalizedStringResource {
        switch self {
        case .location:
            "Location"
        case .camera:
            "Camera"
        case .microphone:
            "Microphone"
        case .notifications:
            "Notifications"
        }
    }

    var sentenceName: LocalizedStringResource {
        switch self {
        case .location:
            "location"
        case .camera:
            "camera"
        case .microphone:
            "microphone"
        case .notifications:
            "notifications"
        }
    }

    var symbol: String {
        switch self {
        case .location:
            "location.fill"
        case .camera:
            "video.fill"
        case .microphone:
            "mic.fill"
        case .notifications:
            "bell.fill"
        }
    }

    @MainActor
    var liveTint: Color {
        switch self {
        case .camera:
            .green
        case .microphone:
            .orange
        case .location, .notifications:
            Theme.accent
        }
    }

    var slashedSymbol: String {
        switch self {
        case .location:
            "location.slash.fill"
        case .camera:
            "video.slash.fill"
        case .microphone:
            "mic.slash.fill"
        case .notifications:
            "bell.slash.fill"
        }
    }
}

nonisolated enum PermissionPolicy: String, Codable, Sendable {
    case ask
    case allow
    case deny

    var label: LocalizedStringResource {
        switch self {
        case .ask:
            "Ask"
        case .allow:
            "Always Allow"
        case .deny:
            "Deny"
        }
    }
}

nonisolated enum AssistantAccessPolicy: String, Codable, CaseIterable, Sendable {
    case ask
    case readOnly
    case control
    case deny

    var label: LocalizedStringResource {
        switch self {
        case .ask:
            "Ask"
        case .readOnly:
            "Read Only"
        case .control:
            "Allow Control"
        case .deny:
            "No Access"
        }
    }
}

@MainActor
@Observable
final class SitePermissions {
    static private(set) var shared = SitePermissions()

    @discardableResult
    static func use(file: URL) -> SitePermissions {
        let store = SitePermissions(storageURL: file)
        shared = store
        return store
    }

    private(set) var records: [String: [WebPermission: PermissionPolicy]] = [:]

    private(set) var defaults: [WebPermission: PermissionPolicy] = [:]

    private(set) var assistantRecords: [String: AssistantAccessPolicy] = [:]

    private var keptActiveOriginSet: Set<String> = []
    private(set) var keptActiveOrigins: [String] = []

    private var noAutomaticPictureOriginSet: Set<String> = []
    private(set) var noAutomaticPictureOrigins: [String] = []

    private let file: URL
    private var saveTask: Task<Void, Never>?

    init(storageURL: URL? = nil) {
        file = storageURL ?? Self.defaultFile
        load()
    }

    // MARK: - Reading

    func policy(for origin: String, _ permission: WebPermission) -> PermissionPolicy {
        if let stored = records[normalize(origin)]?[permission] {
            return stored
        }
        return defaults[permission] ?? .ask
    }

    func recordedPermissions(for origin: String) -> [WebPermission: PermissionPolicy] {
        records[normalize(origin)] ?? [:]
    }

    func origins(for permission: WebPermission) -> [String] {
        records.compactMap { origin, policies in
            policies[permission] != nil ? origin : nil
        }
        .sorted()
    }

    func defaultPolicy(for permission: WebPermission) -> PermissionPolicy {
        defaults[permission] ?? .ask
    }

    func assistantAccess(for origin: String) -> AssistantAccessPolicy {
        assistantRecords[normalize(origin)] ?? .ask
    }

    var assistantOrigins: [String] {
        assistantRecords.keys.sorted()
    }

    func keepsActive(_ origin: String) -> Bool {
        keptActiveOriginSet.contains(normalize(origin))
    }

    func allowsAutomaticPicture(_ origin: String) -> Bool {
        !noAutomaticPictureOriginSet.contains(normalize(origin))
    }

    // MARK: - Writing

    func set(_ policy: PermissionPolicy, for origin: String, _ permission: WebPermission) {
        let origin = normalize(origin)
        guard !origin.isEmpty else { return }
        if policy == .ask {
            records[origin]?[permission] = nil
            if records[origin]?.isEmpty == true {
                records[origin] = nil
            }
        } else {
            records[origin, default: [:]][permission] = policy
        }
        scheduleSave()
    }

    func setDefault(_ policy: PermissionPolicy, for permission: WebPermission) {
        defaults[permission] = policy == .deny ? .deny :
            nil
        scheduleSave()
    }

    func removeAll(for permission: WebPermission) {
        for origin in records.keys {
            records[origin]?[permission] = nil
            if records[origin]?.isEmpty == true {
                records[origin] = nil
            }
        }
        scheduleSave()
    }

    func setAssistantAccess(_ policy: AssistantAccessPolicy, for origin: String) {
        let origin = normalize(origin)
        guard !origin.isEmpty else { return }
        assistantRecords[origin] = policy == .ask ? nil : policy
        scheduleSave()
    }

    func removeAllAssistantAccess() {
        assistantRecords = [:]
        scheduleSave()
    }

    func setKeepsActive(_ keepsActive: Bool, for origin: String) {
        let origin = normalize(origin)
        guard !origin.isEmpty else { return }
        if keepsActive {
            keptActiveOriginSet.insert(origin)
        } else {
            keptActiveOriginSet.remove(origin)
        }
        keptActiveOrigins = keptActiveOriginSet.sorted()
        scheduleSave()
    }

    func setAllowsAutomaticPicture(_ allows: Bool, for origin: String) {
        let origin = normalize(origin)
        guard !origin.isEmpty else { return }
        if allows {
            noAutomaticPictureOriginSet.remove(origin)
        } else {
            noAutomaticPictureOriginSet.insert(origin)
        }
        noAutomaticPictureOrigins = noAutomaticPictureOriginSet.sorted()
        scheduleSave()
    }

    func removeAllKeptActiveOrigins() {
        keptActiveOriginSet = []
        keptActiveOrigins = []
        scheduleSave()
    }

    func removeEverything() {
        records = [:]
        assistantRecords = [:]
        keptActiveOriginSet = []
        keptActiveOrigins = []
        noAutomaticPictureOriginSet = []
        noAutomaticPictureOrigins = []
        scheduleSave()
    }

    func waitForPendingSave() async {
        await saveTask?.value
    }

    // MARK: - What counts as one site

    nonisolated static func origin(for url: URL?) -> String {
        guard let url, let scheme = url.scheme?.lowercased(),
              var host = url.host()?.lowercased(), !host.isEmpty
        else { return "" }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        if host.contains(":") {
            host = "[\(host)]"
        }
        guard let port = url.port, port != defaultPort(for: scheme) else {
            return "\(scheme)://\(host)"
        }
        return "\(scheme)://\(host):\(port)"
    }

    private nonisolated static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "https", "wss":
            443
        case "http", "ws":
            80
        default:
            nil
        }
    }

    nonisolated static func isPotentiallyTrustworthy(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" || scheme == "wss" || scheme == "file" {
            return true
        }
        guard let host = url.host()?.lowercased() else { return false }
        return host == "localhost" || host.hasSuffix(".localhost")
            || host == "::1" || host.hasPrefix("127.")
    }

    nonisolated static func displayName(for origin: String) -> String {
        let prefix = "https://"
        guard origin.hasPrefix(prefix) else { return origin }
        let rest = origin.dropFirst(prefix.count)
        return rest.contains(":") ? origin : String(rest)
    }

    nonisolated func normalize(_ origin: String) -> String {
        if origin.contains("://") {
            return Self.origin(for: URL(string: origin))
        }
        var host = origin.lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }
        return host.isEmpty ? "" : "https://\(host)"
    }

    // MARK: - Persistence

    private nonisolated struct Snapshot: Codable, Sendable {
        var records: [String: [WebPermission: PermissionPolicy]] = [:]
        var defaults: [WebPermission: PermissionPolicy] = [:]
        var assistantAccess: [String: AssistantAccessPolicy] = [:]
        var keptActive: Set<String> = []
        var noAutomaticPicture: Set<String> = []

        init(
            records: [String: [WebPermission: PermissionPolicy]],
            defaults:
                [WebPermission: PermissionPolicy],
            assistantAccess: [String: AssistantAccessPolicy],
            keptActive: Set<String>,
            noAutomaticPicture: Set<String>
        ) {
            self.records = records
            self.defaults = defaults
            self.assistantAccess = assistantAccess
            self.keptActive = keptActive
            self.noAutomaticPicture = noAutomaticPicture
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            records = try values.decodeIfPresent(
                [String: [WebPermission: PermissionPolicy]].self,
                forKey: .records
            ) ?? [:]
            defaults = try values.decodeIfPresent(
                [WebPermission: PermissionPolicy].self,
                forKey: .defaults
            ) ?? [:]
            assistantAccess = try values.decodeIfPresent(
                [String: AssistantAccessPolicy].self,
                forKey: .assistantAccess
            ) ?? [:]
            keptActive = try values.decodeIfPresent(
                Set<String>.self,
                forKey: .keptActive
            ) ?? []
            noAutomaticPicture = try values.decodeIfPresent(
                Set<String>.self,
                forKey: .noAutomaticPicture
            ) ?? []
        }
    }

    nonisolated static func changedSiteCount(in file: URL) -> Int {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return 0 }
        return Set(snapshot.records.keys).union(snapshot.assistantAccess.keys).count
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = Snapshot(
            records: records,
            defaults:
                defaults,
            assistantAccess: assistantRecords,
            keptActive: keptActiveOriginSet,
            noAutomaticPicture: noAutomaticPictureOriginSet
        )
        let url = file
        saveTask = Task {
            await JSONFileStore.shared.write(snapshot, to: url, sortedKeys: true)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        for (key, policies) in snapshot.records {
            let origin = normalize(key)
            guard !origin.isEmpty else { continue }
            records[origin, default: [:]].merge(policies) { existing, _ in existing }
        }
        defaults = snapshot.defaults
        for (key, policy) in snapshot.assistantAccess {
            let origin = normalize(key)
            guard !origin.isEmpty, assistantRecords[origin] == nil else { continue }
            assistantRecords[origin] = policy == .ask ? nil : policy
        }
        for key in snapshot.keptActive {
            let origin = normalize(key)
            if !origin.isEmpty {
                keptActiveOriginSet.insert(origin)
            }
        }
        keptActiveOrigins = keptActiveOriginSet.sorted()
        for key in snapshot.noAutomaticPicture {
            let origin = normalize(key)
            if !origin.isEmpty {
                noAutomaticPictureOriginSet.insert(origin)
            }
        }
        noAutomaticPictureOrigins = noAutomaticPictureOriginSet.sorted()
    }

    private static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linen", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("SitePermissions.json")
    }
}
