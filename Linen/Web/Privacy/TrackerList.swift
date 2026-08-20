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
}
