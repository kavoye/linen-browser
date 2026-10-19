// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import SwiftUI

struct AgentToolsPage: View {
    @Bindable var model: IntelligenceViewModel

    var body: some View {
        if let inspected = model.inspectedProvider {
            SubPageHeader(verbatimBackTitle: inspected.name, onBack: { model.leaveTools() }) {
                resetButton
            }
        } else {
            SubPageHeader(backTitle: "Assistant", onBack: { model.leaveTools() }) {
                resetButton
            }
        }

        SettingsPageHeader(
            title: "Tools",
            caption: "Each tool you turn on uses part of the context window."
        )

        ForEach(AgentToolDescriptor.Category.allCases, id: \.self) { category in
            let tools = AgentToolCatalog.descriptors(in: category)
            SettingsSection(title: category.title, symbol: Self.symbol(for: category), footnote: footnote(for: category)) {
                ForEach(tools) { tool in
                    DetailRow(title: tool.title, caption: tool.summary) {
                        SettingsToggle(Binding(
                            get: { model.isToolEnabled(tool.id) },
                            set: { model.setTool(tool.id, enabled: $0) }
                        ))
                    }

                    if tool.id != tools.last?.id {
                        RowSeparator()
                    }
                }
            }
        }
    }

    @ViewBuilder private var resetButton: some View {
        if !model.isUsingRecommendedTools {
            SettingsButton(title: "Reset") {
                model.resetToolsToRecommended()
            }
        }
    }

    private func footnote(for category: AgentToolDescriptor.Category) -> LocalizedStringResource? {
        guard category == AgentToolDescriptor.Category.allCases.last else { return nil }
        return "Models that accept images can also use screenshots."
    }

    private static func symbol(for category: AgentToolDescriptor.Category) -> String {
        switch category {
        case .research:
            "magnifyingglass"
        case .page:
            "cursorarrow.click"
        case .tabs:
            "square.on.square"
        case .media:
            "play.rectangle"
        }
    }
}
