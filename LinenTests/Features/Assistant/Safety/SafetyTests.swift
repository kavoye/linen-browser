// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import WebKit

@testable import Linen

/// The three places where something the app doesn't control - a server's
/// filename, a failed load, an extension's manifest - decides what the app
/// writes, shows, or grants.
struct DownloadFilenameTests {
    /// `URL.appending(path:)` resolves `..`, and this app is not sandboxed,
    /// so a suggested filename is a path unless something makes it a name.
    @Test(arguments: [
        "../../evil.plist",
        "/etc/passwd",
        "sub/dir/file.txt",
        "a/../../b.zip",
    ])
    func aSuggestedNameCannotEscapeTheDownloadFolder(_ suggested: String) {
        let folder = URL(filePath: "/Users/someone/Downloads", directoryHint: .isDirectory)
        let safe = DownloadManager.safeFilename(suggested)
        #expect(!safe.contains("/"))

        let destination = folder.appending(path: safe).standardizedFileURL
        #expect(destination.deletingLastPathComponent().path == folder.path)
    }

    @Test func leavesOrdinaryNamesAlone() {
        #expect(DownloadManager.safeFilename("Report 2026.pdf") == "Report 2026.pdf")
        #expect(DownloadManager.safeFilename("archive.tar.gz") == "archive.tar.gz")
    }

    @Test func neverProducesAnEmptyOrHiddenName() {
        #expect(DownloadManager.safeFilename("") == "Download")
        #expect(DownloadManager.safeFilename("   ") == "Download")
        #expect(DownloadManager.safeFilename("..") == "Download")
        #expect(DownloadManager.safeFilename(".bashrc") == "bashrc")
    }

    @Test func staysInsideOneFilesystemComponent() {
        let long = String(repeating: "a", count: 400) + ".zip"
        #expect(DownloadManager.safeFilename(long).utf8.count <= 255)
    }
}

struct ErrorPageTests {
    /// A cancel fires on every stop button, every superseded navigation and
    /// every ⌘-click; 102 is what a download looks like to the navigation
    /// delegate. Drawing an error page for those would put one over a page
    /// that is loading perfectly well.
    @Test func staysQuietForCancelsAndDownloads() {
        #expect(ErrorPage.isSilent(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(ErrorPage.isSilent(NSError(domain: "WebKitErrorDomain", code: 102)))
        #expect(ErrorPage.isSilent(NSError(domain: "WebKitErrorDomain", code: 204)))
    }

    @Test func speaksUpForRealFailures() {
        #expect(!ErrorPage.isSilent(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)))
        #expect(!ErrorPage.isSilent(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        #expect(!ErrorPage.isSilent(NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)))
    }

    @Test func prefersTheAddressTheErrorCarries() throws {
        let failing = URL(string: "https://gone.example/page")!
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost,
            userInfo: [NSURLErrorFailingURLErrorKey: failing]
        )
        #expect(ErrorPage.failedURL(from: error, fallback: URL(string: "https://other.example")) == failing)
    }

    @Test func fallsBackToWhereTheTabThoughtItWas() throws {
        let fallback = URL(string: "https://other.example")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(ErrorPage.failedURL(from: error, fallback: fallback) == fallback)
        #expect(ErrorPage.failedURL(from: error, fallback: nil) == nil)
    }

    /// The host and the system's message both trace back to the server that
    /// failed, and they are pasted into markup.
    @Test func escapesEverythingItInterpolates() {
        let html = ErrorPage.html(
            headline: "<script>alert(1)</script>",
            detail: "\"quoted\" & <b>bold</b>",
            url: URL(string: "https://example.com")!
        )
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("&amp;"))
        #expect(html.contains("&quot;quoted&quot;"))
    }

    @Test func saysSomethingUsefulRatherThanAnErrorCode() {
        let offline = ErrorPage.html(
            headline: "You're offline",
            detail: "This Mac isn't connected to the internet.",
            url: URL(string: "https://example.com/x")!
        )
        #expect(offline.contains("You&#39;re offline"))
        #expect(offline.contains("example.com"))
    }
}

