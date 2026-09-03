// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

nonisolated enum ExtensionPageAssets {
    static let reporterFileName = "linen-base.js"

    static let reporterScript = #"""
    (() => {
      "use strict";
      const api = globalThis.browser ?? globalThis.chrome;
      if (!api || !api.runtime || !api.runtime.id) { return; }
      const root = document.documentElement;
      const base = api.runtime.getURL("").replace(/\/$/, "");
      const bases = (root.dataset.linenExtensionBases || "").split(",").filter(Boolean);
      if (bases.includes(base)) { return; }
      bases.push(base);
      root.dataset.linenExtensionBases = bases.join(",");
    })();
    """#

    @discardableResult
    static func ensureReporterApplied(at package: URL) -> Bool {
        let manifestURL = package.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var contentScripts = root["content_scripts"] as? [[String: Any]],
              !contentScripts.isEmpty
        else { return false }

        try? reporterScript.write(
            to: package.appendingPathComponent(reporterFileName),
            atomically: true,
            encoding: .utf8
        )
        guard !contentScripts.contains(where: { ($0["js"] as? [String]) == [reporterFileName] }) else {
            return true
        }
        let matches = contentScripts.flatMap { $0["matches"] as? [String] ?? [] }
        guard !matches.isEmpty else { return false }

        contentScripts.append([
            "js": [reporterFileName],
            "matches": Array(Set(matches)).sorted(),
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
        return true
    }

    static let script = """
    (() => {
      "use strict";
      const descriptor = Object.getOwnPropertyDescriptor(Document.prototype, "currentScript");
      if (!descriptor || typeof descriptor.get !== "function") { return; }
      const original = descriptor.get;
      const unmasked = new WeakMap();
      Object.defineProperty(Document.prototype, "currentScript", {
        configurable: true,
        enumerable: descriptor.enumerable,
        get() {
          const script = original.call(this);
          if (!script) { return script; }
          const src = script.src;
          if (typeof src !== "string" || !src.startsWith("webkit-masked-url://")) { return script; }
          let path = script.dataset ? script.dataset.path : undefined;
          if (!path) {
            // No convention to read: the package root is the best guess, and
            // only when one extension has published one.
            const bases = (document.documentElement.dataset.linenExtensionBases || "")
              .split(",").filter(Boolean);
            if (bases.length !== 1) { return script; }
            path = bases[0];
          }
          let proxy = unmasked.get(script);
          if (proxy) { return proxy; }
          const name = src.split("/").pop() || "script.js";
          const real = path.replace(/\\/$/, "") + "/" + name;
          proxy = new Proxy(script, {
            get(target, key, receiver) {
              if (key === "src") { return real; }
              const value = Reflect.get(target, key, target);
              return typeof value === "function" ? value.bind(target) : value;
            }
          });
          unmasked.set(script, proxy);
          return proxy;
        }
      });
    })();
    """
}
