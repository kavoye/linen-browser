// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated protocol ContextWindowProbing: Sendable {
    func effectiveWindow(for provider: Provider, model: String) async -> Int?
}

nonisolated struct OllamaContextProbe: ContextWindowProbing {
    func effectiveWindow(for provider: Provider, model: String) async -> Int? {
        guard provider.id == "ollama",
              let api = Self.nativeAPIBase(of: provider),
              !model.isEmpty
        else { return nil }

        if let data = await fetch(api.appendingPathComponent("api/ps")),
           let running = Self.window(inRunningModels: data, model: model) {
            return running
        }
        guard let body = try? JSONSerialization.data(withJSONObject: ["model": model]),
              let data = await fetch(api.appendingPathComponent("api/show"), posting: body)
        else { return nil }
        return Self.window(inShowResponse: data)
    }

    static func nativeAPIBase(of provider: Provider) -> URL? {
        guard let baseURL = provider.baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else { return nil }
        if components.path.hasSuffix("/v1") {
            components.path.removeLast("/v1".count)
        }
        return components.url
    }

    static func window(inRunningModels data: Data, model: String) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return nil }

        let wanted = baseName(of: model)
        let match = models.first { entry in
            let name = entry["name"] as? String ?? entry["model"] as? String ?? ""
            return name == model || baseName(of: name) == wanted
        }
        return positiveInt(match?["context_length"])
    }

    static func window(inShowResponse data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parameters = json["parameters"] as? String
        else { return nil }

        for line in parameters.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.first == "num_ctx", fields.count >= 2 {
                return positiveInt(Int(fields[1]))
            }
        }
        return nil
    }

    private static func baseName(of model: String) -> String {
        model.split(separator: ":").first.map(String.init)?.lowercased() ?? model.lowercased()
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let number = value as? Int, number > 0 else { return nil }
        return number
    }

    private func fetch(_ url: URL, posting body: Data? = nil) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 3)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

nonisolated extension LLMSettings {
    private static func discoveredWindowKey(for provider: Provider, model: String) -> String {
        "llm.discoveredContextWindow.\(provider.id).\(model)"
    }

    static func discoveredContextWindow(for provider: Provider, model: String) -> Int? {
        let stored = defaults.integer(forKey: discoveredWindowKey(for: provider, model: model))
        return stored > 0 ? stored : nil
    }

    static func setDiscoveredContextWindow(_ tokens: Int?, for provider: Provider, model: String) {
        if let tokens, tokens > 0 {
            defaults.set(tokens, forKey: discoveredWindowKey(for: provider, model: model))
        } else {
            defaults.removeObject(forKey: discoveredWindowKey(for: provider, model: model))
        }
    }
}
