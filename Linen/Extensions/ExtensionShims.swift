// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

nonisolated enum ExtensionShims {
    static let fileName = "linen-compat.js"
    static let gapsFileName = "linen-api-gaps.js"

    /// Everything a background-script package gets in front of its own scripts.
    static let source = backgroundSource + "\n" + gapsSource

    /// Stand-ins for Chrome APIs that WebKit does not provide. An extension that
    /// uses one without a guard throws when the script loads. In a background
    /// script that happens before the extension registers its listeners, so its
    /// popup and content scripts can never connect. The stand-in events never
    /// fire. The `privacy` settings stay absent, so a check for one still reads
    /// as unsupported. A native API is never replaced.
    static let gapsSource = """
    // linen-api-gaps
    (() => {
        "use strict";
        try {
            const silent = () => ({ addListener() {}, removeListener() {}, hasListener: () => false });
            const roots = [
                typeof browser === "object" ? browser : null,
                typeof chrome === "object" ? chrome : null,
            ];
            for (const api of new Set(roots)) {
                if (!api) {
                    continue;
                }
                api.privacy ||= { network: {}, services: {}, websites: {} };
                if (api.webNavigation) {
                    for (const name of ["onCreatedNavigationTarget", "onHistoryStateUpdated", "onReferenceFragmentUpdated", "onTabReplaced"]) {
                        api.webNavigation[name] ||= silent();
                    }
                }
            }
        } catch (e) {
        }
    })();
    """

    private static let gapsMarker = "// linen-api-gaps"
    private static let gapsTag = "<script src=\"/\(gapsFileName)\"></script>"

    private static let backgroundSource = """
    "use strict";
    try {
        if (!browser.notifications) {
            const silent = { addListener() {}, removeListener() {}, hasListener: () => false };
            browser.notifications = {
                create: async id => typeof id === "string" ? id : "",
                clear: async () => true,
                update: async () => false,
                getAll: async () => ({}),
                onClicked: silent, onClosed: silent, onButtonClicked: silent
            };
        }
        if (browser.permissions) {
            const contains = browser.permissions.contains.bind(browser.permissions);
            browser.permissions.contains = async query => {
                if (!browser.downloads && query?.permissions?.includes("downloads")) return false;
                try { return await contains(query) } catch { return false }
            };
            const request = browser.permissions.request.bind(browser.permissions);
            browser.permissions.request = async query => { try { return await request(query) } catch { return false } };
        }
        for (const action of new Set([browser.action, browser.browserAction])) {
            if (!action?.setIcon) continue;
            const setIcon = action.setIcon.bind(action);
            action.setIcon = (details, ...rest) => {
                if (details && "path" in details && "imageData" in details) {
                    details = { ...details };
                    if (details.path != null) delete details.imageData;
                    else delete details.path;
                }
                return setIcon(details, ...rest);
            };
        }
        if (browser.runtime && browser.runtime.onConnect) {
            const prefix = "linen-external:";
            const internal = new Set();
            const external = new Set();
            const connect = browser.runtime.onConnect;
            const connectExternal = browser.runtime.onConnectExternal;
            const deliver = browser.runtime.onConnect.addListener.bind(connect);
            connect.addListener = f => { internal.add(f); };
            connect.removeListener = f => { internal.delete(f); };
            connect.hasListener = f => internal.has(f);
            if (connectExternal) {
                connectExternal.addListener = f => { external.add(f); };
                connectExternal.removeListener = f => { external.delete(f); };
                connectExternal.hasListener = f => external.has(f);
            }
            deliver(port => {
                let targets = internal;
                let view = port;
                if (typeof port.name === "string" && port.name.startsWith(prefix)) {
                    // port.name is read-only, so the tag is hidden behind a view.
                    const real = port.name.slice(prefix.length);
                    view = new Proxy(port, {
                        get(target, key) {
                            if (key === "name") { return real; }
                            const value = Reflect.get(target, key, target);
                            return typeof value === "function" ? value.bind(target) : value;
                        }
                    });
                    if (external.size) {
                        targets = external;
                    }
                }
                for (const listener of Array.from(targets)) {
                    try {
                        listener(view);
                    } catch (error) {
                    }
                }
            });
        }
        if (browser.webRequest) {
            browser.webRequest.OnBeforeSendHeadersOptions ||= { EXTRA_HEADERS: "extraHeaders", REQUEST_HEADERS: "requestHeaders", BLOCKING: "blocking" };
            browser.webRequest.OnHeadersReceivedOptions ||= { EXTRA_HEADERS: "extraHeaders", RESPONSE_HEADERS: "responseHeaders", BLOCKING: "blocking" };
        }
    } catch (e) {
    }
    """

    @discardableResult
    static func ensureApplied(at package: URL) -> Bool {
        let manifestURL = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var background = root["background"] as? [String: Any],
              var scripts = background["scripts"] as? [String]
        else { return false }

        try? source.write(
            to: package.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
        let removedEmptyActionCommand = removeEmptyActionCommand(from: &root)
        guard scripts.first != fileName || removedEmptyActionCommand else { return true }

        scripts.removeAll { $0 == fileName }
        scripts.insert(fileName, at: 0)
        background["scripts"] = scripts
        root["background"] = background
        guard let updated = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return false }
        do {
            try updated.write(to: manifestURL, options: .atomic)
        } catch {
            return false
        }
        Pipeline.log.notice("Extension compatibility shim installed")
        return true
    }

    /// Puts the API stand-ins in front of code that `ensureApplied` cannot
    /// reach: a service worker, and the background, popup and options pages.
    /// Returns whether the package now carries them.
    @discardableResult
    static func ensureGapsApplied(at package: URL) -> Bool {
        let manifestURL = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }

        var covered = false
        var changed = false
        let background = root["background"] as? [String: Any]
        if let worker = (background?["service_worker"] as? String).flatMap({ file($0, in: package) }) {
            // A service worker is one script. A second classic script cannot run
            // ahead of it, so the stand-ins go at the start of the file itself.
            if let outcome = prependGaps(to: worker) {
                covered = true
                changed = changed || outcome
            }
        }

        let pages = declaredPages(in: root).compactMap { file($0, in: package) }
        if !pages.isEmpty {
            try? gapsSource.write(
                to: package.appendingPathComponent(gapsFileName),
                atomically: true,
                encoding: .utf8
            )
        }
        for page in pages {
            if let outcome = loadGaps(in: page) {
                covered = true
                changed = changed || outcome
            }
        }
        if changed {
            Pipeline.log.notice("Extension API stand-ins installed")
        }
        return covered
    }

    private static func declaredPages(in manifest: [String: Any]) -> [String] {
        var pages: [String] = []
        for action in ["action", "browser_action", "page_action"] {
            if let popup = (manifest[action] as? [String: Any])?["default_popup"] as? String {
                pages.append(popup)
            }
        }
        if let options = manifest["options_page"] as? String {
            pages.append(options)
        }
        if let options = (manifest["options_ui"] as? [String: Any])?["page"] as? String {
            pages.append(options)
        }
        if let page = (manifest["background"] as? [String: Any])?["page"] as? String {
            pages.append(page)
        }
        return pages
    }

    /// The manifest path as a file inside the package, or nil when the path is
    /// empty or leaves the package.
    private static func file(_ path: String, in package: URL) -> URL? {
        let relative = path.drop { $0 == "/" }
        guard !relative.isEmpty else { return nil }
        let root = package.standardizedFileURL.path
        let url = package.appendingPathComponent(String(relative)).standardizedFileURL
        guard url.path.hasPrefix(root + "/") else { return nil }
        return url
    }

    /// Nil when the file cannot be read or written; otherwise whether it changed.
    private static func prependGaps(to script: URL) -> Bool? {
        guard let text = try? String(contentsOf: script, encoding: .utf8) else { return nil }
        guard !text.hasPrefix(gapsMarker) else { return false }
        do {
            try (gapsSource + "\n" + text).write(to: script, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        return true
    }

    /// Nil when the page cannot be read or written; otherwise whether it changed.
    /// The tag goes before the page's own scripts: after the opening head tag,
    /// else before the first script tag, else at the start.
    private static func loadGaps(in page: URL) -> Bool? {
        guard var html = try? String(contentsOf: page, encoding: .utf8) else { return nil }
        guard !html.contains(gapsTag) else { return false }
        if let close = headTagEnd(in: html) {
            html.insert(contentsOf: gapsTag, at: close)
        } else if let script = html.range(of: "<script", options: .caseInsensitive) {
            html.insert(contentsOf: gapsTag, at: script.lowerBound)
        } else {
            html = gapsTag + html
        }
        do {
            try html.write(to: page, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        return true
    }

    /// The index after the `>` of the first `<head>` tag. `<header>` does not count.
    private static func headTagEnd(in html: String) -> String.Index? {
        var searchStart = html.startIndex
        while let open = html.range(of: "<head", options: .caseInsensitive, range: searchStart..<html.endIndex) {
            searchStart = open.upperBound
            guard open.upperBound < html.endIndex else { return nil }
            let next = html[open.upperBound]
            guard next == ">" || next.isWhitespace else { continue }
            return html.range(of: ">", range: open.upperBound..<html.endIndex)?.upperBound
        }
        return nil
    }

    private static func removeEmptyActionCommand(from manifest: inout [String: Any]) -> Bool {
        guard var commands = manifest["commands"] as? [String: Any] else { return false }
        let actions = manifest["manifest_version"] as? Int == 3
            ? ["action"] : ["browser_action", "page_action"]
        var changed = false
        for action in actions where manifest[action] is [String: Any] {
            let command = "_execute_" + action
            guard let definition = commands[command] as? [String: Any], definition.isEmpty else { continue }
            // WebKit supplies this unbound action command when it is omitted, but rejects an empty entry.
            commands.removeValue(forKey: command)
            changed = true
        }
        if changed { manifest["commands"] = commands }
        return changed
    }
}
