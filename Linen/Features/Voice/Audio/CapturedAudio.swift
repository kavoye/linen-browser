// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AVFAudio

nonisolated struct CapturedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}
