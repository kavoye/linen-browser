// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct AutofillSaveBadge: View {
    let browser: BrowserModel
    let coordinator: AppCoordinator

    var body: some View {
        if !coordinator.isShowingSettings, let tab = browser.activeTab, tab.internalPage == nil {
            TabAutofillSaveBadge(session: tab.autofillSave)
                .id(tab.id)
        }
    }
}

private struct TabAutofillSaveBadge: View {
    let session: AutofillSaveSession
    @State private var pendingReview: AutofillSaveSession.Offer?
    @State private var reviewing: AutofillSaveSession.Offer?

    private var windowScheme: ColorScheme {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    var body: some View {
        @Bindable var session = session
        Group {
            if let offer = session.current {
                ChromeIcon(symbol: offer.symbol, weight: .semibold, tint: Theme.systemAccent,
                           help: String(localized: offer.title)) {
                    session.isPopoverPresented.toggle()
                }
                .accessibilityLabel(Text(offer.title))
            }
        }
        .popover(isPresented: $session.isPopoverPresented, arrowEdge: .bottom) {
            if let offer = session.current {
                AutofillSavePopover(session: session, offer: offer) {
                    pendingReview = offer
                    session.isPopoverPresented = false
                }
                .id(offer.id)
                .chromePopoverAppearance()
                .onDisappear {
                    if let pendingReview, session.current?.id == pendingReview.id {
                        reviewing = pendingReview
                    }
                    pendingReview = nil
                }
            }
        }
        .sheet(item: $reviewing) { offer in
            AutofillSaveReview(session: session, offer: offer)
                .environment(\.colorScheme, windowScheme)
        }
        .onChange(of: session.current?.id) { _, id in
            if reviewing?.id != id {
                reviewing = nil
            }
            if pendingReview?.id != id {
                pendingReview = nil
            }
        }
        .onDisappear {
            session.isPopoverPresented = false
            pendingReview = nil
            reviewing = nil
        }
    }
}

private extension AutofillSaveSession.Offer {
    var title: LocalizedStringResource {
        switch candidate.kind {
        case .password:
            isUpdate ? "Update password?" : "Save password?"
        case .card:
            isUpdate ? "Update card?" : "Save card?"
        case .contact:
            "Save address?"
        }
    }

    var symbol: String {
        switch candidate.kind {
        case .password:
            "key"
        case .card:
            "creditcard"
        case .contact:
            "person.crop.rectangle"
        }
    }

}

private struct AutofillSavePopover: View {
    let session: AutofillSaveSession
    let offer: AutofillSaveSession.Offer
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(offer.title).font(.headline)
            AutofillSaveDescription(offer: offer)
            if let error = session.error {
                Text(verbatim: error)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AutofillSaveActions(session: session, offer: offer, review: review)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autofill save suggestion")
    }
}

private struct AutofillSaveDescription: View {
    let offer: AutofillSaveSession.Offer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: offer.symbol)
                .symbolVariant(.fill)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: offer.candidate.summary).font(.system(size: 13))
                    .lineLimit(offer.candidate.kind == .contact ? 4 : 2)
                    .truncationMode(.middle)
                    .help(offer.candidate.summary)
                Text(verbatim: offer.origin).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
    }
}

private struct AutofillSaveActions: View {
    let session: AutofillSaveSession
    let offer: AutofillSaveSession.Offer
    let review: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Review Details…", action: review)
                Button("Never for This Site") { Task { await session.never(offer) } }
            } label: {
                Text(Image(systemName: "ellipsis"))
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
            if session.isBusy {
                Spinner(size: 14)
            }
            Spacer(minLength: 0)
            Button("Not Now") { session.dismiss(offer) }
            Button(offer.isUpdate ? "Update" : "Save") { Task { await session.save(offer) } }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .disabled(session.isBusy)
    }
}
