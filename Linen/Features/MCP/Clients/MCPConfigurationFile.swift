// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

nonisolated struct MCPConfigurationFile {
    static let maximumBytes = 8 * 1_024 * 1_024
    let url: URL
    let original: Data?
    private let inode: ino_t?

    init(url: URL) throws {
        self.url = url
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                original = nil
                inode = nil
                return
            }
            throw MCPClientSetupError.unsafeFile
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_nlink == 1, info.st_size <= Self.maximumBytes else { throw MCPClientSetupError.unsafeFile }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw MCPClientSetupError.unsafeFile }
        original = data
        inode = info.st_ino
    }

    func commit(_ replacement: Data) throws -> URL? {
        guard replacement.count <= Self.maximumBytes else { throw MCPClientSetupError.invalidConfiguration }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = parent.appending(path: ".linen-mcp-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.writePrivate(replacement, to: temporary)
        try ensureUnchanged()
        var backup: URL?
        if let original {
            let destination = parent.appending(path: url.lastPathComponent + ".linen-backup-" + UUID().uuidString)
            try Self.writePrivate(original, to: destination)
            backup = destination
        }
        try ensureUnchanged()
        let result = original == nil
            ? renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL))
            : rename(temporary.path, url.path)
        guard result == 0 else { throw MCPClientSetupError.fileAccess }
        return backup
    }

    private func ensureUnchanged() throws {
        let current = try Self(url: url)
        guard current.inode == inode, current.original == original else { throw MCPClientSetupError.changedFile }
    }

    static func writePrivate(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw MCPClientSetupError.fileAccess }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}
