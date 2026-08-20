// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct Acknowledgement: Decodable, Identifiable {
    let name: String
    let version: String
    let url: String
    let license: String
    let text: String

    var id: String {
        name
    }
}

enum Acknowledgements {
    static let all: [Acknowledgement] = load()

    private struct Payload: Decodable {
        let packages: [Acknowledgement]
    }

    private static func load() -> [Acknowledgement] {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return [] }

        return payload.packages
    }
}

struct AcknowledgementsPage: View {
    let coordinator: AppCoordinator
    let onBack: () -> Void

    var body: some View {
        SettingsButton(title: "About", symbol: "chevron.left", action: onBack)
            .frame(maxWidth: .infinity, alignment: .leading)

        SettingsPageHeader(title: "Acknowledgements")

        SettingsCard {
            ForEach(Array(Acknowledgements.all.enumerated()), id: \.element.id) { index, package in
                if index > 0 {
                    RowSeparator()
                }

                AcknowledgementRow(package: package, coordinator: coordinator)
            }
        }
    }
}

private struct AcknowledgementRow: View {
    let package: Acknowledgement
    let coordinator: AppCoordinator

    @State private var reading = false

    var body: some View {
        DetailRow(
            verbatimTitle: package.name,
            verbatimCaption: "\(package.license) · \(package.version)"
        ) {
            HStack(spacing: 8) {
                SettingsButton(title: "License") {
                    reading = true
                }
                .popover(isPresented: $reading, arrowEdge: .bottom) {
                    LicenseText(package: package)
                }

                IconButton(symbol: "arrow.up.right", help: "Open the project page") {
                    coordinator.openNewTab(url: URL(string: package.url))
                }
            }
        }
    }
}

private struct LicenseText: View {
    let package: Acknowledgement

    var body: some View {
        ScrollView {
            Text(verbatim: package.text)
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(width: 460, height: 340)
    }
}