struct ExtensionConsentTests {
    /// The one summary that matters: an extension that can reach everything
    /// has to say so in those words, not as a list of patterns.
    @Test func callsBroadAccessWhatItIs() {
        let all = ExtensionConsent.hostSummary(for: patterns("<all_urls>"))
        #expect(all == ["every website you visit"])

        let wildcard = ExtensionConsent.hostSummary(for: patterns("*://*/*"))
        #expect(wildcard == ["every website you visit"])
    }

    @Test func namesSpecificSitesPlainly() {
        let hosts = ExtensionConsent.hostSummary(for: patterns(
            "*://*.github.com/*",
            "https://example.com/*"
        ))
        #expect(hosts == ["example.com", "github.com"])
    }

    @Test func oneBroadPatternSwallowsTheNarrowOnes() {
        let hosts = ExtensionConsent.hostSummary(for: patterns("https://example.com/*", "<all_urls>"))
        #expect(hosts == ["every website you visit"])
    }

    @Test func theSheetSaysSomethingEvenWithNothingToReport() {
        #expect(ExtensionConsent.body(hosts: [], abilities: []).contains("no special access"))
    }

    @Test func longHostListsAreTruncatedRatherThanRunOffTheSheet() {
        let hosts = (1...20).map { "site\($0).com" }
        let body = ExtensionConsent.body(hosts: hosts, abilities: [])
        #expect(body.contains("and 12 more"))
        #expect(!body.contains("site20.com"))
    }

    private func patterns(_ strings: String...) -> Set<WKWebExtension.MatchPattern> {
        Set(strings.compactMap { try? WKWebExtension.MatchPattern(string: $0) })
    }
}

/// The code-level backstop for the things the agent must never be talked into
/// doing unasked: spending money, moving it, destroying an account, or
/// speaking in the user's name.
struct SensitiveActionTests {
    @Test(arguments: [
        "Place order", "Place your order", "Buy now", "Buy it now", "Pay",
        "Pay now", "Pay $49.99", "Complete purchase", "Confirm and pay",
        "Proceed to pay", "Checkout", "Check out", "Delete account",
        "Delete my account", "Permanently delete", "Send money",
        "Confirm transfer", "Withdraw", "Post", "Publish", "Send message",
        "Submit review", "Reply",
    ])
    func refusesActionsThatSpendMoneyOrDestroyData(_ label: String) {
        #expect(SensitiveAction.isConsequentialClick(label))
    }

    /// The category decides which grant a remembered "always allow" writes, so
    /// a misfiled label would widen a grant beyond what the user agreed to.
    @Test func filesEachLabelUnderTheRightConsequence() {
        #expect(SensitiveAction.category(of: "Place order") == .purchase)
        #expect(SensitiveAction.category(of: "Confirm and pay") == .purchase)
        #expect(SensitiveAction.category(of: "Send money") == .transfer)
        #expect(SensitiveAction.category(of: "Withdraw") == .transfer)
        #expect(SensitiveAction.category(of: "Delete account") == .deletion)
        #expect(SensitiveAction.category(of: "Send message") == .publication)
        #expect(SensitiveAction.category(of: "Add to Bag") == nil)
    }

    /// "send money" has to win over the shorter "send …" publication signals,
    /// or a transfer would be filed - and granted - as posting.
    @Test func prefersTheMostSpecificSignal() {
        #expect(SensitiveAction.category(of: "Send money now") == .transfer)
        #expect(SensitiveAction.category(of: "Send payment") == .transfer)
    }

    /// The false-positive guard: normal browsing - including the shopping steps
    /// before the commit - has to stay clickable, or the agent stops being
    /// useful for the very tasks it exists for.
    @Test(arguments: [
        "Add to Bag", "Add to Cart", "Add to basket", "Search", "Next",
        "Continue reading", "Sign in", "Accept cookies", "Show more",
        "Save for later", "Payment methods", "Display settings", "Buyers guide",
        "Learn more", "UK 8", "Repay information",
    ])
    func leavesOrdinaryBrowsingAlone(_ label: String) {
        #expect(!SensitiveAction.isConsequentialClick(label))
    }

