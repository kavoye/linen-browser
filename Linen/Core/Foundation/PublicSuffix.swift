// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum PublicSuffix {
    private static let rules: Set<String> = {
        guard let url = Bundle.main.url(forResource: "PublicSuffixList", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return Set(text.split(separator: "\n").lazy.filter { !$0.hasPrefix("//") }.map(String.init))
    }()

    static func registrableDomain(of host: String) -> String? {
        var host = host.lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty, !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !labels.contains("") else { return nil }

        var suffixLength = 1
        for start in labels.indices {
            let suffix = labels[start...].joined(separator: ".")
            if rules.contains("!" + suffix) {
                suffixLength = labels.count - start - 1
                break
            }
            let parent = labels[(start + 1)...].joined(separator: ".")
            if rules.contains(suffix) || (!parent.isEmpty && rules.contains("*." + parent)) {
                suffixLength = labels.count - start
                break
            }
        }
        guard labels.count > suffixLength else { return nil }
        return labels.suffix(suffixLength + 1).joined(separator: ".")
    }
}
