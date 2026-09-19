// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AutofillPasswordField: View {
    @Binding var password: String
    @State private var isRevealed = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case hidden, revealed
    }

    var body: some View {
        LabeledContent("Password") {
            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("Password", text: $password)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .revealed)
                    } else {
                        SecureField("Password", text: $password)
                            .focused($focusedField, equals: .hidden)
                    }
                }
                .labelsHidden()
                .privacySensitive()
                Button {
                    isRevealed.toggle()
                    focusedField = isRevealed ? .revealed : .hidden
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                .help(isRevealed ? "Hide password" : "Show password")
            }
        }
        .onDisappear { isRevealed = false }
    }
}
