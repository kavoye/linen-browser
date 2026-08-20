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
        var destination: URL?
        var bytesReceived: Int64 = 0
        var bytesExpected: Int64 = 0
        var state: State = .running
        var isResumable = false
        let started = Date()

        var isRunning: Bool {
            state == .running
        }

        var fraction: Double? {
            guard bytesExpected > 0 else { return nil }
            return min(1, Double(bytesReceived) / Double(bytesExpected))
        }
    }

    private(set) var items: [Item] = []

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

    init(destinationFolder: URL? = nil, asksWhereToSave: Bool? = nil) {
        destinationFolderOverride = destinationFolder
        asksWhereToSaveOverride = asksWhereToSave
        super.init()
    }

    private static let capacity = 40

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

    func adopt(_ download: WKDownload, suggestedSource: URL?, sourceTabID: UUID? = nil) {
        let id = beginItem(
            source: suggestedSource ?? download.originalRequest?.url,
            sourceTabID: sourceTabID
        )
        attach(download, to: id)
    }

    @discardableResult
    func beginItem(source: URL?, sourceTabID: UUID? = nil) -> UUID {
        let id = UUID()
        items.insert(
            Item(
                id: id,
                filename: source?.lastPathComponent ?? "Download",
                source: source?.host() ?? "",
                sourceTabID: sourceTabID
            ),
            at: 0
        )
        if items.count > Self.capacity {
            if let index = items.lastIndex(where: { !$0.isRunning }) {
                items.remove(at: index)
            }
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
