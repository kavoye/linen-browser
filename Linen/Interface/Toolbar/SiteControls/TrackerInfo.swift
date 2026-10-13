// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct TrackerInfoButton: View {
    let tab: BrowserTab
    let host: String

    @State private var isPresented = false

    private var isBlocking: Bool {
        !tab.context.contentBlocker.isExempt(host)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isPresented ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)
                )
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("About Tracker Blocking")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            TrackerInfoPopover(tab: tab, isBlocking: isBlocking)
                .chromePopoverAppearance()
        }
    }
}

private struct TrackerInfoPopover: View {
    let tab: BrowserTab
    let isBlocking: Bool

    @State private var domains: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackerInfoHeader(isBlocking: isBlocking)

            Divider().padding(.horizontal, SiteControlsMetrics.inset)

            if let domains {
                TrackerDomainList(domains: domains, isBlocking: isBlocking)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking this page…")
                        .font(Theme.Font.label)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 74)
            }

            Divider().padding(.horizontal, SiteControlsMetrics.inset)

            TrackerInfoCaption()
        }
        .frame(width: 310)
        .task(id: tab.urlString) {
            let result = await TrackerPageReport.matchingDomains(in: tab.webView)
            guard !Task.isCancelled else { return }
            domains = result
        }
    }
}

private struct TrackerInfoHeader: View {
    let isBlocking: Bool

    private var status: LocalizedStringResource {
        isBlocking ? "Enabled for this website" : "Disabled for this website"
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isBlocking ? "shield.checkered" : "shield.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isBlocking ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)
                )
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tracker blocking")
                    .font(.system(size: 13, weight: .semibold))
                Text(status)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

private struct TrackerDomainList: View {
    let domains: [String]
    let isBlocking: Bool

    private var listHeight: CGFloat {
        min(CGFloat(domains.count) * 27, 160)
    }

    private var heading: LocalizedStringResource {
        isBlocking ? "Blocked on this page" : "Would be blocked on this page"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if domains.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.success)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("No trackers found")
                            .font(Theme.Font.rowTitle)
                        Text("This page does not reference known tracker domains.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            } else {
                HStack {
                    Text(heading)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(domains.count, format: .number)
                        .font(Theme.Font.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(domains, id: \.self) { domain in
                            Label {
                                Text(verbatim: domain)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(systemName: "shield.slash")
                                    .foregroundStyle(.secondary)
                            }
                            .font(Theme.Font.label)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: listHeight)
            }
        }
        .padding(.horizontal, SiteControlsMetrics.inset)
        .padding(.vertical, 11)
    }
}

private struct TrackerInfoCaption: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Linen blocks third-party requests to known advertising, analytics, session-recording, social-pixel, and fingerprinting domains.")
            Text("The list shows the known tracker domains this page refers to. A request that is stopped before it loads can be missing.")
        }
        .font(Theme.Font.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
    }
}
