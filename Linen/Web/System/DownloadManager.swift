// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import os
import WebKit

@Observable
final class DownloadManager: NSObject {
    struct Item: Identifiable, Equatable {
        enum State: Equatable {
            case running
            case finished
            case interrupted(String)
            case failed(String)
            case cancelled
        }

        let id: UUID
        var filename: String
        var source: String
        let sourceTabID: UUID?
        var isPrivate = false
        var destination: URL?
        var bytesReceived: Int64 = 0
        var bytesExpected: Int64 = 0
        var state: State = .running
        var isResumable = false
        let started: Date

        init(
            id: UUID,
            filename: String,
            source: String,
            sourceTabID: UUID?,
            isPrivate: Bool = false,
            started: Date = Date()
        ) {
            self.id = id
            self.filename = filename
            self.source = source
            self.sourceTabID = sourceTabID
            self.isPrivate = isPrivate
            self.started = started
        }

        var isRunning: Bool {
            state == .running
        }

        var fraction: Double? {
            guard bytesExpected > 0 else { return nil }
            return min(1, Double(bytesReceived) / Double(bytesExpected))
        }
    }

    private(set) var items: [Item] = [] {
        didSet { scheduleWrite() }
    }

    @ObservationIgnored var onFinished: ((String) -> Void)?

    @ObservationIgnored private var live: [UUID: WKDownload] = [:]
    @ObservationIgnored private var identifiers: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var observations: [UUID: NSKeyValueObservation] = [:]
    @ObservationIgnored private var origins: [UUID: URL] = [:]
    @ObservationIgnored private var resumeData: [UUID: Data] = [:]
    @ObservationIgnored private var resuming: Set<UUID> = []

    @ObservationIgnored var webViewProvider: (() -> WKWebView?)?

    @ObservationIgnored private let destinationFolderOverride: URL?
    @ObservationIgnored private let asksWhereToSaveOverride: Bool?
    @ObservationIgnored private let file: URL?
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(destinationFolder: URL? = nil, asksWhereToSave: Bool? = nil, file: URL? = nil) {
        destinationFolderOverride = destinationFolder
        asksWhereToSaveOverride = asksWhereToSave
        self.file = file ?? Self.defaultFile
        super.init()
        items = Self.read(from: self.file)
        writeTask?.cancel()
        writeTask = nil
    }

    static var defaultFile: URL? {
        guard !AppDatabase.isRunningTests, AppDatabase.ownsSession else { return nil }
        return AppDatabase.supportDirectory.appendingPathComponent("Downloads.json")
    }

    /// A ceiling the list is not meant to reach: what it keeps is decided by
    /// `DownloadRetention`, and this only stops a runaway file.
    private static let capacity = 1000

    func apply(_ retention: DownloadRetention, now: Date = Date()) {
        guard let age = retention.maximumAge else { return }
        let cutoff = now.addingTimeInterval(-age)
        let stale = items.filter { !$0.isRunning && $0.started < cutoff }
        guard !stale.isEmpty else { return }
        for item in stale {
            finish(item.id)
        }
        items.removeAll { !$0.isRunning && $0.started < cutoff }
    }

    func clearOnQuitIfNeeded(_ retention: DownloadRetention) {
        guard retention == .onQuit else { return }
        clearFinished()
        writeNow()
    }

    private func scheduleWrite() {
        guard file != nil else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    func writeNow() {
        writeTask?.cancel()
        writeTask = nil
        write()
    }

    private func write() {
        guard let file else { return }
        let kept = items.filter { !$0.isPrivate }.prefix(Self.capacity).map(StoredDownload.init)
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(Array(kept)).write(to: file, options: .atomic)
        } catch {
            Pipeline.log.error("downloads: writing the list failed: \(error, privacy: .public)")
        }
    }

    private static func read(from file: URL?) -> [Item] {
        guard let file, let data = try? Data(contentsOf: file) else { return [] }
        guard let stored = try? JSONDecoder().decode([StoredDownload].self, from: data) else {
            Pipeline.log.error("downloads: the list on disk could not be read")
            return []
        }
        return stored.map(\.item)
    }

    var activeCount: Int {
        items.filter(\.isRunning).count
    }

