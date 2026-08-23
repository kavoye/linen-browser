// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum TrackerList {
    private static let advertising = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "adnxs.com",
        "rubiconproject.com",
        "pubmatic.com",
        "openx.net",
        "criteo.com",
        "criteo.net",
        "taboola.com",
        "outbrain.com",
        "adroll.com",
        "advertising.com",
        "casalemedia.com",
        "sharethrough.com",
        "smartadserver.com",
        "teads.tv",
        "media.net",
        "bidswitch.net",
        "3lift.com",
        "adcolony.com",
        "applovin.com",
        "inmobi.com",
        "unityads.unity3d.com",
    ]

    private static let analytics = [
        "google-analytics.com",
        "analytics.google.com",
        "googletagmanager.com",
        "googletagservices.com",
        "scorecardresearch.com",
        "quantserve.com",
        "quantcount.com",
        "chartbeat.com",
        "chartbeat.net",
        "segment.com",
        "segment.io",
        "mixpanel.com",
        "amplitude.com",
        "heap.io",
        "heapanalytics.com",
        "kissmetrics.com",
        "kissmetrics.io",
        "statcounter.com",
        "matomo.cloud",
        "branch.io",
        "adjust.com",
        "appsflyer.com",
        "newrelic.com",
        "nr-data.net",
    ]

    private static let sessionRecording = [
        "hotjar.com",
        "hotjar.io",
        "fullstory.com",
        "mouseflow.com",
        "luckyorange.com",
        "inspectlet.com",
        "crazyegg.com",
        "clarity.ms",
        "smartlook.com",
        "quantummetric.com",
        "contentsquare.net",
        "decibelinsight.net",
    ]

    private static let socialPixels = [
        "connect.facebook.net",
        "facebook.com/tr",
        "ads-twitter.com",
        "analytics.twitter.com",
        "ads.linkedin.com",
        "px.ads.linkedin.com",
        "analytics.tiktok.com",
        "ads.pinterest.com",
        "bat.bing.com",
        "ads.yahoo.com",
        "amazon-adsystem.com",
    ]

    private static let fingerprinting = [
        "fingerprintjs.com",
        "fpjs.io",
        "iovation.com",
        "threatmetrix.com",
        "audioeye.com",
    ]

    static let domains: [String] =
        advertising + analytics + sessionRecording + socialPixels + fingerprinting

    static func filter(for domain: String) -> String {
        let parts = domain.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let host = String(parts[0])
        let path = parts.count > 1 ? "/" + String(parts[1]) : ""
        let escapedHost = host.replacingOccurrences(of: ".", with: "\\.")
        let escapedPath = path.replacingOccurrences(of: ".", with: "\\.")
        return "^https?://([^/]+\\.)?\(escapedHost)\(escapedPath)"
    }

    static func matchingDomains(
        in resourceURLs: [String],
        topLevelURL: URL?
    ) -> [String] {
        let rules = domains.map(ruleParts)
        var matches = Set<String>()

        for rawURL in resourceURLs {
            guard let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host?.lowercased(),
                  !isSameOrigin(url, topLevelURL)
            else { continue }

            for rule in rules where host == rule.host || host.hasSuffix(".\(rule.host)") {
                guard rule.path.isEmpty || url.path.hasPrefix(rule.path) else { continue }
                matches.insert(rule.host)
                break
            }
        }

        return matches.sorted()
    }

    private static func ruleParts(_ rule: String) -> (host: String, path: String) {
        let parts = rule.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        return (
            String(parts[0]).lowercased(),
            parts.count > 1 ? "/" + String(parts[1]) : ""
        )
    }

    private static func isSameOrigin(_ resourceURL: URL, _ topLevelURL: URL?) -> Bool {
        guard let topLevelURL else { return false }
        return resourceURL.scheme?.lowercased() == topLevelURL.scheme?.lowercased()
            && resourceURL.host?.lowercased() == topLevelURL.host?.lowercased()
            && effectivePort(of: resourceURL) == effectivePort(of: topLevelURL)
    }

    private static func effectivePort(of url: URL) -> Int? {
        if let port = url.port {
            return port
        }
        return switch url.scheme?.lowercased() {
        case "http":
            80
        case "https":
            443
        default:
            nil
        }
    }
}
