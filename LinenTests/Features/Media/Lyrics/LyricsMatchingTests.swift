// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct LyricsMatchingTests {
    private func queries(_ title: String, _ artist: String, album: String = "", duration: Double = 233)
        -> [LyricsQuery] {
        LyricsNaming.queries(title: title, artist: artist, album: album, duration: duration)
    }

    // MARK: - Cleaning what a page reports

    @Test func productionNoiseLeavesTheTitle() {
        #expect(LyricsNaming.cleanTitle("Creep (Official Music Video)") == "Creep")
        #expect(LyricsNaming.cleanTitle("Creep [Official Audio]") == "Creep")
        #expect(LyricsNaming.cleanTitle("Creep (Lyrics)") == "Creep")
        #expect(LyricsNaming.cleanTitle("Creep (Remastered 2011)") == "Creep")
        #expect(LyricsNaming.cleanTitle("Creep (4K HD)") == "Creep")
    }

    @Test func aBracketThatChangesTheWordsIsKept() {
        #expect(LyricsNaming.cleanTitle("Get Lucky (feat. Pharrell Williams)") == "Get Lucky (feat. Pharrell Williams)")
        #expect(LyricsNaming.cleanTitle("Creep (Acoustic)") == "Creep (Acoustic)")
        #expect(LyricsNaming.cleanTitle("Creep (Live at Glastonbury)") == "Creep (Live at Glastonbury)")
    }

    @Test func aChannelNameIsNotAnArtist() {
        #expect(LyricsNaming.cleanArtist("Radiohead - Topic") == "Radiohead")
        #expect(LyricsNaming.cleanArtist("ArianaGrandeVevo") == "ArianaGrande")
        #expect(LyricsNaming.cleanArtist("Daft Punk") == "Daft Punk")
    }

    // MARK: - Building the lookup

    @Test func aTitleThatRepeatsTheArtistIsSplitOnce() {
        let built = queries("Daft Punk - Something About Us", "Daft Punk", album: "Discovery")

        #expect(built.count == 2)
        #expect(built[0].track == "Something About Us")
        #expect(built[0].artist == "Daft Punk")
        #expect(built[0].album == "Discovery")
    }

    @Test func aDashedTitleOutranksTheChannelItWasUploadedTo() {
        let built = queries("Radiohead - Creep (Official Video)", "Alt Rock Archive")

        #expect(built[0].track == "Creep")
        #expect(built[0].artist == "Radiohead")
        #expect(built.contains { $0.artist == "Alt Rock Archive" && $0.track == "Creep" })
    }

    @Test func aPlainTitleKeepsTheArtistThePageReported() {
        let built = queries("Something About Us", "Daft Punk")

        #expect(built.count == 1)
        #expect(built[0].track == "Something About Us")
        #expect(built[0].artist == "Daft Punk")
    }

    @Test func withoutAnArtistTheDashStillNamesOne() {
        let built = queries("Radiohead — Creep", "")

        #expect(built[0].artist == "Radiohead")
        #expect(built[0].track == "Creep")
    }

    @Test func aQueryWithoutATrackIsNeverBuilt() {
        #expect(queries("", "Daft Punk").isEmpty)
        #expect(queries("(Official Video)", "").isEmpty)
    }

    @Test func everyQueryIsDistinct() {
        let built = queries("Creep - Creep", "Creep")

        #expect(Set(built).count == built.count)
    }

    // MARK: - Ranking what came back

    private func score(_ track: String, _ artist: String, _ duration: Double, _ query: LyricsQuery) -> Double? {
        LyricsNaming.score(track: track, artist: artist, duration: duration, against: query)
    }

    @Test func aTrackOfTheWrongLengthIsRefused() {
        let wanted = LyricsQuery(track: "Creep", artist: "Radiohead", album: "", duration: 239)

        #expect(score("Creep", "Radiohead", 239, wanted) != nil)
        #expect(score("Creep", "Radiohead", 300, wanted) == nil)
    }

    @Test func aTrackWithNoSharedWordsIsRefused() {
        let wanted = LyricsQuery(track: "Creep", artist: "Radiohead", album: "", duration: 239)

        #expect(score("Karma Police", "Radiohead", 239, wanted) == nil)
    }

    @Test func theClosestLengthWins() {
        let wanted = LyricsQuery(track: "Creep", artist: "Radiohead", album: "", duration: 239)
        let close = score("Creep", "Radiohead", 239, wanted)
        let further = score("Creep", "Radiohead", 249, wanted)

        #expect(close != nil && further != nil)
        #expect(close! > further!)
    }

    @Test func theRightArtistWinsOverACoverBand() {
        let wanted = LyricsQuery(track: "Creep", artist: "Radiohead", album: "", duration: 239)
        let real = score("Creep", "Radiohead", 239, wanted)
        let cover = score("Creep", "Babies Go Radiohead", 239, wanted)

        #expect(real != nil && cover != nil)
        #expect(real! > cover!)
    }

    // MARK: - Decoding

    @Test func aSearchResultRanksSyncedLyricsFirst() throws {
        let payload = """
        [
          {"id": 1, "trackName": "Creep", "artistName": "Radiohead", "albumName": "Pablo Honey",
           "duration": 239.0, "instrumental": false, "plainLyrics": "words", "syncedLyrics": null},
          {"id": 2, "trackName": "Creep", "artistName": "Radiohead", "albumName": "Pablo Honey",
           "duration": 239.0, "instrumental": false, "plainLyrics": "words",
           "syncedLyrics": "[00:01.00] words"}
        ]
        """
        let wanted = LyricsQuery(track: "Creep", artist: "Radiohead", album: "", duration: 239)

        let ranked = LRCLIB.ranked(in: Data(payload.utf8), against: wanted)

        #expect(ranked.map(\.id) == [2, 1])
    }

    @Test func aResultWithoutAnyWordsIsDropped() {
        let payload = """
        [{"id": 3, "trackName": "Creep", "artistName": "Radiohead", "albumName": "",
          "duration": 239.0, "instrumental": true, "plainLyrics": null, "syncedLyrics": null}]
        """
        let wanted = LyricsQuery(track: "Creep", artist: "Radiohead", album: "", duration: 239)

        #expect(LRCLIB.ranked(in: Data(payload.utf8), against: wanted).isEmpty)
    }

    @Test func aMissingFieldDoesNotBreakTheDecode() {
        let payload = """
        {"id": 4, "trackName": "Creep", "artistName": "Radiohead", "duration": 239.0,
         "plainLyrics": "words"}
        """

        let match = LRCLIB.match(in: Data(payload.utf8))

        #expect(match?.album == "")
        #expect(match?.isInstrumental == false)
        #expect(match?.hasWords == true)
    }

    @Test func matchesThatCarryTheSameWordsAreOfferedOnce() {
        let payload = """
        [
          {"id": 1, "trackName": "Before You Go", "artistName": "Lewis Capaldi",
           "albumName": "Divinely Uninspired", "duration": 215.0, "instrumental": false,
           "plainLyrics": "words", "syncedLyrics": "[00:01.00] words"},
          {"id": 2, "trackName": "Before You Go (Piano Version)", "artistName": "Lewis Capaldi",
           "albumName": "LOVE", "duration": 215.0, "instrumental": false,
           "plainLyrics": "words", "syncedLyrics": "[00:01.00] words"},
          {"id": 3, "trackName": "Before You Go", "artistName": "Lewis Capaldi",
           "albumName": "Sad Songs", "duration": 216.0, "instrumental": false,
           "plainLyrics": "other", "syncedLyrics": "[00:02.00] other"}
        ]
        """
        let wanted = LyricsQuery(
            track: "Before You Go", artist: "Lewis Capaldi", album: "", duration: 215
        )

        let ranked = LRCLIB.ranked(in: Data(payload.utf8), against: wanted)

        #expect(ranked.count == 2, "the two carrying identical words collapse into one")
        #expect(Set(ranked.map(\.wordsKey)).count == 2)
    }

    @Test func aMatchIsNamedByWhatSetsItApart() {
        let match = LyricsMatch(
            id: 1,
            track: "Before You Go",
            artist: "Lewis Capaldi",
            album: "LOVE",
            duration: 215,
            synced: "",
            plain: "words",
            isInstrumental: false
        )

        #expect(match.label == "Before You Go · LOVE · 3:35")
    }

    @Test func aMatchWithNothingToAddIsJustItsName() {
        let match = LyricsMatch(
            id: 1,
            track: "Creep",
            artist: "Radiohead",
            album: "Creep",
            duration: 0,
            synced: "",
            plain: "words",
            isInstrumental: false
        )

        #expect(match.label == "Creep")
    }

    @Test func theUserAgentNamesTheProject() {
        #expect(LRCLIB.userAgent.hasPrefix("Linen/"))
        #expect(LRCLIB.userAgent.contains("github.com/kavoye"))
    }
}