    var hasRecent: Bool {
        items.contains { $0.isRunning || $0.started > Date().addingTimeInterval(-Self.recentWindow) }
    }

    var activeFraction: Double {
        let running = items.filter(\.isRunning)
        guard !running.isEmpty else { return 0 }
        return running.reduce(0.0) { $0 + ($1.fraction ?? 0.5) } / Double(running.count)
    }

    private static let recentWindow: TimeInterval = 6 * 60 * 60

    // MARK: - Taking a download

    func adopt(
        _ download: WKDownload,
        suggestedSource: URL?,
        sourceTabID: UUID? = nil,
        privately: Bool = false
    ) {
        let id = beginItem(
            source: suggestedSource ?? download.originalRequest?.url,
            sourceTabID: sourceTabID,
            privately: privately
        )
        attach(download, to: id)
    }

    @ObservationIgnored var onBegin: (() -> Void)?

    @discardableResult
    func beginItem(source: URL?, sourceTabID: UUID? = nil, privately: Bool = false) -> UUID {
        onBegin?()
        let id = UUID()
        items.insert(
            Item(
                id: id,
                filename: source?.lastPathComponent ?? "Download",
                source: source?.host() ?? "",
                sourceTabID: sourceTabID,
                isPrivate: privately
            ),
            at: 0
        )
        if items.count > Self.capacity, let index = items.lastIndex(where: { !$0.isRunning }) {
            items.remove(at: index)
        }
        origins[id] = source
        return id
    }

    #if DEBUG
    func stage(_ staged: [StageSet.StagedDownload]) {
        items.removeAll()
        origins.removeAll()
        for entry in staged.reversed() {
            let id = beginItem(source: URL(string: "https://\(entry.host)/\(entry.filename)"))
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            items[index].bytesExpected = entry.bytes
            items[index].bytesReceived = entry.finished ? entry.bytes : entry.bytes * 2 / 5
            items[index].state = entry.finished ? .finished : .running
            items[index].destination = URL.downloadsDirectory.appending(path: entry.filename)
        }
    }
    #endif

    func hasActiveDownload(for tabID: UUID) -> Bool {
        items.contains { $0.sourceTabID == tabID && $0.isRunning }
    }

    private func attach(_ download: WKDownload, to id: UUID) {
        live[id] = download
        identifiers[ObjectIdentifier(download)] = id
        download.delegate = self

        let progress = download.progress
        observations[id] = progress.observe(\.completedUnitCount, options: [.new]) { [weak self] progress, _ in
            let received = progress.completedUnitCount
            let expected = progress.totalUnitCount
            Task { @MainActor [weak self] in
                self?.noteProgress(received: received, expected: expected, for: id)
            }
        }
    }

    func cancel(_ item: Item) {
        guard let download = live[item.id] else { return }
        let id = item.id
        noteCancelRequested(id)
        download.cancel { data in
            Task { @MainActor [weak self] in
                self?.noteCancellation(id, resumeData: data)
            }
        }
    }

    func resume(_ item: Item) {
        guard let data = resumeData[item.id], let webView = webViewProvider?() else { return }
        let id = item.id
        noteResumeStarted(id)
        webView.resumeDownload(fromResumeData: data) { download in
            Task { @MainActor [weak self] in
                self?.attach(download, to: id)
            }
        }
    }

    // MARK: - What a row becomes

    func noteFailure(_ id: UUID, reason: String, resumeData: Data?) {
        if let resumeData {
            self.resumeData[id] = resumeData
        }
        let resumable = self.resumeData[id] != nil
        update(id) {
            guard $0.state == .running else { return }
            $0.state = resumable ? .interrupted(reason) : .failed(reason)
            $0.isResumable = resumable
        }
        finish(id, keepingResumeState: resumable)
    }

    func noteCancelRequested(_ id: UUID) {
        update(id) { $0.state = .cancelled }
    }

    func noteCancellation(_ id: UUID, resumeData: Data?) {
        if let resumeData {
            self.resumeData[id] = resumeData
        }
        let resumable = self.resumeData[id] != nil
        update(id) { $0.isResumable = resumable }
        finish(id, keepingResumeState: resumable)
    }

