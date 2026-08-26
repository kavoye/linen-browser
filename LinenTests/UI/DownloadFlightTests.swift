// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// A file appears to fall from where it was clicked into the downloads
/// button. The flight only makes sense when both ends are known and the
/// click is recent enough to be the reason the download started.
@MainActor
struct DownloadFlightTests {
    private let click = CGPoint(x: 120, y: 300)
    private let button = CGPoint(x: 40, y: 780)

    @Test func aClickAndAButtonMakeAFlight() {
        let flights = DownloadFlights()
        flights.target = button
        flights.noteClick(at: click)

        flights.launch()

        #expect(flights.flights.count == 1)
        #expect(flights.flights.first?.from == click)
        #expect(flights.flights.first?.to == button)
    }

    @Test func nothingFliesBeforeTheButtonHasSaidWhereItIs() {
        let flights = DownloadFlights()
        flights.noteClick(at: click)

        flights.launch()

        #expect(flights.flights.isEmpty)
    }

    @Test func aDownloadNobodyClickedForDoesNotFly() {
        let flights = DownloadFlights()
        flights.target = button

        flights.launch()

        #expect(flights.flights.isEmpty, "a download that began on its own has no starting point")
    }

    /// A download that starts a minute after the last click did not come from
    /// it — a page can begin one whenever it likes.
    @Test func aStaleClickIsNotTheReasonADownloadStarted() {
        let flights = DownloadFlights()
        let clickedAt = Date()
        flights.target = button
        flights.noteClick(at: click, on: clickedAt)

        flights.launch(now: clickedAt.addingTimeInterval(60))

        #expect(flights.flights.isEmpty)
    }

    @Test func aClickWithinTheWindowStillCounts() {
        let flights = DownloadFlights()
        let clickedAt = Date()
        flights.target = button
        flights.noteClick(at: click, on: clickedAt)

        flights.launch(now: clickedAt.addingTimeInterval(2))

        #expect(flights.flights.count == 1)
    }

    @Test func aClickOnTheButtonItselfHasNowhereToFly() {
        let flights = DownloadFlights()
        flights.target = button
        flights.noteClick(at: button)

        flights.launch()

        #expect(flights.flights.isEmpty)
    }
}
