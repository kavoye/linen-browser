// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

/// The prompt must fire for a copy that runs from the wrong place, and stay
/// quiet for every copy that is already installed or that a developer built.
struct InstallLocationTests {
    private let applications = [
        URL(fileURLWithPath: "/Users/tester/Applications", isDirectory: true),
        URL(fileURLWithPath: "/Applications", isDirectory: true),
    ]

    private let destinationDirectory = URL(fileURLWithPath: "/Applications", isDirectory: true)

    private func decide(
        bundle: String,
        originalBundle: String? = nil,
        isReadOnlySource: Bool = false,
        hasDeclined: Bool = false,
        isDebugBuild: Bool = false
    ) -> InstallLocation.Decision {
        InstallLocation.decide(
            bundle: URL(fileURLWithPath: bundle),
            originalBundle: originalBundle.map { URL(fileURLWithPath: $0) },
            applicationsDirectories: applications,
            destinationDirectory: destinationDirectory,
            isReadOnlySource: isReadOnlySource,
            hasDeclined: hasDeclined,
            isDebugBuild: isDebugBuild
        )
    }

    @Test func anInstalledCopyIsLeftAlone() {
        #expect(decide(bundle: "/Applications/Linen.app") == .installed)
        #expect(decide(bundle: "/Applications/Browsers/Linen.app") == .installed)
        #expect(decide(bundle: "/Users/tester/Applications/Linen.app") == .installed)
    }

    @Test func aCopyInDownloadsIsOfferedTheMove() {
        let decision = decide(bundle: "/Users/tester/Downloads/Linen.app")

        #expect(decision == .offerMove(
            from: URL(fileURLWithPath: "/Users/tester/Downloads/Linen.app"),
            to: URL(fileURLWithPath: "/Applications/Linen.app"),
            isReadOnlySource: false
        ))
    }

    @Test func aMountedImageIsCopiedRatherThanMoved() {
        let decision = decide(bundle: "/Volumes/Linen/Linen.app", isReadOnlySource: true)

        guard case let .offerMove(_, _, isReadOnlySource) = decision else {
            Issue.record("Expected the move to be offered from a mounted image")
            return
        }
        #expect(isReadOnlySource)
    }

    @Test func translocationIsJudgedByTheOriginal() {
        let translocated = "/private/var/folders/x1/AppTranslocation/A-B-C/d/Linen.app"

        #expect(decide(
            bundle: translocated,
            originalBundle: "/Applications/Linen.app"
        ) == .installed)

        #expect(decide(
            bundle: translocated,
            originalBundle: "/Users/tester/Downloads/Linen.app"
        ) == .offerMove(
            from: URL(fileURLWithPath: "/Users/tester/Downloads/Linen.app"),
            to: URL(fileURLWithPath: "/Applications/Linen.app"),
            isReadOnlySource: false
        ))
    }

    @Test func anUnresolvedOriginalStillOffersTheMove() {
        let translocated = "/private/var/folders/x1/AppTranslocation/A-B-C/d/Linen.app"
        let decision = decide(bundle: translocated, isReadOnlySource: true)

        guard case let .offerMove(from, to, _) = decision else {
            Issue.record("Expected the move to be offered from a translocated mount")
            return
        }
        #expect(from == URL(fileURLWithPath: translocated))
        #expect(to == URL(fileURLWithPath: "/Applications/Linen.app"))
    }

    @Test func askingStopsAfterTheFirstRefusal() {
        #expect(decide(bundle: "/Users/tester/Downloads/Linen.app", hasDeclined: true) == .skip)
    }

    @Test func aRefusalNeverHidesAnInstalledCopy() {
        #expect(decide(bundle: "/Applications/Linen.app", hasDeclined: true) == .installed)
    }

    @Test func aDebugBuildNeverOffersToMoveItself() {
        #expect(decide(bundle: "/Users/tester/Library/Developer/Xcode/DerivedData/Linen.app", isDebugBuild: true) == .skip)
    }
}