    @Test func ignoresCaseAndSurroundingPunctuation() {
        #expect(SensitiveAction.isConsequentialClick("  PLACE  ORDER  "))
        #expect(SensitiveAction.isConsequentialClick("Confirm payment »"))
        #expect(SensitiveAction.category(of: "Continue", context: "data-action=confirm_purchase") == .purchase)
    }

    @Test func surroundingContextCanRevealADeceptiveLabel() {
        #expect(SensitiveAction.category(of: "Continue", context: "Checkout. Complete purchase") == .purchase)
        #expect(SensitiveAction.category(of: "Continue", context: "Continue profile setup") == nil)
    }

    /// The decline message has to tell the model to stop, not to improvise -
    /// an agent that reroutes around a refused click has defeated the gate.
    @Test func tellsTheModelToStopRatherThanRetry() {
        let message = SensitiveAction.declined("Place order", category: .purchase)
        #expect(message.contains("declined"))
        #expect(message.lowercased().contains("do not try another way"))
    }
}

/// Remembered "always allow" answers. The scope of a grant is the whole
/// security property here: one category on one site, revocable, and never
/// implicitly global.
@MainActor
@Suite(.serialized)
struct AgentActionPolicyTests {
    /// Storage that lives and dies with the test. A defaults suite would do
    /// the job too, but only by leaving a file in ~/Library/Preferences that
    /// no teardown can reliably remove.
    private final class InMemoryGrantStorage: AgentGrantStorage {
        var grantData: Data?
    }

    private func makePolicy() -> AgentActionPolicy {
        AgentActionPolicy(storage: InMemoryGrantStorage())
    }

    @Test func remembersOnlyWhatWasGranted() throws {
        let policy = makePolicy()
        policy.allowAlways(.purchase, host: "shop.example.com")

        #expect(policy.isAlwaysAllowed(.purchase, host: "shop.example.com"))
        // Same site, a different consequence.
        #expect(!policy.isAlwaysAllowed(.deletion, host: "shop.example.com"))
        // Same consequence, a different site.
        #expect(!policy.isAlwaysAllowed(.purchase, host: "other.example.com"))
    }

    @Test func treatsWWWAsTheSameSite() throws {
        let policy = makePolicy()
        policy.allowAlways(.purchase, host: "www.shop.example.com")
        #expect(policy.isAlwaysAllowed(.purchase, host: "shop.example.com"))
        #expect(policy.isAlwaysAllowed(.purchase, host: "SHOP.Example.com"))
    }

    /// A grant with no host to bind it to would be a global one wearing a
    /// narrow label, so it is not recorded at all.
    @Test func refusesToRememberAGrantItCannotScope() throws {
        let policy = makePolicy()
        policy.allowAlways(.purchase, host: nil)
        policy.allowAlways(.purchase, host: "")
        #expect(policy.grants.isEmpty)
        #expect(!policy.isAlwaysAllowed(.purchase, host: nil))
    }

    @Test func grantingTwiceDoesNotDuplicateTheRow() throws {
        let policy = makePolicy()
        policy.allowAlways(.purchase, host: "shop.example.com")
        policy.allowAlways(.purchase, host: "www.shop.example.com")
        #expect(policy.grants.count == 1)
    }

    @Test func revokesIndividuallyAndWholesale() throws {
        let policy = makePolicy()
        policy.allowAlways(.purchase, host: "a.example.com")
        policy.allowAlways(.deletion, host: "b.example.com")

        let first = try #require(policy.grants.first { $0.host == "a.example.com" })
        policy.revoke(first)
        #expect(!policy.isAlwaysAllowed(.purchase, host: "a.example.com"))
        #expect(policy.isAlwaysAllowed(.deletion, host: "b.example.com"))

        policy.revokeAll()
        #expect(policy.grants.isEmpty)
    }

    @Test func survivesRelaunch() {
        let storage = InMemoryGrantStorage()

        AgentActionPolicy(storage: storage).allowAlways(.purchase, host: "shop.example.com")
        // A second instance over the same storage is what the next launch sees.
        #expect(AgentActionPolicy(storage: storage).isAlwaysAllowed(.purchase, host: "shop.example.com"))
    }

