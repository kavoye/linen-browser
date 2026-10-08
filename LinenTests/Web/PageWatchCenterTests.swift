// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@MainActor
@Suite(.serialized)
struct PageWatchCenterTests {
    private let page = URL(string: "https://shop.example/kettle")!
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @MainActor
    private final class Harness {
        var date: Date
        var text = "Kettle $54.99 In stock"
        var reads: Bool = true
        var allowed = true
        var verdict = PageWatchVerdict(met: false, state: "$54.99", message: "")
        var judged = 0
        var answers = true
        var classified: [PageWatchChange.Pair] = []
        var classification: (PageWatchChange.Pair) -> PageWatchVerdict = { _ in
            PageWatchVerdict(met: false, state: "", message: "")
        }
        var landed: URL?
        var hasModel = true
        var notices: [PageWatchCenter.Notice] = []
        var duringJudge: (() -> Void)?
        var center: PageWatchCenter!

        init(date: Date, file: URL? = nil) {
            self.date = date
            center = PageWatchCenter(
                file: file,
                schedules: false,
                fetch: { [unowned self] _ in
                    reads ? PageWatchReading(title: "Kettle", text: text, url: landed) : nil
                },
                judge: { [unowned self] _, _ in
                    judged += 1
                    duringJudge?()
                    return answers ? verdict : nil
                },
                classify: { [unowned self] _, pair in
                    classified.append(pair)
                    return answers ? classification(pair) : nil
                },
                canJudge: { [unowned self] in hasModel },
                notify: { [unowned self] _, notice in notices.append(notice) },
                allows: { [unowned self] _ in allowed }
            )
            center.now = { [unowned self] in self.date }
        }

        func advance(_ seconds: TimeInterval) {
            date += seconds
        }
    }

    private func watching(_ harness: Harness, minutes: Int = 60) async -> PageWatch? {
        let result = await harness.center.start(
            url: page, title: "", condition: "price below $50", everyMinutes: minutes
        )
        guard case .watching(let watch) = result else { return nil }
        return watch
    }

    @Test func aWatchStartsFromAReadingOfThePage() async throws {
        let harness = Harness(date: start)
        let watch = try #require(await watching(harness))

        #expect(watch.title == "Kettle")
        #expect(watch.state == "$54.99")
        #expect(watch.nextCheck == start + 3600)
        #expect(harness.center.watches == [watch])
    }

    @Test func aPageThatCannotBeReadIsNeverWatched() async {
        let harness = Harness(date: start)
        harness.reads = false
        let result = await harness.center.start(url: page, title: "", condition: "", everyMinutes: 60)

        #expect(result == .unreadable)
        #expect(harness.center.watches.isEmpty)
    }

    @Test func aConditionThatAlreadyHoldsSetsNoWatch() async {
        let harness = Harness(date: start)
        harness.verdict = PageWatchVerdict(met: true, state: "$42", message: "It is $42 already.")
        let result = await harness.center.start(url: page, title: "", condition: "price below $50", everyMinutes: 60)

        #expect(result == .alreadyMet(harness.verdict))
        #expect(harness.center.watches.isEmpty)
        #expect(harness.notices.isEmpty)
    }

    @Test func intervalsStayBetweenFiveMinutesAndADay() {
        #expect(PageWatch.interval(minutes: 1) == 300)
        #expect(PageWatch.interval(minutes: 90) == 5400)
        #expect(PageWatch.interval(minutes: 100_000) == 86_400)
    }

