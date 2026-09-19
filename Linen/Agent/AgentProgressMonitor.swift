// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

nonisolated struct AgentProgressMonitor {
    private var recent: [String] = []
    private var failures = 0
    private var recoveryAttempts = 0
    private var stalledKeys: Set<String> = []
    private var progressKeys: Set<String> = []
    let policy: AgentExecutionPolicy

    init(policy: AgentExecutionPolicy) {
        self.policy = policy
    }

    enum Decision {
        case proceed
        case recover
        case pause
    }

    mutating func observe(name: String, arguments: String, output: String, failed: Bool) -> Decision {
        guard name != "askUser" else {
            recent = []
            failures = 0
            recoveryAttempts = 0
            stalledKeys = []
            progressKeys = []
            return .proceed
        }
        let comparison = Self.comparison(name: name, arguments: arguments, output: output)
        let bytes = Data((name + "\u{0}" + comparison.arguments + "\u{0}" + comparison.output).utf8)
        let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        if recoveryAttempts > 0, !failed, !stalledKeys.contains(key) {
            progressKeys.insert(key)
            if progressKeys.count >= policy.repeatedActionLimit {
                recoveryAttempts = 0
                stalledKeys = []
                progressKeys = []
                recent = []
            }
        } else if failed {
            progressKeys = []
        }
        failures = failed ? failures + 1 : 0
        recent.append(key)
        if recent.count > 12 {
            recent.removeFirst()
        }
        let repeated = recent.filter { $0 == key }.count >= policy.repeatedActionLimit
        guard repeated || failures >= policy.consecutiveFailureLimit else { return .proceed }
        if recoveryAttempts > 0, stalledKeys.contains(key) || failed {
            return .pause
        }
        recoveryAttempts += 1
        stalledKeys = Set(recent)
        progressKeys = []
        recent = []
        failures = 0
        return .recover
    }

    private static func comparison(name: String, arguments: String, output: String) -> (arguments: String, output: String) {
        let pageTools: Set<String> = [
            "readPage", "clickOnPage", "typeOnPage", "fillFields", "selectOption", "scrollPage", "goBack",
            "inspectControl", "setChecked", "waitForPage", "hoverOnPage", "pressKey",
        ]
        guard pageTools.contains(name) else { return (arguments, output) }
        var stableArguments = arguments
        if let data = arguments.data(using: .utf8),
           var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object.removeValue(forKey: "observationID")
            if let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                stableArguments = String(decoding: encoded, as: UTF8.self)
            }
        }
        var lines = output.components(separatedBy: "\n")
        if let index = lines.lastIndex(where: { $0.hasPrefix("observationID: ") }) {
            let suffix = lines[(index + 1)...]
            if suffix.allSatisfy({ $0.isEmpty || $0 == "</page-content>" || $0.hasPrefix("More text: ") || $0.hasPrefix("More controls: ") }) {
                lines.remove(at: index)
            }
        }
        return (stableArguments, lines.joined(separator: "\n"))
    }
}