    // MARK: - The decision path

    /// The seam is task-local, so the stub reaches everything this test
    /// awaits and nothing running beside it - no clearing, and nothing for a
    /// suite finishing next door to clear out from under a click.
    private func withDecision(
        _ decision: @escaping (String, SensitiveAction.Category, String?) -> AgentActionConsent.Decision,
        _ body: () async -> Void
    ) async {
        await AgentActionConsent.$decisionForTesting.withValue(.init(decision)) {
            await body()
        }
    }

    @Test func aStoredGrantSkipsTheQuestionEntirely() async throws {
        let policy = makePolicy()
        policy.allowAlways(.purchase, host: "shop.example.com")

        var asked = false
        await withDecision({ _, _, _ in
            asked = true
            return .decline
        }) {
            let permitted = await AgentActionConsent.permit(
                label: "Place order",
                category: .purchase,
                host: "www.shop.example.com",
                policy: policy
            )
            #expect(permitted)
        }
        // The point of remembering: no second dialog for the same site.
        #expect(!asked)
    }

    @Test func decliningStopsTheClickAndRemembersNothing() async throws {
        let policy = makePolicy()
        await withDecision({ _, _, _ in .decline }) {
            let permitted = await AgentActionConsent.permit(
                label: "Place order",
                category: .purchase,
                host: "shop.example.com",
                policy: policy
            )
            #expect(!permitted)
        }
        #expect(policy.grants.isEmpty)
    }

    @Test func allowingOnceDoesNotRemember() async throws {
        let policy = makePolicy()
        await withDecision({ _, _, _ in .allowOnce }) {
            let permitted = await AgentActionConsent.permit(
                label: "Place order",
                category: .purchase,
                host: "shop.example.com",
                policy: policy
            )
            #expect(permitted)
        }
        // "Once" has to mean once, or the next turn proceeds unasked.
        #expect(policy.grants.isEmpty)
    }

    @Test func allowingAlwaysRemembersExactlyThatSiteAndCategory() async throws {
        let policy = makePolicy()
        await withDecision({ _, _, _ in .allowAlways }) {
            _ = await AgentActionConsent.permit(
                label: "Place order",
                category: .purchase,
                host: "shop.example.com",
                policy: policy
            )
        }
        #expect(policy.isAlwaysAllowed(.purchase, host: "shop.example.com"))
        #expect(!policy.isAlwaysAllowed(.deletion, host: "shop.example.com"))
        #expect(!policy.isAlwaysAllowed(.purchase, host: "elsewhere.example.com"))
    }

    /// The sheet has to name the control, the site, and the stakes - a generic
    /// "allow this action?" is the kind people learn to click through.
    @Test func theSheetNamesTheStakes() {
        let body = AgentActionConsent.body(
            label: "Place order",
            category: .purchase,
            site: "shop.example.com"
        )
        #expect(body.contains("Place order"))
        #expect(body.contains("shop.example.com"))
        #expect(body.contains("completes a purchase"))
        #expect(body.contains("hidden instructions"))
    }
}

/// The id is scraped off a results page and becomes the address a tab loads,
/// so nothing but a genuine 11-character YouTube id may reach it.
struct MediaWatchURLTests {
    @Test func buildsTheWatchAddressForAWellFormedID() {
        let url = AgentToolkit.watchURL(videoID: "dQw4w9WgXcQ")
        #expect(url?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "\"></iframe><script>alert(1)</script>",
        "short",
        "toolongtobeavalidid",
        "abcd efghij",
        "abc/def/ghij",
        "",
    ])
    func refusesAnythingThatIsntAnID(_ videoID: String) {
        #expect(AgentToolkit.watchURL(videoID: videoID) == nil)
    }
}

/// The compatibility tokens stay fixed while the platform version changes.
struct UserAgentTests {
    private func agent(_ major: Int, _ minor: Int, _ patch: Int = 0) -> String {
        WebViewPool.makeSafariUserAgent(
            osVersion: OperatingSystemVersion(
                majorVersion: major,
                minorVersion: minor,
                patchVersion: patch
            )
        )
    }

