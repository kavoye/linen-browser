// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import AVFoundation

nonisolated enum MicrophoneAccess {
    enum State: Equatable {
        case allowed
        case undecided
        case denied
    }

    static var state: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .allowed
        case .notDetermined:
            .undecided
        default:
            .denied
        }
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    @MainActor
    static func openSystemSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        guard let url = URL(string: pane) else { return }
        NSWorkspace.shared.open(url)
    }
}
