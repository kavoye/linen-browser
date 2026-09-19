// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import LocalAuthentication
import Synchronization

nonisolated enum AutofillSaveIndex {
    enum Decision: Sendable {
        case new, update, unchanged, blocked
    }

    private struct Index: Codable {
        var key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var records: [String: [String: String]] = [:]
        var blocked: [String: Set<String>] = [:]
        var suggestions: [String: [AutofillSuggestion]] = [:]

        func digest(_ parts: [String]) throws -> String {
            guard key.count == 32 else { throw AutofillVaultError.invalidData }
            let data = try JSONEncoder().encode(parts)
            return Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))).base64EncodedString()
        }
    }

    private static let lock = Mutex(())
    private static let storage = AutofillKeychainStorage(access: .whenUnlocked)

    private static func service(_ profileID: UUID) -> String {
        var namespace = "com.kavoye.Linen.autofill"
        if AppDatabase.isRunningTests { namespace += ".tests.\(ProcessInfo.processInfo.processIdentifier)" }
        #if DEBUG
        if StageMode.isActive { namespace += ".stage" }
        #endif
        return "\(namespace).save-index.\(profileID.uuidString)"
    }

    private static func access<T>(profileID: UUID, saving: Bool, _ body: (inout Index) throws -> T) throws -> T {
        guard profileID != Profile.privateID else { throw AutofillVaultError.privateBrowsing }
        return try lock.withLock { _ in
            let context = LAContext()
            context.interactionNotAllowed = true
            let data = try storage.read(service: service(profileID), context: context)
            guard (data?.count ?? 0) <= 8_000_000 else { throw AutofillVaultError.invalidData }
            var index = try data.map { try JSONDecoder().decode(Index.self, from: $0) } ?? Index()
            let result = try body(&index)
            if saving {
                let encoded = try JSONEncoder().encode(index)
                guard encoded.count <= 8_000_000 else { throw AutofillVaultError.invalidData }
                try storage.write(encoded, service: service(profileID), context: context)
            }
            return result
        }
    }

    static func decision(for candidate: AutofillSaveCandidate, origin: String, profileID: UUID) throws -> Decision {
        try access(profileID: profileID, saving: false) { index in
            let kind = candidate.kind.rawValue
            if try index.blocked[kind]?.contains(index.digest([kind, origin])) == true { return .blocked }
            let identity = try index.digest([kind] + candidate.identity)
            guard let existing = index.records[kind]?[identity] else { return .new }
            return try existing == index.digest([kind] + candidate.values) ? .unchanged : .update
        }
    }

    static func replace(_ candidates: [AutofillSaveCandidate], kind: AutofillSaveKind, profileID: UUID) throws {
        try access(profileID: profileID, saving: true) { index in
            var records: [String: String] = [:]
            for candidate in candidates {
                records[try index.digest([kind.rawValue] + candidate.identity)] = try index.digest([kind.rawValue] + candidate.values)
            }
            index.records[kind.rawValue] = records
            index.suggestions[kind.rawValue] = candidates.map(AutofillSuggestion.init)
        }
    }

    static func suggestions(kind: AutofillSaveKind, origin: String, profileID: UUID) throws -> [AutofillSuggestion] {
        try access(profileID: profileID, saving: false) { index in
            (index.suggestions[kind.rawValue] ?? []).filter {
                (kind != .password || $0.origin == origin) && !$0.isExpired
            }
        }
    }

    static func block(kind: AutofillSaveKind, origin: String, profileID: UUID) throws {
        try access(profileID: profileID, saving: true) { index in
            var blocked = index.blocked[kind.rawValue] ?? []
            guard blocked.count < 1000 else { return }
            blocked.insert(try index.digest([kind.rawValue, origin]))
            index.blocked[kind.rawValue] = blocked
        }
    }

    static func resetBlocks(kind: AutofillSaveKind, profileID: UUID) throws {
        try access(profileID: profileID, saving: true) { $0.blocked[kind.rawValue] = nil }
    }

    static func erase(profileID: UUID) throws {
        try lock.withLock { _ in try storage.erase(service: service(profileID)) }
    }
}
