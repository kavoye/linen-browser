// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

nonisolated enum MediaPayload {
    static func audioReport(in message: String) -> Bool? {
        guard message.hasPrefix("audio:") else { return nil }
        return message.hasSuffix("1")
    }

    static func videoReport(in message: String) -> Bool? {
        guard message.hasPrefix("video:") else { return nil }
        return message.hasSuffix("1")
    }

    static func fields(in json: String) -> [String: Double]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Double]
    }

    static func point(in payload: String) -> CGPoint? {
        let parts = payload.split(separator: ",")
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1])
        else { return nil }
        return CGPoint(x: x, y: y)
    }

    static func rect(in json: String) -> CGRect? {
        guard let data = json.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              let x = fields["x"], let y = fields["y"],
              let width = fields["w"], let height = fields["h"],
              width > 0, height > 0
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
