// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Observation

nonisolated struct AgentMemoryUpdate: Codable, Equatable, Hashable, Sendable {
    let factID: UUID
    let subject: String
    let value: String
}

@MainActor
@Observable
final class AssistantMemory {
    nonisolated struct Fact: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
        static let databaseTableName = "assistantMemory"

        nonisolated enum Source: String, Codable, Sendable {
            case answer
            case message
            case model
        }

        var id: UUID
        var subject: String
        var value: String
        var source: Source
        var savedAt: Date

        static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
            .timeIntervalSinceReferenceDate
        }

        static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
            .timeIntervalSinceReferenceDate
        }
    }

    private(set) var facts: [Fact] = []
    private let database: AppDatabase

    static var isEnabled: Bool {
        get { LLMSettings.defaults.object(forKey: "assistant.memory.enabled") as? Bool ?? true }
        set { LLMSettings.defaults.set(newValue, forKey: "assistant.memory.enabled") }
    }

    init(database: AppDatabase) {
        self.database = database
        reload()
    }

    func reload() {
        facts = (try? database.writer.read { db in
            try Fact.order(Column("savedAt").desc).fetchAll(db)
        }) ?? []
    }

    @discardableResult
    func remember(_ subject: String, is value: String, source: Fact.Source) -> Fact? {
        let subject = Self.normalized(subject)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !subject.isEmpty, !value.isEmpty, value.count <= 200, !Self.isSensitive(subject + " " + value) else { return nil }
        let existing = facts.first { $0.subject == subject }
        let fact = Fact(id: existing?.id ?? UUID(), subject: subject, value: value, source: source, savedAt: Date())
        guard (try? database.writer.write { db in try fact.save(db) }) != nil else { return nil }
        reload()
        return fact
    }

    func update(_ fact: Fact, value: String) {
        remember(fact.subject, is: value, source: fact.source)
    }

    func forget(_ id: UUID) {
        _ = try? database.writer.write { db in try Fact.deleteOne(db, key: id) }
        reload()
    }

    func restore(_ update: AgentMemoryUpdate) {
        guard !facts.contains(where: { $0.id == update.factID }), !facts.contains(where: { $0.subject == update.subject }) else { return }
        let fact = Fact(id: update.factID, subject: update.subject, value: update.value, source: .message, savedAt: Date())
        _ = try? database.writer.write { db in try fact.save(db) }
        reload()
    }

    func forgetAll() {
        _ = try? database.writer.write { db in try Fact.deleteAll(db) }
        reload()
    }

    enum UpdateStatus: Equatable {
        case kept
        case changed
        case forgotten
    }

    func status(of update: AgentMemoryUpdate) -> UpdateStatus {
        guard let fact = facts.first(where: { $0.id == update.factID }) else { return .forgotten }
        return fact.value == update.value ? .kept : .changed
    }

    func fact(about subject: String) -> Fact? {
        let wanted = Self.words(in: subject)
        return facts.first { !wanted.isEmpty && Self.words(in: $0.subject).isSuperset(of: wanted) }
    }

    static func context(for facts: [Fact]) -> String {
        guard !facts.isEmpty else { return "" }
        return "[What you remember about the user: " + facts.map { "\($0.subject): \($0.value)" }.joined(separator: "; ") + "]\n"
    }

    nonisolated static func isSensitive(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.range(of: #"password|passcode|\bpin\b|cvv|cvc|card number|security code|iban|social security|passport|one-time code"#,
                         options: .regularExpression) != nil {
            return true
        }
        return text.filter(\.isNumber).count >= 9
    }

    nonisolated static func normalized(_ subject: String) -> String {
        var words = subject.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.first == "my" || words.first == "our" {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    nonisolated private static func words(in text: String) -> Set<String> {
        let ignored: Set<String> = ["the", "and", "for", "you", "your", "this", "that", "with", "set", "use", "what", "are", "was"]
        return Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !ignored.contains($0) }
            .map { word in
                let singular = word.hasSuffix("s") && word.count > 4 ? String(word.dropLast()) : word
                return singular == "color" ? "colour" : singular
            })
    }
}
