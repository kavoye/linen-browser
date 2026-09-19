// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated struct OpenAIPresentation: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Identifiable, Sendable {
        var id: String {
            url.absoluteString
        }
        let title: String
        let url: URL
    }
    struct Picture: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let data: Data
        let format: String
    }
    struct File: Codable, Equatable, Identifiable, Sendable {
        var id: String {
            (containerID ?? "") + "/" + fileID
        }
        let fileID: String
        let containerID: String?
        let name: String
    }
    var sources: [Source] = []
    var pictures: [Picture] = []
    var files: [File] = []
    var summaries: [String] = []

    mutating func append(_ response: OpenAIJSON) {
        for item in response["output"].array ?? [] {
            if item["type"] == "reasoning" {
                summaries += (item["summary"].array ?? []).compactMap { $0["text"].string }
            }
            if item["type"] == "image_generation_call", let id = item["id"].string,
                let encoded = item["result"].string, let data = Data(base64Encoded: encoded), !pictures.contains(where: { $0.id == id }) {
                let format = item["output_format"].string ?? "png"
                pictures.append(.init(id: id, data: data, format: ["png", "jpeg", "webp"].contains(format) ? format : "png"))
            }
            for part in item["content"].array ?? [] {
                for annotation in part["annotations"].array ?? [] {
                    if annotation["type"] == "url_citation", let raw = annotation["url"].string,
                        let url = URL(string: raw), ["https", "http"].contains(url.scheme), url.host != nil,
                        !sources.contains(where: { $0.url == url }) {
                        sources.append(.init(title: annotation["title"].string ?? url.host() ?? raw, url: url))
                    }
                    if ["file_citation", "container_file_citation", "file_path"].contains(annotation["type"].string ?? ""),
                        let id = annotation["file_id"].string {
                        let file = File(
                            fileID: id, containerID: annotation["container_id"].string, name: annotation["filename"].string ?? "OpenAI file"
                        )
                        if !files.contains(where: {
                            $0.id == file.id }) { files.append(file)
                        }
                    }
                }
            }
        }
    }
}
