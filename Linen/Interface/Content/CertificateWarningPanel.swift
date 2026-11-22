// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct CertificateWarningPanel: View {
    let tab: BrowserTab
    let pending: CertificateWarning
    @State private var remembers = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.warning, Theme.danger)
                .padding(.bottom, 14)

            Text("This connection isn’t private")
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 6)

            Text("Linen can’t verify the certificate for \(pending.address). Someone may be impersonating this website.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $remembers) {
                Text("Always trust this certificate for \(pending.address)")
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)

            HStack(spacing: 8) {
                Button("Show Certificate") {
                    CertificatePanel.show(pending.warning.trust, host: pending.url.host())
                }
                Spacer(minLength: 16)
                Button("Visit Website") {
                    tab.visitDespiteCertificateWarning(remembering: remembers)
                }
                Button("Go Back") {
                    tab.leaveCertificateWarning()
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 22)
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(Theme.Wash.faint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .id(pending.id)
        .onAppear(perform: visitIfAllowed)
        .onChange(of: tab.context.settings.allowsCertificateExceptions) {
            visitIfAllowed()
        }
    }

    private func visitIfAllowed() {
        guard tab.context.settings.allowsCertificateExceptions else { return }
        tab.visitDespiteCertificateWarning(remembering: false)
    }
}
