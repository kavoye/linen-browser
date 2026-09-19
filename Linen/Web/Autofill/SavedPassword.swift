// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

nonisolated struct SavedPassword: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var origin: String
    var username: String
    var password: String

    init(website: String, username: String, password: String) throws {
        let address = website.contains("://") ? website : "https://" + website
        guard let url = URL(string: address), let origin = Self.origin(for: url),
              !password.isEmpty, password.count <= 4096, username.count <= 500 else { throw AutofillVaultError.invalidData }
        self.origin = origin
        self.username = username
        self.password = password
    }

    static func origin(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.lowercased()
        if let port = url.port, port != 443 {
            components.port = port
        }
        return components.string
    }

    var summary: Summary {
        Summary(id: id, origin: origin, username: username)
    }

    nonisolated struct Summary: Identifiable, Equatable, Sendable {
        let id: UUID
        let origin: String
        let username: String
    }

    static func generate() throws -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AutofillVaultError.keychain(errSecNotAvailable) }
        return String(decoding: bytes.map { alphabet[Int($0 & 63)] }, as: UTF8.self)
    }

    static func merging(_ incoming: Self, into records: [Self]) -> [Self] {
        var records = records
        var incoming = incoming
        if let index = records.firstIndex(where: { $0.id == incoming.id })
            ?? records.firstIndex(where: { $0.origin == incoming.origin && $0.username == incoming.username }) {
            incoming.id = records[index].id
            records[index] = incoming
            records.removeAll { $0.id != incoming.id && $0.origin == incoming.origin && $0.username == incoming.username }
        } else {
            records.append(incoming)
        }
        return records
    }
}

enum PasswordExtensionPolicy {
    static let knownIDs: Set<String> = [
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa", "nngceckbapebfimnlniiiahkandclblb",
        "hdokiejnpimakedhajhdlcegeplioahd", "fdjamakpfbbddfjaooikfcpapjohcfmg",
        "ghmbeldphafepmbegfdlkpapadhbakde", "bfogiafebfohielmmehodmfbbebbbpei",
        "iCloudPasswords", "bitwarden-password-manager", "1password-x-password-manager",
        "lastpass-password-manager", "dashlane", "proton-pass", "keepassxc-browser",
    ]

    private static let knownNames = [
        "1password", "bitwarden", "lastpass", "dashlane", "proton pass", "keeper", "enpass",
        "roboform", "keepassxc", "keepass", "strongbox", "icloud passwords", "passwords", "passbolt", "nordpass",
    ]

    static func availableProviders(in records: [InstalledExtension]) -> [InstalledExtension] {
        records.filter { record in
            guard record.enabled else { return false }
            if knownIDs.contains(record.id) { return true }
            let name = record.displayName.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ")
            return knownNames.contains { name == $0 || name.hasPrefix($0 + " ") }
        }
    }

    static func provider(in records: [InstalledExtension], selectedID: String = "") -> InstalledExtension? {
        let providers = availableProviders(in: records)
        return providers.first { $0.id == selectedID } ?? providers.first
    }
}
