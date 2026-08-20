// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Security
import Testing

@testable import Linen

/// The scrapers and parsers: every one of these reads a format Linen does not
/// control, and every one of them is a single assumption away from silently
/// returning nothing.
struct SnippetFetcherTests {
    /// A cut-down version of what `html.duckduckgo.com/html/` actually
    /// serves: a sponsored row first, then two real ones.
    private static let html = """
    <div class="result results_links_deep result--ad">
      <a rel="nofollow" class="result__a" href="//duckduckgo.com/y.js?ad_provider=x">Buy Shoes Now</a>
      <a class="result__snippet">Sponsored nonsense</a>
    </div>
    <div class="result results_links_deep">
      <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa&amp;rut=abc">
        First &amp; Best Result
      </a>
      <a class="result__snippet">A snippet with &quot;quotes&quot; and <b>markup</b>.</a>
    </div>
    <div class="result results_links_deep">
      <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.org%2Fb">Second</a>
      <a class="result__snippet">Another one.</a>
    </div>
    """

    @Test func unwrapsRedirectsAndDropsAds() {
        let hits = SnippetFetcher.hits(in: Self.html, limit: 3)
        #expect(hits.count == 2)
        #expect(hits[0].url == "https://example.com/a")
        #expect(hits[1].url == "https://example.org/b")
        #expect(!hits.contains { $0.title.contains("Buy Shoes") })
    }

    /// The `&amp;` unescape exists because without it every parameter after
    /// the first parses as `amp;<name>` and the destination comes back wrong.
    @Test func decodesEntitiesInTitlesAndSnippets() {
        let hits = SnippetFetcher.hits(in: Self.html, limit: 3)
        #expect(hits[0].title == "First & Best Result")
        #expect(hits[0].snippet == "A snippet with \"quotes\" and markup.")
    }

    @Test func honoursTheLimit() {
        #expect(SnippetFetcher.hits(in: Self.html, limit: 1).count == 1)
    }

    @Test func survivesMarkupItHasNeverSeen() {
        #expect(SnippetFetcher.hits(in: "<html><body>nothing here</body></html>", limit: 3).isEmpty)
        #expect(SnippetFetcher.hits(in: "", limit: 3).isEmpty)
        // Truncated mid-tag: the loop has to end rather than spin.
        #expect(SnippetFetcher.hits(in: #"<a class="result__a" href="//dd"#, limit: 3).isEmpty)
    }

    @Test(arguments: [
        "//duckduckgo.com/y.js?u3=x",
        "https://example.com/?ad_provider=bing",
        "https://example.com/?ad_domain=shoes.com",
    ])
    func recognisesAds(_ href: String) {
        #expect(SnippetFetcher.isAdvertisement(href: href))
    }

    @Test func doesNotCallOrdinaryLinksAds() {
        #expect(!SnippetFetcher.isAdvertisement(href: "https://example.com/y-junior"))
    }

    /// The fallback source exists so one markup change can't take the agent's
    /// only search path with it - so it has to actually parse its own format,
    /// which puts `href` *before* `class` where the html page does the
    /// reverse, and quotes attributes with either mark.
    @Test func liteEndpointParsesItsOwnMarkup() throws {
        let lite = """
        <tr><td><a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.net%2Fx"
            class="result-link">Lite Result</a></td></tr>
        <tr><td class="result-snippet">Short description here.</td></tr>
        """
        let hits = SnippetFetcher.liteHits(in: lite, limit: 3)
        let first = try #require(hits.first)
        #expect(hits.count == 1)
        #expect(first.title == "Lite Result")
        #expect(first.url == "https://example.net/x")
        #expect(first.snippet == "Short description here.")
    }

    @Test func liteEndpointToleratesSingleQuotedAttributes() throws {
        let lite = """
        <a rel='nofollow' href='//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.net%2Fy' class='result-link'>Y</a>
        <td class='result-snippet'>Snippet.</td>
        """
        let first = try #require(SnippetFetcher.liteHits(in: lite, limit: 3).first)
        #expect(first.url == "https://example.net/y")
        #expect(first.snippet == "Snippet.")
    }

