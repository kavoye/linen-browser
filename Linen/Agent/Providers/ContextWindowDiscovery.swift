// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated protocol ContextWindowProbing: Sendable {
    func effectiveWindow(for provider: Provider, model: String, apiKey: String?) async -> Int?
}

nonisolated struct OllamaContextProbe: ContextWindowProbing {
    func effectiveWindow(for provider: Provider, model: String, apiKey: String?) async -> Int? {
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

nonisolated struct ProviderContextProbe: ContextWindowProbing {
    func effectiveWindow(for provider: Provider, model: String, apiKey: String?) async -> Int? {
        guard !model.isEmpty, let baseURL = provider.baseURL else { return nil }
        if provider.id == "ollama" {
            return await OllamaContextProbe().effectiveWindow(for: provider, model: model, apiKey: apiKey)
        }

        switch provider.adapter {
        case .system:
            return nil
        case .anthropic:
            guard let apiKey else { return nil }
            var request = URLRequest(url: baseURL.appendingPathComponent("models").appendingPathComponent(model))
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return await fetchWindow(request)
        case .gemini:
            guard let apiKey,
                  var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
                  components.path.hasSuffix("/openai")
            else { return nil }
            components.path.removeLast("/openai".count)
            guard let nativeURL = components.url else { return nil }
            var request = URLRequest(url: nativeURL.appendingPathComponent("models").appendingPathComponent(model))
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            return await fetchWindow(request)
        case .openAIResponses, .openAICompatible:
            var request = URLRequest(url: baseURL.appendingPathComponent("models"))
            if let apiKey {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            if let data = await fetch(request),
               let window = Self.window(inModelList: data, model: model) {
                return window
            }
            if provider.baseURL?.host() == "api.openai.com" {
                return await documentedWindow(for: model)
            }
            request.url = baseURL.appendingPathComponent("models").appendingPathComponent(model)
            return await fetchWindow(request)
        }
    }

    static func window(inModel data: Data) -> Int? {
        guard let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return window(in: entry)
    }

    static func window(inModelList data: Data, model: String) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]]
        else { return nil }
        let entry = entries.first {
            ($0["id"] as? String) == model || ($0["name"] as? String) == "models/\(model)"
        }
        return entry.flatMap(window(in:))
    }

    static func window(inDocumentation data: Data) -> Int? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        let visible = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let pattern = #"([0-9][0-9,]*)\s+context window"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: visible, range: NSRange(visible.startIndex..., in: visible)),
              let range = Range(match.range(at: 1), in: visible)
        else { return nil }
        return positiveInt(String(visible[range]).replacingOccurrences(of: ",", with: ""))
    }

    private static func window(in entry: [String: Any]) -> Int? {
        for key in ["context_length", "context_window", "context_window_tokens", "max_context_length",
                    "max_model_len", "max_input_tokens", "inputTokenLimit", ] {
            if let window = positiveInt(entry[key]) {
                return window
            }
        }
        return nil
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        let number = value as? Int ?? (value as? String).flatMap(Int.init)
        guard let number, number >= 2_048 else { return nil }
        return number
    }

    private func documentedWindow(for model: String) async -> Int? {
        guard model.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://developers.openai.com/api/docs/models/\(model)")
        else { return nil }
        return await fetch(URLRequest(url: url)).flatMap(Self.window(inDocumentation:))
    }

    private func fetchWindow(_ request: URLRequest) async -> Int? {
        await fetch(request).flatMap(Self.window(inModel:))
    }

    private func fetch(_ request: URLRequest) async -> Data? {
        var request = request
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true
        else { return nil }
        return data
    }
}

nonisolated extension LLMSettings {
    private static func discoveredWindowKey(for provider: Provider, model: String) -> String {
        "llm.discoveredContextWindow.\(provider.id).\(provider.baseURL?.absoluteString ?? "").\(model)"
    }

    static func discoveredContextWindow(for provider: Provider, model: String) -> Int? {
        let key = discoveredWindowKey(for: provider, model: model)
        let checkedAt = defaults.double(forKey: "\(key).checkedAt")
        guard checkedAt > 0, Date().timeIntervalSince1970 - checkedAt < 86_400 else { return nil }
        let stored = defaults.integer(forKey: key)
        return stored > 0 ? stored : nil
    }

    static func setDiscoveredContextWindow(_ tokens: Int?, for provider: Provider, model: String) {
        let key = discoveredWindowKey(for: provider, model: model)
        if let tokens, tokens > 0 {
            defaults.set(tokens, forKey: key)
            defaults.set(Date().timeIntervalSince1970, forKey: "\(key).checkedAt")
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: "\(key).checkedAt")
        }
    }
}