/// The shortlist a search answers with. Every row that scores is a real
/// candidate, so the list has to be cut somewhere the picker can show.
struct LyricsShortlistTests {
    private let query = LyricsQuery(track: "Creep", artist: "Radiohead", album: "", duration: 0)

    private func rows(_ count: Int) -> Data {
        let rows = (0..<count).map { index in
            """
            {"id":\(index),"trackName":"Creep","artistName":"Radiohead","albumName":"Pablo Honey",\
            "duration":233,"instrumental":false,"plainLyrics":"verse \(index)","syncedLyrics":""}
            """
        }
        return Data("[\(rows.joined(separator: ","))]".utf8)
    }

    @Test func everyRowThatScoresIsRanked() {
        #expect(LRCLIB.ranked(in: rows(5), against: query).count == 5)
    }

    @Test func theShortlistStopsAtEight() {
        #expect(LRCLIB.ranked(in: rows(9), against: query).count == 8)
        #expect(LRCLIB.ranked(in: rows(40), against: query).count == 8)
    }

    @Test func aRowForAnotherSongIsNoChoice() {
        let other = Data("""
            [{"id":1,"trackName":"Paranoid Android","artistName":"Radiohead","albumName":"",\
            "duration":233,"instrumental":false,"plainLyrics":"please could you stop","syncedLyrics":""}]
            """.utf8)
        #expect(LRCLIB.ranked(in: other, against: query).isEmpty)
    }

    @Test func aPayloadItCannotReadRanksNothing() {
        #expect(LRCLIB.ranked(in: Data("not json".utf8), against: query).isEmpty)
    }
}