    @Test func pullsAnAttributeOutRegardlessOfOrderOrQuoting() {
        let tag = #"<a rel="nofollow" href="/x?a=1&b=2" class='result-link'>"#
        #expect(SnippetFetcher.attribute("href", in: tag) == "/x?a=1&b=2")
        #expect(SnippetFetcher.attribute("class", in: tag) == "result-link")
        #expect(SnippetFetcher.attribute("target", in: tag) == nil)
    }

    @Test func theTwoParsersDoNotShareAssumptions() {
        // Each returns nothing for the other's markup, which is the whole
        // point of having a second one.
        #expect(SnippetFetcher.liteHits(in: Self.html, limit: 3).isEmpty)
    }
}

struct ChromeWebStoreTests {
    @Test func readsTheIDOutOfAStorePageURL() {
        let id = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        #expect(ChromeWebStore.extensionID(
            fromPageURL: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(id)"
        ) == id)
        // The slug is optional; the id is always last.
        #expect(ChromeWebStore.extensionID(
            fromPageURL: "https://chromewebstore.google.com/detail/\(id)"
        ) == id)
    }

    @Test(arguments: [
        // Not the store.
        "https://evil.example.com/detail/slug/ddkjiahejlhfcafbddmgiahcphecmpfh",
        // A lookalike host that merely contains the real one.
        "https://chromewebstore.google.com.evil.tld/detail/ddkjiahejlhfcafbddmgiahcphecmpfh",
        // Right length, wrong alphabet.
        "https://chromewebstore.google.com/detail/DDKJIAHEJLHFCAFBDDMGIAHCPHECMPFH",
        "https://chromewebstore.google.com/detail/zzzjiahejlhfcafbddmgiahcphecmpfh",
        // Wrong length.
        "https://chromewebstore.google.com/detail/tooshort",
        // Not a detail page.
        "https://chromewebstore.google.com/category/ddkjiahejlhfcafbddmgiahcphecmpfh",
    ])
    func refusesAnythingElse(_ url: String) {
        #expect(ChromeWebStore.extensionID(fromPageURL: url) == nil)
    }

}

/// The extension-package verifier. These build a genuine CRX3 with a fresh RSA
/// key, so the whole path - container split, protobuf parse, SPKI unwrap, id
/// derivation, signature check - runs against real crypto rather than a
/// fixture, and the tamper cases prove it fails closed.
struct CRXVerifierTests {
    /// A CRX3 signed by `key`, wrapping `zip`, plus the extension id that key
    /// derives to.
    private static func makeCRX(zip: Data) throws -> (crx: Data, id: String, key: SecKey) {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
        ]
        let priv = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let pub = try #require(SecKeyCopyPublicKey(priv))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(pub, nil)) as Data
        let spki = spkiWrap(pkcs1)
        let id = CRXVerifier.derivedID(fromPublicKey: spki)

        // signed_header_data = SignedData { crx_id = SHA-256(spki)[0..<16] }.
        let crxID = Data(SHA256.hash(data: spki).prefix(16))
        let signedHeaderData = protoField(1, crxID)

