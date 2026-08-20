// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WebKit

nonisolated enum ErrorPage {
    static func isSilent(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return true
        }
        if error.domain == "WebKitErrorDomain", error.code == 102 || error.code == 204 {
            return true
        }
        return false
    }

    static func failedURL(from error: any Error, fallback: URL?) -> URL? {
        let error = error as NSError
        return (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? fallback
    }

    private static func explain(_ error: any Error) -> (headline: LocalizedStringResource, detail: String) {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else {
            return ("This page didn’t load", error.localizedDescription)
        }
        switch error.code {
        case NSURLErrorNotConnectedToInternet:
            return ("You’re offline", String(localized: "This Mac isn’t connected to the internet."))
        case NSURLErrorCannotFindHost:
            return (
                "Can’t find this website",
                String(localized: "No server answers to that address. Check the spelling.")
            )
        case NSURLErrorCannotConnectToHost:
            return (
                "Can’t reach this website",
                String(localized: "The server refused the connection or isn’t running.")
            )
        case NSURLErrorTimedOut:
            return (
                "This website took too long",
                String(localized: "The server accepted the connection but never replied.")
            )
        case NSURLErrorNetworkConnectionLost:
            return (
                "The connection dropped",
                String(localized: "The network went away mid-transfer. Try again.")
            )
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return (
                "This connection isn’t private",
                String(localized: "The website’s certificate couldn’t be verified, so Linen stopped before sending anything.")
            )
        case NSURLErrorUserAuthenticationRequired:
            return (
                "This website needs a sign-in",
                String(localized: "The server asked for a username and password.")
            )
        default:
            return ("This page didn’t load", error.localizedDescription)
        }
    }

    @discardableResult
    @MainActor
    static func show(_ error: any Error, in webView: WKWebView, fallbackURL: URL?) -> URL? {
        guard !isSilent(error), let url = failedURL(from: error, fallback: fallbackURL) else { return nil }
        let (headline, detail) = explain(error)
        webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: html(headline: String(localized: headline), detail: detail, url: url)
        )
        return url
    }

    static func html(headline: String, detail: String, url: URL) -> String {
        let host = escape(url.host() ?? url.absoluteString)
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(headline))</title>
        <style>
          :root { color-scheme: light dark; --ink:#1c1c1e; --dim:#6b6b70; --bg:#fafafb; }
          @media (prefers-color-scheme: dark) {
            :root { --ink:#f2f2f4; --dim:#98989e; --bg:#171719; }
          }
          html, body { height: 100%; margin: 0; }
          body {
            background: var(--bg); color: var(--ink);
            font: 400 15px/1.5 -apple-system, system-ui, sans-serif;
            display: flex; align-items: center; justify-content: center;
            text-align: center; padding: 0 32px; box-sizing: border-box;
            -webkit-font-smoothing: antialiased;
          }
          main { max-width: 30rem; }
          h1 { font-size: 20px; font-weight: 600; margin: 0 0 10px; letter-spacing: -0.01em; }
          p { margin: 0; color: var(--dim); }
          .host {
            margin-top: 22px; font-size: 12.5px; color: var(--dim);
            font-family: ui-monospace, SFMono-Regular, monospace;
            word-break: break-all;
          }
        </style>
        </head><body><main>
          <h1>\(escape(headline))</h1>
          <p>\(escape(detail))</p>
          <p class="host">\(host)</p>
        </main></body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
