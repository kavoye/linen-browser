// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import os
import WebKit

nonisolated enum AutofillDiagnostics {
    enum Event: String {
        case scriptReady, saveScriptReady, policyEnabled, policyDisabled, fieldSelected
        case lookupFailed, lookupCompleted, dropdownShown
        case editNoScope, editDisabled, editRecorded, submitNoEdits, submitInvalid, submitCaptured, saveOffered
        case submissionPending, submissionCompleted
    }

    private static let log = Logger(subsystem: "com.kavoye.Linen", category: "autofill")

    enum PolicyOperation: String {
        case password, save
    }

    static func policyFailed(_ operation: PolicyOperation, error: Error, isMainFrame: Bool) {
        #if DEBUG
        let failure = error as NSError
        let webKit = failure.domain == WKError.errorDomain
        // Exception messages can contain page text or URLs. Log only a known
        // exception class and the numeric WebKit code.
        let message = failure.userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
        let exception = ["SecurityError", "TypeError", "ReferenceError", "SyntaxError", "InvalidStateError"]
            .first { message.hasPrefix($0 + ":") } ?? "other"
        log.error("""
        policyFailed operation=\(operation.rawValue, privacy: .public) webKit=\(webKit, privacy: .public) \
        code=\(failure.code, privacy: .public) exception=\(exception, privacy: .public) mainFrame=\(isMainFrame, privacy: .public)
        """)
        #endif
    }

    static func note(_ event: Event, kind: AutofillSaveKind, count: Int = 0) {
        #if DEBUG
        log.notice("\(event.rawValue, privacy: .public) kind=\(kind.rawValue, privacy: .public) count=\(count, privacy: .public)")
        #endif
    }
}
