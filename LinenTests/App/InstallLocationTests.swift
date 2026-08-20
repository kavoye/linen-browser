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

    private func expectMove(
        _ decision: InstallLocation.Decision,
        from expectedFrom: String,
        to expectedTo: String,
        isReadOnlySource expectedReadOnly: Bool = false,
        _ comment: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case let .offerMove(from, to, isReadOnlySource) = decision else {
            Issue.record(comment, sourceLocation: sourceLocation)
            return
        }
        #expect(from.path == expectedFrom, sourceLocation: sourceLocation)
        #expect(to.path == expectedTo, sourceLocation: sourceLocation)
        #expect(isReadOnlySource == expectedReadOnly, sourceLocation: sourceLocation)
    }

    @Test func anInstalledCopyIsLeftAlone() {
        #expect(decide(bundle: "/Applications/Linen.app") == .installed)
        #expect(decide(bundle: "/Applications/Browsers/Linen.app") == .installed)
        #expect(decide(bundle: "/Users/tester/Applications/Linen.app") == .installed)
    }

    @Test func aCopyInDownloadsIsOfferedTheMove() {
        expectMove(
            decide(bundle: "/Users/tester/Downloads/Linen.app"),
            from: "/Users/tester/Downloads/Linen.app",
            to: "/Applications/Linen.app",
            "Expected the move to be offered from Downloads"
        )
    }

    @Test func aMountedImageIsCopiedRatherThanMoved() {
        expectMove(
            decide(bundle: "/Volumes/Linen/Linen.app", isReadOnlySource: true),
            from: "/Volumes/Linen/Linen.app",
            to: "/Applications/Linen.app",
            isReadOnlySource: true,
            "Expected the move to be offered from a mounted image"
        )
    }

    @Test func translocationIsJudgedByTheOriginal() {
        let translocated = "/private/var/folders/x1/AppTranslocation/A-B-C/d/Linen.app"

        #expect(decide(
            bundle: translocated,
            originalBundle: "/Applications/Linen.app"
        ) == .installed)

        expectMove(
            decide(bundle: translocated, originalBundle: "/Users/tester/Downloads/Linen.app"),
            from: "/Users/tester/Downloads/Linen.app",
            to: "/Applications/Linen.app",
            "Expected the move to be judged by the original copy"
        )
    }

    @Test func anUnresolvedOriginalStillOffersTheMove() {
        let translocated = "/private/var/folders/x1/AppTranslocation/A-B-C/d/Linen.app"

        expectMove(
            decide(bundle: translocated, isReadOnlySource: true),
            from: translocated,
            to: "/Applications/Linen.app",
            isReadOnlySource: true,
            "Expected the move to be offered from a translocated mount"
        )
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
