// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct EditStartPageButton: View {
    let settings: BrowserSettings

    @State private var editing = false
    @State private var hovering = false

    var body: some View {
        Button { editing.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Edit")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .glassSurface(isActive: hovering || editing, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering || editing ? .primary : .secondary)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help("Customize Start Page")
        .popover(isPresented: $editing, arrowEdge: .top) {
            StartPageEditor(settings: settings)
        }
    }
}

private struct StartPageEditor: View {
    let settings: BrowserSettings

    private static let rowHeight: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start Page")
                    .font(.system(size: 13, weight: .semibold))
                Text("Turn sections on or off. Drag to reorder.")
                    .font(Theme.Font.label)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 9)

            List {
                ForEach(settings.startPageOrder) { section in
                    StartPageEditorRow(
                        section: section,
                        settings: settings,
                        height: Self.rowHeight
                    )
                }
                .onMove { source, destination in
                    withAnimation(Theme.Motion.settle) {
                        settings.moveStartPageSections(from: source, to: destination)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .listRowBackground(Color.clear)
            .frame(height: CGFloat(settings.startPageOrder.count) * Self.rowHeight)

            if !settings.hiddenFrequentHosts.isEmpty {
                Divider().opacity(0.4)

                Button("Restore \(settings.hiddenFrequentHosts.count) removed websites") {
                    settings.restoreHiddenFrequentSites()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .glassSurface(in: Capsule())
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
        }
        .frame(width: 310)
        .padding(.bottom, 12)
    }
}

private struct StartPageEditorRow: View {
    let section: StartPageSection
    let settings: BrowserSettings
    let height: CGFloat

    @State private var hovering = false

    var body: some View {
        @Bindable var settings = settings

        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(Theme.Font.micro)
                .foregroundStyle(.quaternary)

            Image(systemName: section.symbol)
                .font(Theme.Font.label)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(Theme.Font.rowTitle)
                Text(section.summary)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Toggle(isOn: $settings[showsStartPageSection: section]) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .frame(height: height)
        .padding(.horizontal, 8)
        .hoverBackground(
            isActive: hovering,
            in: RoundedRectangle(cornerRadius: Theme.Radius.hover, style: .continuous)
        )
        .onHover { hovering = $0 }
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
