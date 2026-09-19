// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum SafariCardImport {
    static let maximumJSONBytes = 2 * 1024 * 1024

    struct Result: Sendable {
        let cards: [PaymentCard]
        let skipped: Int
    }

    static func decode(_ data: Data) throws -> Result {
        guard data.count <= maximumJSONBytes else { throw PaymentCardError.tooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["payment_cards"] as? [[String: Any]]
        else { throw PaymentCardError.invalidExport }
        if let metadata = root["metadata"] as? [String: Any],
           let kind = metadata["data_type"] as? String, kind != "payment_cards" {
            throw PaymentCardError.invalidExport
        }
        guard records.count <= 500 else { throw PaymentCardError.tooLarge }
        var cards: [PaymentCard] = []
        var skipped = 0
        for record in records {
            guard let number = record["card_number"] as? String,
                  let card = try? PaymentCard(
                    number: number,
                    cardholder: record["cardholder_name"] as? String ?? "",
                    month: record["card_expiration_month"] as? Int,
                    year: record["card_expiration_year"] as? Int
                  ) else {
                skipped += 1
                continue
            }
            cards = PaymentCard.merging([card], into: cards)
        }
        return Result(cards: cards, skipped: skipped)
    }

    static func read(_ file: URL) throws -> Result {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if file.pathExtension.lowercased() != "zip" {
            guard size <= maximumJSONBytes else { throw PaymentCardError.tooLarge }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            return try decode(handle.read(upToCount: maximumJSONBytes + 1) ?? Data())
        }
        guard size <= 256 * 1024 * 1024 else { throw PaymentCardError.tooLarge }
        let listing = try unzip(["-Z1", file.path], limit: 256 * 1024)
        guard let names = String(data: listing, encoding: .utf8) else { throw PaymentCardError.invalidExport }
        let entries = names.split(whereSeparator: \.isNewline).map(String.init).filter {
            $0.lowercased().hasSuffix(".json") && !$0.hasPrefix("__MACOSX/")
        }.sorted {
            let left = $0.lowercased().contains("paymentcards")
            let right = $1.lowercased().contains("paymentcards")
            return left == right ? $0 < $1 : left
        }
        guard entries.count <= 64 else { throw PaymentCardError.tooLarge }
        for entry in entries {
            guard !entry.hasPrefix("-"), !entry.contains(where: { "*?[]\\".contains($0) }) else { continue }
            guard let data = try? unzip(["-p", file.path, entry], limit: maximumJSONBytes) else { continue }
            if let result = try? decode(data) {
                return result
            }
        }
        throw PaymentCardError.invalidExport
    }

    private static func unzip(_ arguments: [String], limit: Int) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { try? pipe.fileHandleForReading.close() }
        var result = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard result.count + chunk.count <= limit else {
                process.terminate()
                try? pipe.fileHandleForReading.close()
                process.waitUntilExit()
                throw PaymentCardError.tooLarge
            }
            result.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PaymentCardError.invalidExport }
        return result
    }
}
