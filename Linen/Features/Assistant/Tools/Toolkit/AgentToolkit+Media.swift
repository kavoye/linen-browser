// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

extension AgentToolkit {
    func playVideo(topic: String) async -> String {
        let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let step = beginTool(name: "playVideo")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard !topic.isEmpty else {
            let output = "Enter a video topic."
            completeTool(step, failed: true)
            return output
        }
        let resolved = await services.resolveVideo(topic)
        if let output = cancellationOutput(for: step) {
            return output
        }
        if let videoID = resolved.videoID, let watch = Self.watchURL(videoID: videoID) {
            let tab = browser.newTab(url: watch, activate: !media.isEnabled, transition: .agent)
            adoptOpened(tab)
            media.controlTab(
                webView: tab.webView,
                title: topic,
                tabID: tab.id,
                artwork: MediaCenter.poster(forPage: watch.absoluteString)
            )
            let output = media.isEnabled
                ? "Opened the video in the browser's media player. Check playback before reporting that it is playing."
                : "Opened it in a tab. The media player is off in Settings."
            completeTool(step)
            return output
        }
        guard let fallbackURL = Self.webURL(resolved.fallbackURL) else {
            let output = "Couldn’t open an unsafe video result."
            completeTool(step, failed: true)
            return output
        }
        let fallbackTab = browser.newTab(url: fallbackURL, transition: .agent)
        adoptOpened(fallbackTab)
        let output = "Couldn't resolve a video directly; opened the results in a tab instead."
        completeTool(step)
        return output
    }

    func closeVideo() -> String {
        let step = beginTool(name: "closeVideo")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard media.model.isActive else {
            let output = "No media is playing."
            completeTool(step, failed: true)
            return output
        }
        media.close()
        let output = "Paused it and closed the media player. Its tab is still open."
        completeTool(step)
        return output
    }

    func controlMedia(action: String) -> String {
        let step = beginTool(name: "controlMedia")
        if let output = cancellationOutput(for: step) {
            return output
        }
        guard media.model.isActive else {
            let output = "No media is playing."
            completeTool(step, failed: true)
            return output
        }
        let output: String
        switch action {
        case "pip":
            if media.model.isInNativePiP {
                output = "Already in Picture in Picture."
            } else {
                media.toggleNativePiP()
                output = "Moving into Picture in Picture."
            }
        case "exitPip":
            if media.model.isInNativePiP {
                media.toggleNativePiP()
                output = "Back in the media player."
            } else {
                output = "Not in Picture in Picture."
            }
        case "expand", "collapse":
            output = "The player has one size now. Try Picture in Picture for a bigger view."
        default:
            output = "Unknown media action."
        }
        completeTool(step, failed: output == "Unknown media action.")
        return output
    }

    nonisolated static func webURL(_ url: URL) -> URL? {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    nonisolated static func isVideoIDCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
    }

    nonisolated static func watchURL(videoID: String) -> URL? {
        guard videoID.count == 11, videoID.allSatisfy(Self.isVideoIDCharacter) else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/watch")
        components?.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components?.url
    }
}
