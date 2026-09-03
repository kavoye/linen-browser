// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

nonisolated enum ExtensionShims {
    static let fileName = "linen-compat.js"

    static let source = """
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
            browser.permissions.contains = async query => { try { return await contains(query) } catch { return false } };
            const request = browser.permissions.request.bind(browser.permissions);
            browser.permissions.request = async query => { try { return await request(query) } catch { return false } };
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
        guard scripts.first != fileName else { return true }

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
        Pipeline.log.notice("ext: gave \(package.lastPathComponent, privacy: .public) the WebKit compat shim")
        return true
    }
}
