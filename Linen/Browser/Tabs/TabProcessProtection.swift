// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum TabProtectionReason: Equatable {
    case editedForm
    case activeDownload
    case deviceAccess
    case agentWorking
    case mediaPlayback
    case visibleInSplit
    case alwaysKeepActive
    case privateBrowsing
    case extensionPage
}

enum TabReclaimState: Equatable {
    case none
    case unloaded
    case reloading
}
