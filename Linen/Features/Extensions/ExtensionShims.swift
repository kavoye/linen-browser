// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

nonisolated enum ExtensionShims {
    static let fileName = "linen-compat.js"
    static let pageFileName = "linen-compat-page.js"
    static let workerFileName = "linen-worker.js"

    private static let missingEvents = "["
        + ExtensionCompatibility.unsupportedMembers.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
        + "]"

    static let source = template.replacingOccurrences(of: relayFlag, with: "true")
    static let pageSource = template.replacingOccurrences(of: relayFlag, with: "false")

    private static let relayFlag = "LINEN_RELAY_EXTERNAL_CONNECTIONS"

    private static let template = """
    "use strict";
    try {
        const silent = { addListener() {}, removeListener() {}, hasListener: () => false };
        for (const member of \(missingEvents)) {
            const [namespace, event] = member.split(".");
            const api = browser[namespace];
            try { if (api && !api[event]) api[event] = silent; } catch {}
        }
        if (!browser.privacy && browser.runtime?.getManifest?.()?.permissions?.includes("privacy")) {
            browser.privacy = { network: {}, services: {}, websites: {} };
        }
        if (!browser.notifications) {
            browser.notifications = {
                create: async id => typeof id === "string" ? id : "",
                clear: async () => true,
                update: async () => false,
                getAll: async () => ({}),
                onClicked: silent, onClosed: silent, onButtonClicked: silent
            };
        }
        const answer = (args, value, error) => {
            const callback = typeof args[args.length - 1] === "function" ? args[args.length - 1] : null;
            if (callback) {
                Promise.resolve().then(() => callback(error ? undefined : value));
                return;
            }
            return error ? Promise.reject(error) : Promise.resolve(value);
        };
        if (browser.storage && !browser.storage.managed) {
            const readOnly = name => (...args) => answer(args, undefined, new Error(`storage.managed.${name}() isn't supported because managed storage is read-only.`));
            browser.storage.managed = {
                get: (...args) => answer(args, {}),
                getBytesInUse: (...args) => answer(args, 0),
                getKeys: (...args) => answer(args, []),
                set: readOnly("set"), remove: readOnly("remove"), clear: readOnly("clear"),
                onChanged: silent
            };
        }
        const unsupported = name => new Proxy({}, {
            get(target, key) {
                if (typeof key !== "string" || key === "then" || key === "toJSON") return undefined;
                if (!(key in target)) {
                    target[key] = /^on[A-Z]/.test(key)
                        ? silent
                        : (...args) => answer(args, undefined, new Error(`${name}.${key}() isn't supported in Linen.`));
                }
                return target[key];
            }
        });
        const notNamespaces = new Set([
            "activeTab", "background", "clipboardRead", "clipboardWrite", "declarativeNetRequestFeedback",
            "declarativeNetRequestWithHostAccess", "downloads", "downloads.open", "downloads.ui", "favicon",
            "geolocation", "identity.email", "nativeMessaging", "tabHide", "unlimitedStorage",
            "webRequestBlocking", "webRequestFilterResponse"
        ]);
        for (const permission of browser.runtime?.getManifest?.()?.permissions ?? []) {
            if (typeof permission !== "string" || notNamespaces.has(permission) || !/^[a-z][A-Za-z.]*$/.test(permission)) continue;
            const path = permission.split(".");
            const last = path.pop();
            try {
                let parent = browser;
                for (const part of path) parent = parent[part] ??= {};
                if (!parent[last]) parent[last] = unsupported(permission);
            } catch {}
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
        if (\(relayFlag) && browser.runtime && browser.runtime.onConnect) {
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
              var background = root["background"] as? [String: Any]
        else { return false }

        var changedBackground = false
        var shimmed = false
        if var scripts = background["scripts"] as? [String] {
            changedBackground = scripts.first != fileName
            scripts.removeAll { $0 == fileName }
            scripts.insert(fileName, at: 0)
            background["scripts"] = scripts
            shimmed = true
        }
        if let worker = background["service_worker"] as? String,
           let wrapper = wrapWorker(worker, isModule: background["type"] as? String == "module", in: package) {
            changedBackground = changedBackground || wrapper != worker
            background["service_worker"] = wrapper
            shimmed = true
        }
        guard shimmed else { return false }

        try? source.write(
            to: package.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
        let removedEmptyActionCommand = removeEmptyActionCommand(from: &root)
        guard changedBackground || removedEmptyActionCommand else { return true }

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

    @discardableResult
    static func ensurePagesApplied(at package: URL) -> Int {
        let root = package.resolvingSymlinksInPath().standardizedFileURL
        let manifest = (try? Data(contentsOf: root.appendingPathComponent("manifest.json")))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let backgroundPage = ((manifest?["background"] as? [String: Any])?["page"] as? String)
            .map { $0.split(separator: "/").filter { $0 != "." }.joined(separator: "/") }
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return 0 }

        var pages: [(url: URL, path: String)] = []
        for case let url as URL in files where ["html", "htm"].contains(url.pathExtension.lowercased()) {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            let base = root.path(percentEncoded: false)
            guard path.hasPrefix(base) else { continue }
            pages.append((url, String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        }
        guard !pages.isEmpty else { return 0 }

        try? source.write(to: root.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        try? pageSource.write(to: root.appendingPathComponent(pageFileName), atomically: true, encoding: .utf8)
        var changed = 0
        for page in pages {
            guard let html = try? String(contentsOf: page.url, encoding: .utf8),
                  let updated = inserting(script: page.path == backgroundPage ? fileName : pageFileName, into: html),
                  (try? updated.write(to: page.url, atomically: true, encoding: .utf8)) != nil
            else { continue }
            changed += 1
        }
        return changed
    }

    static func inserting(script file: String, into html: String) -> String? {
        let tag = "<script src=\"/\(file)\"></script>"
        guard !html.contains(tag) else { return nil }
        for pattern in [#"<head(\s[^>]*)?>"#, #"<html(\s[^>]*)?>"#, #"<!doctype[^>]*>"#] {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                var updated = html
                updated.insert(contentsOf: tag, at: range.upperBound)
                return updated
            }
        }
        return tag + html
    }

    private static func wrapWorker(_ worker: String, isModule: Bool, in package: URL) -> String? {
        var directories = worker.split(separator: "/").map(String.init).filter { $0 != "." }
        guard let name = directories.popLast(), !directories.contains("..") else { return nil }
        guard name != workerFileName else { return worker }

        let shim = (directories.isEmpty ? "./" : String(repeating: "../", count: directories.count)) + fileName
        guard let shimLiteral = literal(shim), let workerLiteral = literal("./" + name) else { return nil }
        let wrapper = isModule
            ? "import \(shimLiteral);\nimport \(workerLiteral);\n"
            : "importScripts(\(shimLiteral), \(workerLiteral));\n"
        let path = (directories + [workerFileName]).joined(separator: "/")
        do {
            try wrapper.write(to: package.appendingPathComponent(path), atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        return path
    }

    private static func literal(_ text: String) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: text,
            options: [.fragmentsAllowed, .withoutEscapingSlashes]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
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
