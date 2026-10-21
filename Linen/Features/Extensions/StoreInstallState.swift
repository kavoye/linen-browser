// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

enum StoreInstallState: Equatable {
    case idle
    case installing(id: String)
    case installed(id: String)
    case failed(id: String, message: String)
}