        var message = Data("CRX3 SignedData\u{00}".utf8)
        message.append(contentsOf: le32(signedHeaderData.count))
        message.append(signedHeaderData)
        message.append(zip)
        let signature = try #require(
            SecKeyCreateSignature(priv, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, nil)
        ) as Data

        let proof = protoField(1, spki) + protoField(2, signature)
        let header = protoField(2, proof) + protoField(10000, signedHeaderData)

        var crx = Data("Cr24".utf8)
        crx.append(contentsOf: le32(3))
        crx.append(contentsOf: le32(header.count))
        crx.append(header)
        crx.append(zip)
        return (crx, id, priv)
    }

    @Test func acceptsAGenuinelySignedPackage() throws {
        let zip = Data("PK\u{03}\u{04}the real extension payload".utf8)
        let made = try Self.makeCRX(zip: zip)
        #expect(try CRXVerifier.verifiedZip(from: made.crx, expectedID: made.id) == zip)
    }

    @Test func rejectsAPackageAlteredAfterSigning() throws {
        let zip = Data("PK\u{03}\u{04}the real extension payload".utf8)
        var made = try Self.makeCRX(zip: zip)
        // Flip one byte of the zip while leaving the signature over the original
        // in place: the recomputed message no longer matches.
        let last = made.crx.count - 1
        made.crx[last] = made.crx[last] ^ 0xFF
        #expect(throws: CRXVerifier.VerificationError.self) {
            try CRXVerifier.verifiedZip(from: made.crx, expectedID: made.id)
        }
    }

    @Test func rejectsAPackageWhoseKeyIsNotThisExtension() throws {
        let made = try Self.makeCRX(zip: Data("PK\u{03}\u{04}payload".utf8))
        // A valid, correctly-signed package - but installed under a different
        // id than the key derives to.
        let wrongID = String(repeating: "a", count: 32)
        #expect(wrongID != made.id)
        #expect(throws: CRXVerifier.VerificationError.self) {
            try CRXVerifier.verifiedZip(from: made.crx, expectedID: wrongID)
        }
    }

    @Test func refusesABareUnsignedZip() {
        let zip = Data("PK\u{03}\u{04}not a crx at all, just a zip".utf8)
        #expect(throws: CRXVerifier.VerificationError.self) {
            try CRXVerifier.verifiedZip(from: zip, expectedID: String(repeating: "a", count: 32))
        }
    }

    @Test func refusesTruncatedAndWrongVersionContainers() {
        #expect(throws: (any Error).self) { try CRXVerifier.split(Data("Cr24".utf8)) }
        #expect(throws: (any Error).self) { try CRXVerifier.split(Data(repeating: 0, count: 64)) }

        var runaway = Data("Cr24".utf8)
        runaway.append(contentsOf: [3, 0, 0, 0])
        runaway.append(contentsOf: [0xFF, 0xFF, 0xFF, 0x7F]) // header runs off the end
        runaway.append(Data(repeating: 0, count: 32))
        #expect(throws: (any Error).self) { try CRXVerifier.split(runaway) }

        var version2 = Data("Cr24".utf8)
        version2.append(contentsOf: [2, 0, 0, 0])
        version2.append(contentsOf: [4, 0, 0, 0])
        version2.append(Data(repeating: 0, count: 32))
        #expect(throws: (any Error).self) { try CRXVerifier.split(version2) }
    }

    @Test func derivesA32CharacterAToPIdentifier() throws {
        let made = try Self.makeCRX(zip: Data("PK\u{03}\u{04}x".utf8))
        #expect(made.id.count == 32)
        #expect(made.id.allSatisfy { ("a"..."p").contains($0) })
    }

    // MARK: - DER / protobuf encoders (only what the test needs to forge a CRX)

    private static func le32(_ n: Int) -> [UInt8] {
        [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)]
    }

    private static func varint(_ value: Int) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v > 0 {
                byte |= 0x80
            }
            out.append(byte)
        } while v > 0
        return out
    }

    /// A length-delimited protobuf field.
    private static func protoField(_ number: Int, _ bytes: Data) -> Data {
        var out = Data(varint((number << 3) | 2))
        out.append(contentsOf: varint(bytes.count))
        out.append(bytes)
        return out
    }

    private static func derLength(_ n: Int) -> [UInt8] {
        if n < 0x80 {
            return [UInt8(n)]
        }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return [UInt8(0x80 | bytes.count)] + bytes
    }

    /// Wraps a PKCS#1 RSAPublicKey into a DER SubjectPublicKeyInfo - the inverse
    /// of what `CRXVerifier` unwraps, so the two have to agree on the structure.
    private static func spkiWrap(_ pkcs1: Data) -> Data {
        let algorithm: [UInt8] = [
            0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86,
            0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00,
        ]
        var bitString: [UInt8] = [0x03]
        bitString += derLength(pkcs1.count + 1)
        bitString += [0x00]
        bitString += [UInt8](pkcs1)

        let body = algorithm + bitString
        var sequence: [UInt8] = [0x30]
        sequence += derLength(body.count)
        sequence += body
        return Data(sequence)
    }
}

struct SiteNameTests {
    @Test(arguments: [
        ("news.ycombinator.com", "ycombinator"),
        ("www.ebay.co.uk", "ebay"),
        ("github.com", "github"),
        ("www.google.com", "google"),
        ("bbc.co.uk", "bbc"),
        // A two-letter TLD that isn't behind a generic label keeps one label.
        ("example.io", "example"),
        ("localhost", "localhost"),
    ])
    func namesTheSiteAPersonWouldSay(_ host: String, _ expected: String) {
        #expect(SiteName.name(forHost: host) == expected)
    }