    @Test func tracksTheRunningOSMajorAndMinor() {
        #expect(agent(26, 6, 1).contains("Version/26.6 "))
        #expect(agent(27, 0).contains("Version/27.0 "))
        #expect(agent(26, 12).contains("Version/26.12 "))
    }

    /// The compatibility string uses two version components.
    @Test func ignoresThePatchComponent() {
        #expect(agent(26, 6, 1) == agent(26, 6, 4))
    }

    /// These tokens are fixed compatibility values.
    @Test func keepsFrozenCompatibilityTokens() {
        let string = agent(26, 6)
        #expect(string.hasPrefix("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "))
        #expect(string.contains("AppleWebKit/605.1.15 (KHTML, like Gecko)"))
        #expect(string.hasSuffix(" Safari/605.1.15"))
    }

    /// The shape sites actually parse, in order, with no doubled spaces from
    /// the concatenation.
    @Test func readsAsOneWellFormedSafariString() {
        let string = agent(26, 6)
        #expect(!string.contains("  "))
        #expect(string == "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/26.6 Safari/605.1.15")
    }

    /// What the app actually sends, on whatever machine this runs on.
    @Test func theLiveStringIsCoherent() {
        let live = WebViewPool.safariUserAgent
        #expect(live.contains("Version/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)."))
        #expect(live.hasSuffix(" Safari/605.1.15"))
    }
}

/// A custom provider reached over plain http would put the API key on the wire
/// in the clear - allowed only for a loopback server, which has no key.
struct ProviderEndpointTests {
    @Test(arguments: [
        "http://api.example.com/v1",
        "http://198.51.100.7:8000/v1",
        "HTTP://API.EXAMPLE.COM/v1",
        // Claimed over mDNS, not assigned: anything on the same network can
        // answer for it, so plaintext to one is plaintext to a stranger.
        "http://my-mac.local:11434/v1",
    ])
    func rejectsPlainHTTPToRemoteHosts(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(IntelligenceViewModel.isInsecureRemoteEndpoint(url))
    }

    @Test(arguments: [
        "http://localhost:8000/v1",
        "http://127.0.0.1:1234/v1",
        "https://api.example.com/v1",
        "https://my-mac.local:11434/v1",
    ])
    func allowsHTTPSAndLoopbackHTTP(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(!IntelligenceViewModel.isInsecureRemoteEndpoint(url))
    }

    /// The interface's sense of "local" is wider than the wire's: a `.local`
    /// server still needs no key, it just needs TLS.
    @Test func aDotLocalServerIsStillALocalServer() throws {
        let url = try #require(URL(string: "https://my-mac.local:11434/v1"))
        #expect(IntelligenceViewModel.isLocalNetwork(url))
        #expect(!IntelligenceViewModel.isLoopback(url))
    }
}

/// The way past a rejected certificate. Everything here is about the door
/// being shut: a browser that ships this open has no certificate checking.
@MainActor
struct CertificateTrustTests {
    /// The setting itself, not the alert, is what the invariant hangs on.
    @Test func exceptionsAreOffUntilAskedFor() {
        let settings = BrowserSettings.shared
        let restore = settings.allowsCertificateExceptions
        defer { settings.allowsCertificateExceptions = restore }

        settings.resetToDefaults()
        #expect(!settings.allowsCertificateExceptions)
    }

    /// An exception granted under the setting must not outlive it. Otherwise
    /// turning the switch back off leaves the hosts already accepted
    /// permanently trusted, which is the opposite of what it says.
    @Test func turningTheSettingOffForgetsWhatWasAcceptedUnderIt() {
        let settings = BrowserSettings.shared
        let restore = settings.allowsCertificateExceptions
        defer {
            settings.allowsCertificateExceptions = restore
            CertificateTrust.forgetAll()
        }

        settings.allowsCertificateExceptions = true
        settings.allowsCertificateExceptions = false
        #expect(CertificateTrust.acceptedHostCount == 0)
    }
}