    @Test func anUnchangedPageSkipsTheModel() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.judged == 1)
        #expect(harness.center.watches.first?.nextCheck == start + 7200)
        #expect(harness.notices.isEmpty)
    }

    @Test func onlyDueWatchesAreChecked() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.text = "Kettle $49.99 In stock"
        harness.advance(1800)
        await harness.center.checkDue()

        #expect(harness.judged == 1)
    }

    @Test func aMetConditionNotifiesOnceAndEndsTheWatch() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.text = "Kettle $42.99 In stock"
        harness.verdict = PageWatchVerdict(met: true, state: "$42.99", message: "The price dropped to $42.99.")
        harness.advance(3600)
        await harness.center.checkDue()
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.notices == [.met("The price dropped to $42.99.")])
        #expect(harness.center.watches.isEmpty)
    }

    @Test func aChangeThatIsNotTheConditionUpdatesTheState() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.text = "Kettle $52.99 In stock"
        harness.verdict = PageWatchVerdict(met: false, state: "$52.99", message: "")
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.center.watches.first?.state == "$52.99")
        #expect(harness.notices.isEmpty)
    }

    @Test func threeFailedReadsInARowEndTheWatch() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.reads = false
        for _ in 1..<PageWatch.failureLimit {
            harness.advance(3600)
            await harness.center.checkDue()
        }
        #expect(harness.notices.isEmpty)
        #expect(harness.center.watches.first?.failures == PageWatch.failureLimit - 1)

        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.notices == [.unreachable])
        #expect(harness.center.watches.isEmpty)
    }

    @Test func aGoodReadClearsEarlierFailures() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.reads = false
        harness.advance(3600)
        await harness.center.checkDue()
        harness.reads = true
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.center.watches.first?.failures == 0)
    }

    @Test func aWatchEndsAfterItsLifetime() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.advance(PageWatch.lifetime)
        await harness.center.checkDue()

        #expect(harness.notices == [.expired])
        #expect(harness.center.watches.isEmpty)
    }

    @Test func aSiteBlockedForTheAssistantIsDroppedWithoutReading() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.allowed = false
        harness.text = "Kettle $42.99 In stock"
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.center.watches.isEmpty)
        #expect(harness.judged == 1)
        #expect(harness.notices.isEmpty)
    }

    @Test func stoppingAWatchMidCheckSendsNothing() async throws {
        let harness = Harness(date: start)
        let watch = try #require(await watching(harness))
        harness.text = "Kettle $42.99 In stock"
        harness.verdict = PageWatchVerdict(met: true, state: "$42.99", message: "Dropped.")
        harness.duringJudge = { harness.center.stop(watch.id) }
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.notices.isEmpty)
        #expect(harness.center.watches.isEmpty)
    }

    @Test func watchesAreFoundByIDTitleOrCondition() async throws {
        let harness = Harness(date: start)
        let watch = try #require(await watching(harness))

        #expect(harness.center.matching(watch.id.uuidString) == [watch])
        #expect(harness.center.matching("kettle") == [watch])
        #expect(harness.center.matching("below $50") == [watch])
        #expect(harness.center.matching("teapot").isEmpty)
        #expect(harness.center.matching("") == [watch])
    }

    @Test func watchesSurviveARelaunch() async throws {
        let file = TestFiles.directory
            .appendingPathComponent("linen-watches-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let harness = Harness(date: start, file: file)
        let watch = try #require(await watching(harness))

        var reloaded: [PageWatch] = []
        for _ in 0..<50 where reloaded.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
            reloaded = Harness(date: start, file: file).center.watches
        }
        #expect(reloaded == [watch])
    }

    // MARK: - Any change

    private func watchingAnyChange(_ harness: Harness) async -> PageWatch? {
        let result = await harness.center.start(url: page, title: "", condition: "", everyMinutes: 60)
        guard case .watching(let watch) = result else { return nil }
        return watch
    }

    @Test func anyChangeNeverAsksTheModelAboutTheFirstReading() async throws {
        let harness = Harness(date: start)
        harness.verdict = PageWatchVerdict(met: true, state: "200 hp", message: "Now 200 hp, up from 150 hp.")
        let watch = try #require(await watchingAnyChange(harness))

        #expect(harness.judged == 0)
        #expect(harness.classified.isEmpty)
        #expect(watch.snapshot == harness.text)
        #expect(harness.notices.isEmpty)
    }

    @Test func anyChangeShowsTheModelOnlyWhatChanged() async throws {
        let harness = Harness(date: start)
        harness.text = "Kettle. Price $54.99. In stock."
        _ = try #require(await watchingAnyChange(harness))
        harness.text = "Kettle. Price $49.99. In stock."
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.classified == [PageWatchChange.Pair(removed: "Price $54.99.", added: "Price $49.99.")])
        #expect(harness.judged == 0)
    }

    @Test func anyChangeIgnoresNoiseButKeepsTheNewText() async throws {
        let harness = Harness(date: start)
        harness.text = "Kettle. Views: 10."
        _ = try #require(await watchingAnyChange(harness))
        harness.text = "Kettle. Views: 11."
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.notices.isEmpty)
        #expect(harness.center.watches.first?.snapshot == "Kettle. Views: 11.")
    }

    @Test func anyChangeNotifiesWhenTheChangeMatters() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watchingAnyChange(harness))
        harness.text = "Kettle $49.99 In stock"
        harness.classification = { _ in PageWatchVerdict(met: true, state: "", message: "The price is now $49.99.") }
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.notices == [.met("The price is now $49.99.")])
        #expect(harness.center.watches.isEmpty)
    }

    @Test func noWatchStartsWithoutAModel() async {
        let harness = Harness(date: start)
        harness.hasModel = false
        let result = await harness.center.start(url: page, title: "", condition: "", everyMinutes: 60)

        #expect(result == .noModel)
        #expect(harness.center.watches.isEmpty)
    }

    @Test func aMissingModelPostponesTheCheckWithoutEndingTheWatch() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.text = "Kettle $49.99 In stock"
        harness.hasModel = false
        for _ in 0..<PageWatch.failureLimit {
            harness.advance(3600)
            await harness.center.checkDue()
        }
        harness.hasModel = true
        harness.answers = false
        for _ in 0..<PageWatch.failureLimit {
            harness.advance(3600)
            await harness.center.checkDue()
        }

        let watch = try #require(harness.center.watches.first)
        #expect(harness.notices.isEmpty)
        #expect(watch.failures == 0)
        #expect(watch.nextCheck == harness.date + 3600)
        #expect(watch.snapshot == "Kettle $54.99 In stock")
    }

    @Test func aChangeListsOnlyTheSentencesThatDiffer() {
        let change = PageWatchChange(
            from: "Intro. Engine: 200 hp. Price from 1.3M. Outro!",
            to: "Intro. Engine: 210 hp. Price from 1.3M. Outro! New section."
        )

        #expect(change.removed == ["Engine: 200 hp."])
        #expect(change.added == ["Engine: 210 hp.", "New section."])
        #expect(PageWatchChange(from: "Same. Text.", to: "Same.  Text.").isEmpty)
    }

    @Test func aChangePairsTextFromTheSamePlace() {
        let change = PageWatchChange(
            from: "Updated May 1.\nIntro.\nBody.\nPrice $54.99.",
            to: "Intro.\nBody.\nPrice $49.99."
        )

        #expect(change.pairs == [
            .init(removed: "Updated May 1.", added: nil),
            .init(removed: "Price $54.99.", added: "Price $49.99."),
        ])
    }

    @Test func aLongUnpunctuatedPageStillReportsItsChange() async throws {
        let harness = Harness(date: start)
        let filler = Array(repeating: "Add to cart Free shipping Reviews", count: 80).joined(separator: " ")
        harness.text = "Kettle\n$54.99\nIn stock\n" + filler
        _ = try #require(await watchingAnyChange(harness))
        harness.text = "Kettle\n$49.99\nIn stock\n" + filler
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.classified == [PageWatchChange.Pair(removed: "$54.99", added: "$49.99")])
    }

    @Test func aRealChangeIsNotHiddenByNoiseBesideIt() async throws {
        let harness = Harness(date: start)
        harness.text = "Views: 10\nPrice $54.99"
        _ = try #require(await watchingAnyChange(harness))
        harness.text = "Views: 11\nPrice $49.99"
        harness.classification = { pair in
            pair.added == "Price $49.99"
                ? PageWatchVerdict(met: true, state: "", message: "Price dropped.")
                : PageWatchVerdict(met: false, state: "", message: "")
        }
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.classified.count == 2)
        #expect(harness.notices == [.met("Price dropped.")])
    }

    @Test func tooManyChangesOfNoiseDoNotNotify() async throws {
        let harness = Harness(date: start)
        harness.text = (1...40).map { "Line \($0)" }.joined(separator: "\n")
        _ = try #require(await watchingAnyChange(harness))
        harness.text = (1...40).map { "Row \($0)" }.joined(separator: "\n")
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.classified.count == PageWatchCenter.classifyLimit)
        #expect(harness.notices.isEmpty)
        #expect(harness.center.watches.first?.snapshot == harness.text)
    }

    @Test func aRedirectAwayFromThePageIsAFailedRead() async throws {
        let harness = Harness(date: start)
        harness.landed = page
        _ = try #require(await watchingAnyChange(harness))
        harness.landed = URL(string: "https://shop.example/login?return_to=%2Fkettle")
        harness.text = "Sign in to continue"
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.classified.isEmpty)
        #expect(harness.center.watches.first?.failures == 1)
        #expect(harness.notices.isEmpty)
    }

    @Test func aPageThatRedirectsAtTheStartIsNotWatched() async {
        let harness = Harness(date: start)
        harness.landed = URL(string: "https://shop.example/login")
        let result = await harness.center.start(url: page, title: "", condition: "", everyMinutes: 60)

        #expect(result == .unreadable)
    }

    @Test func samePageIgnoresTrailingSlashQueryAndHostCase() {
        let watched = URL(string: "https://Shop.example/kettle")!
        #expect(PageWatch.isSamePage(URL(string: "https://shop.example/kettle/?ref=1")!, watched))
        #expect(!PageWatch.isSamePage(URL(string: "https://shop.example/login")!, watched))
        #expect(!PageWatch.isSamePage(URL(string: "https://login.example/kettle")!, watched))
    }

    @Test func samePageKeepsTheWatchedQuery() {
        let watched = URL(string: "https://shop.example/item?id=123")!
        #expect(PageWatch.isSamePage(URL(string: "https://shop.example/item?id=123&ref=1")!, watched))
        #expect(!PageWatch.isSamePage(URL(string: "https://shop.example/item?id=999")!, watched))
        #expect(!PageWatch.isSamePage(URL(string: "https://shop.example/item")!, watched))
    }

    @Test func aWatchStoppedByShutDownMidCheckDoesNothingMore() async throws {
        let harness = Harness(date: start)
        _ = try #require(await watching(harness))
        harness.text = "Kettle $42.99 In stock"
        harness.verdict = PageWatchVerdict(met: true, state: "$42.99", message: "Dropped.")
        harness.duringJudge = { harness.center.shutDown() }
        harness.advance(3600)
        await harness.center.checkDue()

        #expect(harness.notices.isEmpty)
        #expect(harness.center.watches.isEmpty)
    }

    @Test func aSleepingScheduleDoesNotKeepTheCenterAlive() async throws {
        weak var released: PageWatchCenter?
        do {
            let center = PageWatchCenter(
                file: nil,
                fetch: { _ in PageWatchReading(title: "Kettle", text: "Kettle $54.99 In stock") },
                judge: { _, _ in PageWatchVerdict(met: false, state: "$54.99", message: "") },
                classify: { _, _ in nil },
                notify: { _, _ in }
            )
            released = center
            let result = await center.start(url: page, title: "", condition: "price below $50", everyMinutes: 60)
            guard case .watching = result else {
                Issue.record("Expected a watch")
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(await waitUntil { released == nil })
    }
}
