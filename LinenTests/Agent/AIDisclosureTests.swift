// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import Linen
import Testing

@MainActor
struct AIDisclosureTests {
    @Test func spokenPrefixIsSaidOnceThenDropped() {
        AIDisclosure.resetSpokenDisclosure()

        #expect(!AIDisclosure.spokenPrefix().isEmpty)
        #expect(AIDisclosure.spokenPrefix().isEmpty)
        #expect(AIDisclosure.spokenPrefix().isEmpty)
    }

    @Test func publicationConsentSaysWhoWroteTheText() {
        let disclosed = AgentActionConsent.body(
            label: "Post",
            category: .publication,
            site: "example.com",
            authoredByAI: true
        )

        #expect(disclosed.contains("written by AI"))
        #expect(disclosed.contains("under your name"))
    }

    @Test func consentStaysUnchangedWhenTheUserWroteTheText() {
        let plain = AgentActionConsent.body(
            label: "Post",
            category: .publication,
            site: "example.com",
            authoredByAI: false
        )

        #expect(!plain.contains("written by AI"))
        #expect(plain.contains("hidden instructions"))
    }

    /// The extra line is about publishing, so a purchase keeps the wording it
    /// had even when the agent filled the form.
    @Test func nonPublicationCategoriesAreNotAnnotated() {
        let purchase = AgentActionConsent.body(
            label: "Place order",
            category: .purchase,
            site: "example.com",
            authoredByAI: true
        )

        #expect(!purchase.contains("written by AI"))
    }

    @Test func agentRepliesAreAnnouncedAsAI() {
        let value = AskRestingContent.agent("The shop closes at six.")
            .accessibilityValue(fallback: "")

        #expect(value.hasPrefix("AI reply:"))
    }

    /// Article 50 in plain words: every disclosure says it is AI, and the
    /// onboarding copy also says it is not a person.
    @Test func disclosureCopySaysAINotAPerson() {
        for caption in [AIDisclosure.replyCaption, AIDisclosure.onboardingCaption, AIDisclosure.settingsCaption] {
            #expect(String(localized: caption).contains("AI"))
        }
        #expect(String(localized: AIDisclosure.onboardingCaption).contains("not a person"))
    }

    /// The copy warns, in one short sentence, that replies can be wrong.
    @Test func disclosureCopyWarnsAboutMistakes() {
        for caption in [AIDisclosure.replyCaption, AIDisclosure.onboardingCaption, AIDisclosure.settingsCaption] {
            let text = String(localized: caption)
            #expect(text.contains("can be wrong") || text.contains("can contain mistakes"))
        }
    }
}