    func noteDestination(_ destination: URL, expectedLength: Int64, for id: UUID) {
        update(id) {
            $0.filename = destination.lastPathComponent
            $0.destination = destination
            $0.bytesExpected = max(0, expectedLength)
        }
    }

    func noteProgress(received: Int64, expected: Int64, for id: UUID) {
        update(id) {
            $0.bytesReceived = received
            $0.bytesExpected = max(0, expected)
        }
    }

    func holdsResumeState(for id: UUID) -> Bool {
        resumeData[id] != nil
    }

    func noteResumeStarted(_ id: UUID) {
        resuming.insert(id)
        update(id) {
            $0.state = .running
            $0.isResumable = false
        }
    }

    func reusableDestination(for id: UUID) -> URL? {
        guard resuming.remove(id) != nil else { return nil }
        return items.first { $0.id == id }?.destination
    }

    func canResume(_ item: Item) -> Bool {
        item.isResumable && resumeData[item.id] != nil && webViewProvider?() != nil
    }

    func remove(_ item: Item) {
        guard !item.isRunning else { return }
        finish(item.id)
        items.removeAll { $0.id == item.id }
    }

    func forgetPrivateDownloads() {
        for item in items where item.isPrivate {
            if item.isRunning {
                cancel(item)
            }
            finish(item.id)
        }
        items.removeAll(where: \.isPrivate)
    }

    func clearFinished() {
        for item in items where !item.isRunning {
            finish(item.id)
        }
        items.removeAll { !$0.isRunning }
    }

    func revealInFinder(_ item: Item) {
        guard let destination = item.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func open(_ item: Item) {
        guard let destination = item.destination, item.state == .finished else { return }
        NSWorkspace.shared.open(destination)
    }

    // MARK: - Bookkeeping

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func finish(_ id: UUID, keepingResumeState: Bool = false) {
        if let download = live.removeValue(forKey: id) {
            identifiers.removeValue(forKey: ObjectIdentifier(download))
        }
        observations.removeValue(forKey: id)?.invalidate()
        guard !keepingResumeState else { return }
        origins.removeValue(forKey: id)
        resumeData.removeValue(forKey: id)
        resuming.remove(id)
    }

    private func id(for download: WKDownload) -> UUID? {
        identifiers[ObjectIdentifier(download)]
    }

    // MARK: - Where the file goes

    nonisolated static func safeFilename(_ suggested: String) -> String {
        var name = suggested
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        if name.utf8.count > 200 {
            name = String(name.prefix(200))
        }
        return name.isEmpty ? "Download" : name
    }

    private func uniqueDestination(for filename: String, in folder: URL) -> URL {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let candidate = folder.appending(path: Self.safeFilename(filename))
        guard manager.fileExists(atPath: candidate.path(percentEncoded: false)) else { return candidate }

        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for index in 2...999 {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let next = folder.appending(path: name)
            if !manager.fileExists(atPath: next.path(percentEncoded: false)) {
                return next
            }
        }
        return candidate
    }

    /// A sheet, not `runModal()`. A nested event loop re-enters main-actor work
    /// and wedges when a second download starts under the first panel.
    private func askWhereToSave(_ filename: String, in folder: URL, on window: NSWindow?) async -> URL? {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save File")
        panel.nameFieldStringValue = Self.safeFilename(filename)
        panel.directoryURL = folder
        panel.canCreateDirectories = true

        guard let window else {
            return panel.runModal() == .OK ? panel.url : nil
        }
        let response = await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }
}

// MARK: - WKDownloadDelegate

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        if let id = id(for: download), let existing = reusableDestination(for: id) {
            return existing
        }

        let settings = BrowserSettings.shared
        let name = suggestedFilename.isEmpty ? "Download" : suggestedFilename
        let folder = destinationFolderOverride ?? settings.downloadFolder
        let asksWhereToSave = asksWhereToSaveOverride ?? settings.asksWhereToSave

        let destination = asksWhereToSave
            ? await askWhereToSave(name, in: folder, on: download.webView?.window)
            : uniqueDestination(for: name, in: folder)