    @Test func titleCasesForDisplay() {
        #expect(SiteName.title(forHost: "news.ycombinator.com") == "Ycombinator")
    }
}

/// The rule that keeps the frequently-visited grid from filling up with the
/// search box: every typed phrase lands on the engine, so it outranks every
/// real destination.
@MainActor
struct SearchEngineHostTests {
    @Test(arguments: [
        "duckduckgo.com",
        "html.duckduckgo.com",
        "www.bing.com",
        "search.brave.com",
        "www.google.com",
        "google.co.uk",
    ])
    func recognisesASearchBox(_ host: String) {
        #expect(SearchEngineHosts.isSearchEngine(host))
    }

    /// Google is a domain that does everything; only its search host counts.
    @Test(arguments: [
        "mail.google.com",
        "maps.google.com",
        "github.com",
        "news.ycombinator.com",
    ])
    func leavesDestinationsAlone(_ host: String) {
        #expect(!SearchEngineHosts.isSearchEngine(host))
    }
}

struct SearchEngineTests {
    /// Percent-encoding here is not cosmetic: `&`, `=` and `#` left raw turn
    /// the rest of a query into extra parameters on the engine's own URL.
    @Test func escapesQueryCharactersThatWouldSplitTheURL() throws {
        let url = try #require(SearchEngine.duckDuckGo.searchURL(for: "a&b=c #d?e"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "q" }?.value == "a&b=c #d?e")
        #expect(query.count == 1)
    }

    @Test func handlesUnicodeAndSpaces() throws {
        let url = try #require(SearchEngine.duckDuckGo.searchURL(for: "größe 42 shoes"))
        #expect(url.absoluteString.contains("gr%C3%B6%C3%9Fe"))
    }

    @Test func everyBuiltInEngineProducesAURL() {
        for engine in SearchEngine.catalog {
            #expect(engine.searchURL(for: "test") != nil, "\(engine.name) built no URL")
            #expect(engine.host != nil, "\(engine.name) has no readable host")
        }
    }

    @Test func aHalfFilledCustomEngineIsNotAURL() {
        #expect(SearchEngine.custom(name: "Mine", template: "").searchURL(for: "x") == nil)
    }
}

/// The on-device model's answer is a format Linen does not control either: it
/// is asked for "Some Word" and sometimes returns a shouted, quoted sentence.
struct FolderNameTests {
    @Test(arguments: [
        ("TRAVEL PLANNING", "Travel Planning"),
        ("RECIPES", "Recipes"),
        // Short all-caps words are the ones that really are acronyms.
        ("AI TOOLS", "AI Tools"),
        ("API DOCS", "API Docs"),
        // A name that already has a lowercase letter is the user's to keep,
        // however odd it looks.
        ("iPhone Rumors", "iPhone Rumors"),
        ("Trip Planning", "Trip Planning"),
        ("  \"Job Search\".  ", "Job Search"),
    ])
    func namesTheFolderTheWayTheSidebarWritesEverythingElse(_ raw: String, _ expected: String) {
        #expect(FolderNamer.sanitize(raw) == expected)
    }

    @Test(arguments: [
        "",
        "\"\"",
        "A folder of pages about planning a trip to Japan",
        "Trip Planning For Next Spring",
    ])
    func refusesWhatWouldNotFitTheSidebar(_ raw: String) {
        #expect(FolderNamer.sanitize(raw) == nil)
    }
}

struct YouTubeResolverTests {
    @Test func buildsAResultsURLWithAnEncodedQuery() throws {
        let url = YouTubeResolver.resultsURL(for: "lo-fi & jazz")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "www.youtube.com")
        #expect(components.path == "/results")
        #expect(components.queryItems == [URLQueryItem(name: "search_query", value: "lo-fi & jazz")])
    }

    @Test func extractsTheFirstWellFormedVideoIdentifier() {
        let html = #"{"videoId":"abcdefghijk"} {"videoId":"lmnopqrstuv"}"#
        #expect(YouTubeResolver.firstVideoID(in: html) == "abcdefghijk")
    }

    @Test(arguments: [
        #"{"videoId":"short"}"#,
        #"{"videoId":"abcdefghijk!"}"#,
        "",
    ])
    func rejectsMalformedVideoIdentifiers(_ html: String) {
        #expect(YouTubeResolver.firstVideoID(in: html) == nil)
    }
}
