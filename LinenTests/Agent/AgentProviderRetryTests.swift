// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

struct AgentProviderRetryTests {
    @Test func retriesAreBoundedAndHonorServerDelay() {
        let failure = OpenAIFailure(kind: .http, status: 429, retryAfter: 7)
        #expect(AgentProviderRetry.delay(for: failure, attempt: 0, remoteActionsEnabled: false) == 7)
        #expect(AgentProviderRetry.delay(for: failure, attempt: 2, remoteActionsEnabled: false) == nil)
        #expect(AgentProviderRetry.delay(for: failure, attempt: 0, remoteActionsEnabled: true) == nil)
        #expect(AgentProviderRetry.delay(for: OpenAIFailure(kind: .http, status: 503, retryAfter: 120), attempt: 0, remoteActionsEnabled: false) == nil)
    }

    @Test func streamedRateLimitsWithoutHTTPStatusCanRetry() {
        let failure = OpenAIFailure.event(["error": ["code": "rate_limit_exceeded"]])
        #expect(failure.isRateLimited)
        #expect(AgentProviderRetry.delay(for: failure, attempt: 0, remoteActionsEnabled: false, jitter: 0) == 2)
        #expect(AgentProviderRetry.delay(for: failure, attempt: 1, remoteActionsEnabled: false, jitter: 0) == 4)
        #expect(AgentProviderRetry.delay(for: failure, attempt: 2, remoteActionsEnabled: false) == nil)
        #expect(AgentProviderRetry.delay(for: failure, attempt: 0, remoteActionsEnabled: true) == nil)
        #expect(!OpenAIFailure(kind: .http, status: 429, code: "insufficient_quota").isRateLimited)
    }

    @Test func permanentErrorsAndUncertainDeliveryAreNotRetried() {
        for error in [OpenAIFailure(kind: .http, status: 401), .init(kind: .http, status: 429, code: "insufficient_quota"), .init(kind: .streamInterrupted)] {
            #expect(AgentProviderRetry.delay(for: error, attempt: 0, remoteActionsEnabled: false) == nil)
        }
        #expect(AgentProviderRetry.delay(for: URLError(.timedOut), attempt: 0, remoteActionsEnabled: false) == nil)
        #expect(AgentProviderRetry.delay(for: URLError(.networkConnectionLost), attempt: 0, remoteActionsEnabled: false) == nil)
        #expect(AgentProviderRetry.delay(for: URLError(.cannotConnectToHost), attempt: 1, remoteActionsEnabled: false, jitter: 0) == 2)
    }

    @Test func parsesRetryHeaders() {
        #expect(AgentProviderRetry.retryAfter("3") == 3)
        #expect(AgentProviderRetry.retryAfter(nil, milliseconds: "250") == 0.25)
        #expect(AgentProviderRetry.retryAfter("Thu, 01 Jan 1970 00:01:00 GMT", now: Date(timeIntervalSince1970: 0)) == 60)
        #expect(AgentProviderRetry.retryAfter("bad") == nil)
    }
}

@MainActor
@Suite(.serialized)
struct AgentRetryWorkflowTests {
    @Test func retryDoesNotRepeatAnExecutedAction() async throws {
        let fixture = HarnessFixture([.calls(["typeOnPage"]), .failure(OpenAIFailure(kind: .http, status: 503, retryAfter: 0)), .text("Finished.")])
        await fixture.run()
        #expect(fixture.state.calls == 1)
        #expect(fixture.model.requests.count == 3)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state == .completed)
    }

    @Test func streamedRateLimitRetriesWithoutRepeatingBrowserActions() async throws {
        let fixture = HarnessFixture([.calls(["typeOnPage"]),
                                     .failure(OpenAIFailure(kind: .http, code: "rate_limit_exceeded", retryAfter: 0)), .text("Finished."),
        ])
        await fixture.run()
        #expect(fixture.state.calls == 1)
        #expect(fixture.model.requests.count == 3)
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.state == .completed)
    }

    @Test func exhaustedRateLimitPausesWithoutAnotherSummaryRequest() async throws {
        let failure = OpenAIFailure(kind: .http, code: "rate_limit_exceeded", retryAfter: 0)
        let fixture = HarnessFixture([.failure(failure), .failure(failure), .failure(failure), .text("Must not request a summary")])
        await fixture.run()
        #expect(fixture.model.requests.count == 3)
        let trace = fixture.log.latestTrace(forTab: fixture.tabID)
        #expect(trace?.stopReason == .rateLimited)
        #expect(trace?.state == .paused)
        #expect(trace?.response.contains("rate limit") == true)
        #expect(trace?.diagnostics.events.last?.values["status"] == "rate_limited")
    }

    @Test func retryRespectsTheRequestLimit() async throws {
        let fixture = HarnessFixture([.failure(OpenAIFailure(kind: .http, status: 429, retryAfter: 0)), .text("Unexpected retry")],
                                     policy: .init(maxModelRequests: 1))
        await fixture.run()
        #expect(fixture.log.latestTrace(forTab: fixture.tabID)?.stopReason == .requestLimit)
        #expect(fixture.model.requests.filter { !$0.contains("browser task is paused") }.count == 1)
        #expect(fixture.state.calls == 0)
    }
}
