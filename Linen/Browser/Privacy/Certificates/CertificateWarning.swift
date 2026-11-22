// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
struct CertificateWarning: Identifiable {
    let id = UUID()
    let url: URL
    let warning: CertificateTrust.Warning

    var address: String {
        guard let host = url.host() else { return url.absoluteString }
        let shown = host.contains(":") ? "[\(host)]" : host
        guard let port = url.port else { return shown }
        return "\(shown):\(port)"
    }
}

extension BrowserTab {
    var certificateExceptions: [String: String] {
        context.settings.rememberedCertificates.merging(acceptedCertificates) { _, accepted in accepted }
    }

    func visitDespiteCertificateWarning(remembering: Bool) {
        guard let pending = certificateWarning else { return }
        if remembering {
            context.settings.rememberedCertificates[pending.warning.site] = pending.warning.fingerprint
        } else {
            acceptedCertificates[pending.warning.site] = pending.warning.fingerprint
        }
        certificateWarning = nil
        load(pending.url, transition: .reload)
    }

    func leaveCertificateWarning() {
        certificateWarning = nil
        if canGoBack {
            goBack()
        } else {
            load(SystemPages.start)
        }
    }
}
