// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreAudio
import os

@MainActor
final class OutputDucker {
    static let duckedLevel: Float32 = 0.05

    private static let breadcrumbKey = "audio.duckedFrom"

    private var restoreAction: (() -> Void)?

    var isDucked: Bool {
        restoreAction != nil
    }

    static func restoreAfterUncleanExit() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.object(forKey: breadcrumbKey) as? Double else { return }
        defaults.removeObject(forKey: breadcrumbKey)
        guard let device = defaultOutputDevice() else { return }
        let elements = settableVolumeElements(on: device)
        for element in elements where (volume(of: device, element: element) ?? 1) <= duckedLevel + 0.001 {
            setVolume(Float32(saved), of: device, element: element)
        }
        Pipeline.log.notice("OutputDucker: restored output left ducked by a previous run")
    }

    func duck(to level: Float32 = OutputDucker.duckedLevel) {
        guard restoreAction == nil else { return }
        guard let device = Self.defaultOutputDevice() else { return }

        let elements = Self.settableVolumeElements(on: device)
        if !elements.isEmpty {
            let saved = elements.map { ($0, Self.volume(of: device, element: $0) ?? 1) }
            if let highest = saved.map(\.1).max(), highest > level {
                UserDefaults.standard.set(Double(highest), forKey: Self.breadcrumbKey)
            }
            for (element, current) in saved where current > level {
                Self.setVolume(level, of: device, element: element)
            }
            restoreAction = {
                for (element, previous) in saved {
                    Self.setVolume(previous, of: device, element: element)
                }
                UserDefaults.standard.removeObject(forKey: Self.breadcrumbKey)
            }
        } else if Self.isMuteSettable(on: device) {
            let wasMuted = Self.isMuted(device) ?? false
            Self.setMuted(true, on: device)
            restoreAction = { Self.setMuted(wasMuted, on: device) }
        }
    }

    func restore() {
        restoreAction?()
        restoreAction = nil
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else {
            Pipeline.log.error("OutputDucker: no default output device (status \(status))")
            return nil
        }
        return device
    }

    private static func settableVolumeElements(on device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        let candidates: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]
        let settable = candidates.filter { element in
            var address = volumeAddress(element)
            var isSettable = DarwinBoolean(false)
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr else {
                return false
            }
            return isSettable.boolValue
        }
        if settable.contains(kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return settable
    }

    private static func volumeAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static func volume(
        of device: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        var address = volumeAddress(element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func setVolume(
        _ value: Float32,
        of device: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) {
        var address = volumeAddress(element)
        var value = max(0, min(1, value))
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value
        )
        if status != noErr {
            Pipeline.log.error("OutputDucker: set volume failed (status \(status))")
        }
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func isMuteSettable(on device: AudioDeviceID) -> Bool {
        var address = muteAddress
        var isSettable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr else {
            return false
        }
        return isSettable.boolValue
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value != 0 : nil
    }

    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
        if status != noErr {
            Pipeline.log.error("OutputDucker: set mute failed (status \(status))")
        }
    }
}
