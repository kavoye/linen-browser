// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
final class TabEvents {
    var onNavigationStarted: ((URL) -> Void)?
    var onNavigationFinished: ((Bool) -> Void)?
    var onNavigationOutsideExtension: ((URL) -> Void)?
    var onSameDocumentNavigation: (() -> Void)?
    var onInPageMove: (() -> Void)?
    var onTitleChanged: (() -> Void)?
    var onNewWindow: ((WKWebView, Bool) -> Void)?
    var onOpenInNewTab: ((URL, Bool) -> Void)?
    var onOpenInNewWindow: ((URL, Bool, Bool) -> Void)?
    var onOpenInPeek: ((URL, CGPoint) -> Void)?
    var onSummarizeLink: ((URL, CGPoint) -> Void)?
    var onCloseRequested: (() -> Void)?
    var onPictureInPictureChanged: ((Bool) -> Void)?
    var onPictureReturnExpected: (() -> Void)?
    var onDownload: ((WKDownload, URL?) -> Void)?
    var onPageColorWillChange: (() -> Void)?
    var onSaveDocument: ((Data, String, URL?, Bool) async -> Void)?
    var onLinkHovered: ((URL?, NSEvent.ModifierFlags, CGPoint) -> Void)?
    var onContentProcessTerminated: (() -> Void)?
    var onLocationRevoked: (() -> Void)?
    var isShown: (() -> Bool)?

    func removeAll() {
        onNavigationStarted = nil
        onNavigationFinished = nil
        onNavigationOutsideExtension = nil
        onSameDocumentNavigation = nil
        onInPageMove = nil
        onTitleChanged = nil
        onNewWindow = nil
        onOpenInNewTab = nil
        onOpenInNewWindow = nil
        onOpenInPeek = nil
        onSummarizeLink = nil
        onCloseRequested = nil
        onPictureInPictureChanged = nil
        onPictureReturnExpected = nil
        onDownload = nil
        onSaveDocument = nil
        onLinkHovered = nil
        onContentProcessTerminated = nil
        onLocationRevoked = nil
        isShown = nil
    }
}
