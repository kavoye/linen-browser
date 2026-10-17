// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@testable import Linen

final class EvalSpeech: SpeechOutput {
    var isMuted = true
    var onSpeakingChange: ((Bool) -> Void)?
    func speak(_ text: String) {}
    func stopSpeaking() {}
}

final class EvalGrantStorage: AgentGrantStorage {
    var grantData: Data?
}

nonisolated struct EvalCredentials: ProviderCredentialStore {
    let environmentKey: String
    func key(for provider: Provider) -> String? {
        ProcessInfo.processInfo.environment[environmentKey]
    }
    func isConfigured(_ provider: Provider) -> Bool {
        key(for: provider)?.isEmpty == false
    }
    func source(for provider: Provider) -> CredentialStore.Source {
        .environment(environmentKey)
    }
    func masked(for provider: Provider) -> String? {
        nil
    }
    func save(_ key: String, for provider: Provider) -> String? {
        "Read-only eval credentials"
    }
    func delete(for provider: Provider) {}
}
