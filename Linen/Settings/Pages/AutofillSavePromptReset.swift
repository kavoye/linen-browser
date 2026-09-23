// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AutofillSavePromptReset: View {
    let kind: AutofillSaveKind
    let profileID: UUID
    @State private var isBusy = false
    @State private var showsError = false

    var body: some View {
        SettingsCard {
            DetailRow(title: "Save suggestions", caption: "Restore prompts on excluded sites.") {
                SettingsButton(title: "Reset") {
                    isBusy = true
                    Task {
                        do {
                            try await Task.detached { [kind, profileID] in
                                try AutofillSaveIndex.resetBlocks(kind: kind, profileID: profileID)
                            }.value
                            AutofillSaveCoordinator.shared.resetDismissals(kind: kind, profileID: profileID)
                        } catch { showsError = true }
                        isBusy = false
                    }
                }
                .disabled(isBusy || profileID == Profile.privateID)
            }
        }
        .alert("Couldn’t Reset Save Suggestions", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        }
    }
}
