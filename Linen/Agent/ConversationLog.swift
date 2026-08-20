// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import GRDB
import Observation
import os

@MainActor
@Observable
final class ConversationLog {
    nonisolated struct Usage: Codable, Equatable, Sendable {
        var requestCount = 0
        var inputTokens = 0
        var cachedTokens = 0
        var outputTokens = 0
        var estimatedContextTokens = 0

        static let zero = Usage()
    }

    nonisolated struct ActivityLink: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let title: String
        let url: URL

        init(id: UUID = UUID(), title: String, url: URL) {
            self.id = id
            self.title = title
            self.url = url
        }
    }

    nonisolated struct Step: Codable, Identifiable, Equatable, Sendable {
        enum Kind: String, Codable, Equatable {
            case thinking
            case tool
        }

        enum State: String, Codable, Equatable {
            case running
            case completed
            case failed
        }

        let id: UUID
        let kind: Kind
        let title: String
        let toolName: String?
        let startedAt: Date
        var detail: String?
        var links: [ActivityLink]
        var state: State

        init(
            kind: Kind,
            title: String,
            toolName: String? = nil,
            detail: String? = nil,
            links: [ActivityLink] = [],
            state: State = .running
        ) {
            id = UUID()
            self.kind = kind
            self.title = title
            self.toolName = toolName
            self.startedAt = Date()
            self.detail = detail
            self.links = links
            self.state = state
        }

        init(
            id: UUID,
            kind: Kind,
            title: String,
            toolName: String?,
            startedAt: Date,
            detail: String?,
            links: [ActivityLink],
            state: State
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.toolName = toolName
            self.startedAt = startedAt
            self.detail = detail
            self.links = links
            self.state = state
        }
    }

    nonisolated struct TaskTrace: Codable, Identifiable, Equatable, Sendable {
        enum State: String, Codable, Equatable {
            case running
            case completed
            case cancelled
            case failed
        }

        let id: UUID
        var tabID: UUID
        let prompt: String
        let startedAt: Date
        var steps: [Step]
        var response: String
        var state: State
        var finishedAt: Date?
    }

    struct Exchange: Equatable {
        let prompt: String
        let response: String
    }

    private nonisolated struct TraceRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentTrace"

        var id: UUID
        var tabID: UUID
        var prompt: String
        var startedAt: Date
        var response: String
        var state: TaskTrace.State
        var finishedAt: Date?
    }

    private nonisolated struct StepRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentStep"

        var id: UUID
        var traceID: UUID
        var position: Int
        var kind: Step.Kind
        var title: String
        var toolName: String?
        var startedAt: Date
        var detail: String?
        var links: String
        var state: Step.State
    }

    private nonisolated struct UsageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
        static let databaseTableName = "agentUsage"

        var tabID: UUID
        var requestCount: Int
        var inputTokens: Int
        var cachedTokens: Int
        var outputTokens: Int
        var estimatedContextTokens: Int
    }

    private(set) var traces: [TaskTrace] = []
    private(set) var usageByTab: [UUID: Usage] = [:]
    private(set) var failureCount = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var discardedTabIDs = RecentIDs()
    @ObservationIgnored private var dirtyTraceIDs: Set<UUID> = []
    @ObservationIgnored private var dirtyUsageTabIDs: Set<UUID> = []
    private var database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
        load()
    }

    func adopt(database: AppDatabase) {
        saveTask?.cancel()
        saveTask = nil
        self.database = database
        traces = []
        usageByTab = [:]
        dirtyTraceIDs = []
        dirtyUsageTabIDs = []
        discardedTabIDs = RecentIDs()
        load()
    }

    @discardableResult
    func beginTask(_ prompt: String, tabID: UUID) -> UUID {
        discardedTabIDs.remove(tabID)
        cancelRunningTask(forTab: tabID)

        let taskID = UUID()
        traces.append(TaskTrace(
            id: taskID,
            tabID: tabID,
            prompt: prompt,
            startedAt: Date(),
            steps: [Step(kind: .thinking, title: String(localized: "Understanding the request"))],
            response: "",
            state: .running,
            finishedAt: nil
        ))
        scheduleSave(trace: taskID)
        return taskID
    }

    @discardableResult
    func beginTool(
        taskID: UUID,
        name: String,
        title: String,
        detail: String? = nil
    ) -> UUID? {
        guard let traceIndex = traces.firstIndex(where: { $0.id == taskID }),
              traces[traceIndex].state == .running
        else { return nil }
        finishRunningSteps(at: traceIndex)
        let step = Step(kind: .tool, title: title, toolName: name, detail: detail)
        traces[traceIndex].steps.append(step)
        scheduleSave(trace: taskID)
        return step.id
    }

    func completeTool(
        taskID: UUID,
        stepID: UUID?,
        detail: String,
        links: [ActivityLink] = [],
        failed: Bool = false
    ) {
        guard let stepID,
              let traceIndex = traces.firstIndex(where: { $0.id == taskID }),
              traces[traceIndex].state == .running,
              let stepIndex = traces[traceIndex].steps.firstIndex(where: { $0.id == stepID })
        else { return }

        traces[traceIndex].steps[stepIndex].detail = Self.trimmedDetail(detail)
        traces[traceIndex].steps[stepIndex].links = links
        traces[traceIndex].steps[stepIndex].state = failed ? .failed : .completed
        scheduleSave(trace: taskID)
    }

    func updateResponse(_ response: String, taskID: UUID) {
        guard let index = traces.firstIndex(where: { $0.id == taskID }),
              traces[index].state == .running
        else { return }
        finishRunningSteps(at: index)
        traces[index].response = response
        scheduleSave(trace: taskID)
    }

    func completeTask(_ taskID: UUID, response: String) {
        guard let index = traces.firstIndex(where: { $0.id == taskID }),
              traces[index].state == .running
        else { return }
        finishRunningSteps(at: index)
        traces[index].response = response
        traces[index].state = .completed
        traces[index].finishedAt = Date()
        scheduleSave(trace: taskID)
        saveNow()
    }

    func failTask(_ taskID: UUID, reason: String) {
        guard let index = traces.firstIndex(where: { $0.id == taskID }),
              traces[index].state == .running
        else { return }
        finishRunningSteps(at: index, failed: true)
        traces[index].response = reason
        traces[index].state = .failed
        traces[index].finishedAt = Date()
        failureCount += 1
        scheduleSave(trace: taskID)
        saveNow()
    }

    func cancelTask(_ taskID: UUID) {
        guard let index = traces.firstIndex(where: { $0.id == taskID }),
              traces[index].state == .running
        else { return }
        finishRunningSteps(at: index, failed: true)
        traces[index].state = .cancelled
        traces[index].finishedAt = Date()
        scheduleSave(trace: taskID)
        saveNow()
    }

    func cancelRunningTask(forTab tabID: UUID) {
        guard let index = traces.lastIndex(where: { $0.tabID == tabID && $0.state == .running }) else { return }
        finishRunningSteps(at: index, failed: true)
        traces[index].state = .cancelled
        traces[index].finishedAt = Date()
        scheduleSave(trace: traces[index].id)
    }

    func recordUsage(tabID: UUID, input: Int, cached: Int, output: Int) {
        guard !discardedTabIDs.contains(tabID) else { return }
        var usage = usageByTab[tabID, default: .zero]
        usage.requestCount += 1
        usage.inputTokens += input
        usage.cachedTokens += cached
        usage.outputTokens += output
        usageByTab[tabID] = usage
        scheduleSave(usage: tabID)
    }

    func recordContextEstimate(tabID: UUID, tokens: Int) {
        guard !discardedTabIDs.contains(tabID) else { return }
        var usage = usageByTab[tabID, default: .zero]
        usage.estimatedContextTokens = tokens
        usageByTab[tabID] = usage
        scheduleSave(usage: tabID)
    }

    func usage(forTab tabID: UUID) -> Usage {
        usageByTab[tabID, default: .zero]
    }

    func traces(forTab tabID: UUID) -> [TaskTrace] {
        traces.filter { $0.tabID == tabID }
    }

    func latestTrace(forTab tabID: UUID) -> TaskTrace? {
        traces.last { $0.tabID == tabID }
    }

    func hasActivity(forTab tabID: UUID) -> Bool {
        traces.contains { $0.tabID == tabID }
    }

    func isRunning(onTab tabID: UUID) -> Bool {
        traces.last { $0.tabID == tabID }?.state == .running
    }

    func exchanges(forTab tabID: UUID, limit: Int? = nil) -> [Exchange] {
        let exchanges = traces.lazy
            .filter { $0.tabID == tabID && $0.state == .completed && !$0.response.isEmpty }
            .map { Exchange(prompt: $0.prompt, response: $0.response) }
        let all = Array(exchanges)
        guard let limit, all.count > limit else { return all }
        return Array(all.suffix(limit))
    }

    func removeTab(_ tabID: UUID) {
        discardedTabIDs.insert(tabID)
        traces.removeAll { $0.tabID == tabID }
        usageByTab.removeValue(forKey: tabID)
        forget([tabID])
    }

    func reassign(from tabID: UUID, to newTabID: UUID) {
        guard tabID != newTabID,
              !discardedTabIDs.contains(newTabID),
              !traces.contains(where: { $0.tabID == newTabID }),
              usageByTab[newTabID] == nil
        else { return }

        var moved = false
        for index in traces.indices where traces[index].tabID == tabID {
            traces[index].tabID = newTabID
            dirtyTraceIDs.insert(traces[index].id)
            moved = true
        }
        if let usage = usageByTab.removeValue(forKey: tabID) {
            usageByTab[newTabID] = usage
            dirtyUsageTabIDs.remove(tabID)
            dirtyUsageTabIDs.insert(newTabID)
            writeNow { db in
                _ = try UsageRecord.filter(Column("tabID") == tabID).deleteAll(db)
            }
            moved = true
        }
        guard moved else { return }
        scheduleFlush()
    }

    func removeTrace(_ traceID: UUID) {
        guard let index = traces.firstIndex(where: { $0.id == traceID }),
              traces[index].state != .running
        else { return }
        traces.remove(at: index)
        dirtyTraceIDs.remove(traceID)
        writeNow { db in
            _ = try TraceRecord.filter(Column("id") == traceID).deleteAll(db)
        }
    }

    func clearAll() {
        guard !traces.isEmpty || !usageByTab.isEmpty else { return }
        discardedTabIDs.formUnion(traces.map(\.tabID))
        traces.removeAll()
        usageByTab.removeAll()
        dirtyTraceIDs.removeAll()
        dirtyUsageTabIDs.removeAll()
        saveTask?.cancel()
        saveTask = nil
        writeNow { db in
            _ = try TraceRecord.deleteAll(db)
            _ = try UsageRecord.deleteAll(db)
        }
    }

    func retainTabs(_ tabIDs: Set<UUID>) {
        let removed = Set(traces.map(\.tabID)).union(usageByTab.keys).subtracting(tabIDs)
        guard !removed.isEmpty else { return }
        discardedTabIDs.formUnion(removed)
        traces.removeAll { !tabIDs.contains($0.tabID) }
        usageByTab = usageByTab.filter { tabIDs.contains($0.key) }
        forget(removed)
    }

    private func forget(_ tabIDs: Set<UUID>) {
        guard !tabIDs.isEmpty else { return }
        dirtyTraceIDs.subtract(traces.filter { tabIDs.contains($0.tabID) }.map(\.id))
        dirtyUsageTabIDs.subtract(tabIDs)
        let ids = Array(tabIDs)
        writeNow { db in
            _ = try TraceRecord.filter(ids.contains(Column("tabID"))).deleteAll(db)
            _ = try UsageRecord.filter(ids.contains(Column("tabID"))).deleteAll(db)
        }
    }

    // MARK: - Persistence

    private func scheduleSave(trace id: UUID) {
        dirtyTraceIDs.insert(id)
        scheduleFlush()
    }

    private func scheduleSave(usage tabID: UUID) {
        dirtyUsageTabIDs.insert(tabID)
        scheduleFlush()
    }

    private func scheduleFlush() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        flush(blocking: false)
    }

    func saveBlocking() {
        flush(blocking: true)
    }

    private func flush(blocking: Bool) {
        saveTask?.cancel()
        saveTask = nil
        guard blocking || !dirtyTraceIDs.isEmpty || !dirtyUsageTabIDs.isEmpty else { return }

        let traceRows = blocking
            ? traces
            : dirtyTraceIDs.compactMap { id in traces.first { $0.id == id } }
        let stepRows = traceRows.flatMap(Self.steps(of:))
        let usageRows = blocking
            ? usageByTab.map { Self.record($0.value, for: $0.key) }
            : dirtyUsageTabIDs.map { tabID in
                Self.record(usageByTab[tabID, default: .zero], for: tabID)
            }
        let touched = traceRows.map(\.id)
        dirtyTraceIDs.removeAll()
        dirtyUsageTabIDs.removeAll()

        let updates: @Sendable (Database) throws -> Void = { db in
            for trace in traceRows {
                try Self.record(trace).save(db)
            }
            _ = try StepRecord.filter(touched.contains(Column("traceID"))).deleteAll(db)
            for step in stepRows {
                try step.insert(db)
            }
            for usage in usageRows {
                try usage.save(db)
            }
        }
        if blocking {
            writeNow(updates)
        } else {
            write(updates)
        }
    }

    private func load() {
        let stored = try? database.writer.read { db in
            (
                traces: try TraceRecord.order(Column("startedAt")).fetchAll(db),
                steps: try StepRecord.order(Column("position")).fetchAll(db),
                usage: try UsageRecord.fetchAll(db)
            )
        }
        guard let stored else { return }

        let stepsByTrace = Dictionary(grouping: stored.steps, by: \.traceID)
        var repairedInterruptedTask = false

        traces = stored.traces.map { record in
            var trace = TaskTrace(
                id: record.id,
                tabID: record.tabID,
                prompt: record.prompt,
                startedAt: record.startedAt,
                steps: (stepsByTrace[record.id] ?? []).map(Self.step(from:)),
                response: record.response,
                state: record.state,
                finishedAt: record.finishedAt
            )
            guard trace.state == .running else { return trace }
            for index in trace.steps.indices where trace.steps[index].state == .running {
                trace.steps[index].state = .failed
            }
            trace.state = .cancelled
            trace.finishedAt = Date()
            repairedInterruptedTask = true
            dirtyTraceIDs.insert(trace.id)
            return trace
        }

        usageByTab = Dictionary(
            stored.usage.map { ($0.tabID, Self.usage(from: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        if repairedInterruptedTask {
            scheduleFlush()
        }
    }

    private func write(_ updates: @escaping @Sendable (Database) throws -> Void) {
        let database = database
        Task {
            do {
                try await database.writer.write(updates)
            } catch {
                Pipeline.log.error("agent log: write failed: \(error, privacy: .public)")
            }
        }
    }

    private func writeNow(_ updates: (Database) throws -> Void) {
        do {
            try database.writer.write(updates)
        } catch {
            Pipeline.log.error("agent log: delete failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Records

    private nonisolated static func record(_ trace: TaskTrace) -> TraceRecord {
        TraceRecord(
            id: trace.id,
            tabID: trace.tabID,
            prompt: trace.prompt,
            startedAt: trace.startedAt,
            response: trace.response,
            state: trace.state,
            finishedAt: trace.finishedAt
        )
    }

    private nonisolated static func steps(of trace: TaskTrace) -> [StepRecord] {
        trace.steps.enumerated().map { position, step in
            let links = (try? JSONEncoder().encode(step.links)) ?? Data()
            return StepRecord(
                id: step.id,
                traceID: trace.id,
                position: position,
                kind: step.kind,
                title: step.title,
                toolName: step.toolName,
                startedAt: step.startedAt,
                detail: step.detail,
                links: String(decoding: links, as: UTF8.self),
                state: step.state
            )
        }
    }

    private nonisolated static func step(from record: StepRecord) -> Step {
        Step(
            id: record.id,
            kind: record.kind,
            title: record.title,
            toolName: record.toolName,
            startedAt: record.startedAt,
            detail: record.detail,
            links: (try? JSONDecoder().decode(
                [ActivityLink].self,
                from: Data(record.links.utf8)
            )) ?? [],
            state: record.state
        )
    }

    private nonisolated static func record(_ usage: Usage, for tabID: UUID) -> UsageRecord {
        UsageRecord(
            tabID: tabID,
            requestCount: usage.requestCount,
            inputTokens: usage.inputTokens,
            cachedTokens: usage.cachedTokens,
            outputTokens: usage.outputTokens,
            estimatedContextTokens: usage.estimatedContextTokens
        )
    }

    private nonisolated static func usage(from record: UsageRecord) -> Usage {
        Usage(
            requestCount: record.requestCount,
            inputTokens: record.inputTokens,
            cachedTokens: record.cachedTokens,
            outputTokens: record.outputTokens,
            estimatedContextTokens: record.estimatedContextTokens
        )
    }

    private func finishRunningSteps(at traceIndex: Int, failed: Bool = false) {
        for stepIndex in traces[traceIndex].steps.indices
        where traces[traceIndex].steps[stepIndex].state == .running {
            traces[traceIndex].steps[stepIndex].state = failed ? .failed : .completed
        }
    }

    private static func trimmedDetail(_ detail: String, limit: Int = 5_000) -> String {
        guard detail.count > limit else { return detail }
        return String(detail.prefix(limit)) + "…"
    }
}