        guard let destination else {
            if let id = id(for: download) {
                update(id) { $0.state = .cancelled }
                finish(id)
            }
            return nil
        }

        if let id = id(for: download) {
            noteDestination(destination, expectedLength: response.expectedContentLength, for: id)
        }
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = id(for: download) else { return }
        var filename = ""
        var destination: URL?
        update(id) {
            $0.state = .finished
            if let fraction = $0.fraction, fraction < 1 {
                $0.bytesReceived = $0.bytesExpected
            }
            filename = $0.filename
            destination = $0.destination
        }
        if let destination {
            Self.quarantine(destination, from: origins[id])
        }
        finish(id)
        onFinished?(filename)
    }

    private static func quarantine(_ file: URL, from source: URL?) {
        var file = file
        var properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload,
            kLSQuarantineAgentNameKey as String: "Linen",
        ]
        if let source {
            properties[kLSQuarantineDataURLKey as String] = source
            properties[kLSQuarantineOriginURLKey as String] = source
        }
        var values = URLResourceValues()
        values.quarantineProperties = properties
        try? file.setResourceValues(values)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let id = id(for: download) else { return }
        noteFailure(id, reason: error.localizedDescription, resumeData: resumeData)
        Pipeline.log.error("download failed: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - Formatting

extension DownloadManager.Item {
    private static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    var sizeSummary: String {
        switch state {
        case .running where bytesExpected > 0:
            return String(localized: "\(Self.size(bytesReceived)) of \(Self.size(bytesExpected))")
        case .running:
            return Self.size(bytesReceived)
        case .finished:
            return Self.size(max(bytesReceived, bytesExpected))
        case .cancelled:
            return String(localized: "Canceled")
        case .interrupted:
            let received = Self.size(bytesReceived)
            guard bytesExpected > 0 else {
                return String(localized: "Stopped at \(received)")
            }
            return String(localized: "Stopped at \(received) of \(Self.size(bytesExpected))")
        case .failed(let why):
            return why
        }
    }

    var stoppedReason: String? {
        switch state {
        case .interrupted(let why), .failed(let why):
            why
        default:
            nil
        }
    }
}

enum DownloadRetention: String, CaseIterable, Identifiable {
    case afterOneDay
    case onQuit
    case manually

    var id: String {
        rawValue
    }

    var label: LocalizedStringResource {
        switch self {
        case .afterOneDay:
            "After one day"
        case .onQuit:
            "When Linen quits"
        case .manually:
            "Manually"
        }
    }

    var maximumAge: TimeInterval? {
        self == .afterOneDay ? 86_400 : nil
    }
}

private struct StoredDownload: Codable {
    enum Outcome: String, Codable {
        case finished
        case interrupted
        case failed
        case cancelled
    }

    let id: UUID
    let filename: String
    let source: String
    let destination: URL?
    let bytesReceived: Int64
    let bytesExpected: Int64
    let outcome: Outcome
    let reason: String?
    let started: Date

    init(_ item: DownloadManager.Item) {
        id = item.id
        filename = item.filename
        source = item.source
        destination = item.destination
        bytesReceived = item.bytesReceived
        bytesExpected = item.bytesExpected
        started = item.started
        switch item.state {
        case .finished:
            outcome = .finished
            reason = nil
        case .interrupted(let why):
            outcome = .interrupted
            reason = why
        case .failed(let why):
            outcome = .failed
            reason = why
        case .cancelled:
            outcome = .cancelled
            reason = nil
        case .running:
            outcome = .interrupted
            reason = String(localized: "Linen closed before this finished")
        }
    }

    var item: DownloadManager.Item {
        var restored = DownloadManager.Item(
            id: id,
            filename: filename,
            source: source,
            sourceTabID: nil,
            started: started
        )
        restored.destination = destination
        restored.bytesReceived = bytesReceived
        restored.bytesExpected = bytesExpected
        switch outcome {
        case .finished:
            restored.state = .finished
        case .interrupted:
            restored.state = .interrupted(reason ?? String(localized: "This download did not finish"))
        case .failed:
            restored.state = .failed(reason ?? String(localized: "This download failed"))
        case .cancelled:
            restored.state = .cancelled
        }
        return restored
    }
}
