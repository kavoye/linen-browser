// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

nonisolated enum ExtensionExternalConnect {
    static let relayFileName = "linen-external.js"
    static let portPrefix = "linen-external:"

    static let pageScript = #"""
    (() => {
      "use strict";
      const marker = "linenExternalConnectable";
      const root = document.documentElement;
      const origin = window.location.origin === "null" ? "*" : window.location.origin;
      const ports = new Map();
      const replies = new Map();
      let counter = 0;

      function listeners() {
        const set = new Set();
        return {
          addListener: f => { set.add(f); },
          removeListener: f => { set.delete(f); },
          hasListener: f => set.has(f),
          fire: (...args) => {
            for (const f of Array.from(set)) {
              try { f(...args); } catch (error) { setTimeout(() => { throw error; }); }
            }
          }
        };
      }

      function connectable(extensionId) {
        return (root.dataset[marker] || "").split(",").includes(extensionId);
      }

      function connect(extensionId, info) {
        if (typeof extensionId !== "string") { info = extensionId; extensionId = undefined; }
        const id = "linen-" + (++counter) + "-" + Math.random().toString(36).slice(2);
        const port = { name: (info && info.name) || "", onMessage: listeners(), onDisconnect: listeners() };
        let open = true;
        const close = error => {
          if (!open) { return; }
          open = false;
          ports.delete(id);
          window.chrome.runtime.lastError = error ? { message: error } : undefined;
          port.onDisconnect.fire(port);
          window.chrome.runtime.lastError = undefined;
        };
        port.postMessage = message => {
          if (!open) { throw new Error("Attempting to use a disconnected port object"); }
          window.postMessage({ linenExternal: "post", port: id, message }, origin);
        };
        port.disconnect = () => {
          if (!open) { return; }
          open = false;
          ports.delete(id);
          window.postMessage({ linenExternal: "disconnect", port: id }, origin);
        };
        ports.set(id, { port, close });
        if (!extensionId || !connectable(extensionId)) {
          setTimeout(() => close("Could not establish connection. Receiving end does not exist."), 0);
          return port;
        }
        window.postMessage({ linenExternal: "connect", port: id, extensionId, name: port.name }, origin);
        return port;
      }

      function sendMessage(extensionId, message, options, callback) {
        if (typeof options === "function") { callback = options; options = undefined; }
        if (typeof extensionId !== "string" || !connectable(extensionId)) {
          const error = "Could not establish connection. Receiving end does not exist.";
          if (callback) { setTimeout(() => { window.chrome.runtime.lastError = { message: error }; callback(); window.chrome.runtime.lastError = undefined; }, 0); return; }
          return Promise.reject(new Error(error));
        }
        const requestId = "linen-" + (++counter) + "-" + Math.random().toString(36).slice(2);
        const promise = new Promise((resolve, reject) => { replies.set(requestId, { resolve, reject }); });
        window.postMessage({ linenExternal: "send", requestId, extensionId, message }, origin);
        if (callback) {
          promise.then(callback, error => { window.chrome.runtime.lastError = { message: String(error && error.message || error) }; callback(); window.chrome.runtime.lastError = undefined; });
          return;
        }
        return promise;
      }

      function install() {
        const chrome = window.chrome = window.chrome || {};
        const runtime = chrome.runtime = chrome.runtime || {};
        if (!runtime.connect) { runtime.connect = connect; }
        if (!runtime.sendMessage) { runtime.sendMessage = sendMessage; }
        if (!("lastError" in runtime)) { runtime.lastError = undefined; }
      }

      window.addEventListener("message", event => {
        if (event.source !== window) { return; }
        const data = event.data;
        if (!data || typeof data !== "object" || typeof data.linenExternal !== "string") { return; }
        if (data.linenExternal === "message") {
          const entry = ports.get(data.port);
          if (entry) { entry.port.onMessage.fire(data.message, entry.port); }
        } else if (data.linenExternal === "disconnected") {
          const entry = ports.get(data.port);
          if (entry) { entry.close(data.error); }
        } else if (data.linenExternal === "reply") {
          const pending = replies.get(data.requestId);
          if (!pending) { return; }
          replies.delete(data.requestId);
          if (data.error) { pending.reject(new Error(data.error)); } else { pending.resolve(data.response); }
        }
      });

      if (root.dataset[marker]) {
        install();
        return;
      }
      const observer = new MutationObserver(() => {
        if (!root.dataset[marker]) { return; }
        observer.disconnect();
        install();
      });
      observer.observe(root, { attributes: true, attributeFilter: ["data-linen-external-connectable"] });
    })();
    """#

    static let relayScript = #"""
    (() => {
      "use strict";
      const api = globalThis.browser ?? globalThis.chrome;
      if (!api || !api.runtime || !api.runtime.id) { return; }
      const me = api.runtime.id;
      const marker = "linenExternalConnectable";
      const root = document.documentElement;
      const ids = (root.dataset[marker] || "").split(",").filter(Boolean);
      if (!ids.includes(me)) {
        ids.push(me);
        root.dataset[marker] = ids.join(",");
      }
      const origin = window.location.origin === "null" ? "*" : window.location.origin;
      const ports = new Map();
      const retryDelays = [250, 500, 1000, 2000, 4000];

      function open(id, name, attempt) {
        let entry = ports.get(id);
        if (!entry) {
          entry = { port: null, queue: [], closed: false, heard: false, name };
          ports.set(id, entry);
        }
        if (entry.closed) { return; }
        let port;
        try {
          port = api.runtime.connect({ name: "linen-external:" + (name || "") });
        } catch (error) {
          fail(id, entry, String(error && error.message || error), attempt);
          return;
        }
        entry.port = port;
        port.onMessage.addListener(message => {
          entry.heard = true;
          window.postMessage({ linenExternal: "message", port: id, message }, origin);
        });
        port.onDisconnect.addListener(() => {
          const error = api.runtime.lastError;
          if (entry.port !== port) { return; }
          entry.port = null;
          fail(id, entry, error ? error.message : undefined, attempt);
        });
        for (const message of entry.queue.splice(0)) {
          try { port.postMessage(message); } catch (error) { entry.queue.unshift(message); break; }
        }
      }

      function fail(id, entry, error, attempt) {
        if (entry.closed) { return; }
        if (!entry.heard && attempt < retryDelays.length) {
          setTimeout(() => open(id, entry.name, attempt + 1), retryDelays[attempt]);
          return;
        }
        entry.closed = true;
        ports.delete(id);
        window.postMessage({ linenExternal: "disconnected", port: id, error }, origin);
      }

      window.addEventListener("message", event => {
        if (event.source !== window) { return; }
        const data = event.data;
        if (!data || typeof data !== "object" || typeof data.linenExternal !== "string") { return; }
        if (data.linenExternal === "connect") {
          if (data.extensionId !== me) { return; }
          open(data.port, data.name, 0);
        } else if (data.linenExternal === "post") {
          const entry = ports.get(data.port);
          if (!entry) { return; }
          if (entry.port) {
            try { entry.port.postMessage(data.message); } catch (error) { entry.queue.push(data.message); }
          } else {
            entry.queue.push(data.message);
          }
        } else if (data.linenExternal === "disconnect") {
          const entry = ports.get(data.port);
          if (!entry) { return; }
          ports.delete(data.port);
          entry.closed = true;
          if (entry.port) { try { entry.port.disconnect(); } catch (error) { } }
        } else if (data.linenExternal === "send") {
          if (data.extensionId !== me) { return; }
          Promise.resolve()
            .then(() => api.runtime.sendMessage(data.message))
            .then(
              response => window.postMessage({ linenExternal: "reply", requestId: data.requestId, response }, origin),
              error => window.postMessage({ linenExternal: "reply", requestId: data.requestId, error: String(error && error.message || error) }, origin)
            );
        }
      });
    })();
    """#

    @discardableResult
    static func ensureRelayApplied(at package: URL) -> Bool {
        let manifestURL = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let external = root["externally_connectable"] as? [String: Any],
              let matches = external["matches"] as? [String], !matches.isEmpty
        else { return false }

        try? relayScript.write(
            to: package.appendingPathComponent(relayFileName),
            atomically: true,
            encoding: .utf8
        )
        var contentScripts = root["content_scripts"] as? [[String: Any]] ?? []
        guard !contentScripts.contains(where: { ($0["js"] as? [String]) == [relayFileName] }) else { return true }

        contentScripts.append([
            "js": [relayFileName],
            "matches": matches,
            "run_at": "document_start",
            "all_frames": true,
        ])
        root["content_scripts"] = contentScripts
        guard let updated = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return false }
        do {
            try updated.write(to: manifestURL, options: .atomic)
        } catch {
            return false
        }
        Pipeline.log.notice("ext: gave \(package.lastPathComponent, privacy: .public) the externally_connectable relay")
        return true
    }
}
