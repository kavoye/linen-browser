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

    var body: some View {
        @Bindable var session = session
        Group {
            if let offer = session.current {
                ChromeIcon(symbol: offer.symbol, weight: .semibold, tint: Theme.accent,
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
                .environment(\.colorScheme, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
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
        VStack(alignment: .leading, spacing: 16) {
            AutofillSaveDescription(offer: offer)
            if let error = session.error {
                Text(verbatim: error)
                    .font(Theme.Font.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AutofillSaveActions(session: session, offer: offer, review: review)
        }
        .padding(16)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autofill save suggestion")
    }
}

private struct AutofillSaveDescription: View {
    let offer: AutofillSaveSession.Offer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: offer.symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(offer.title).font(.headline)
                Text(verbatim: offer.origin).font(Theme.Font.label).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                Text(verbatim: offer.candidate.summary).font(Theme.Font.label)
                    .lineLimit(offer.candidate.kind == .contact ? 4 : 2)
                    .truncationMode(.middle)
                    .help(offer.candidate.summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AutofillSaveActions: View {
    let session: AutofillSaveSession
    let offer: AutofillSaveSession.Offer
    let review: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Review Details…", action: review)
                Spacer(minLength: 8)
                Button("Never for This Site") { Task { await session.never(offer) } }
            }
            .buttonStyle(.link)
            .font(Theme.Font.label)
            Divider()
            HStack(spacing: 8) {
                if session.isBusy {
                    Spinner(size: 14)
                }
                Spacer(minLength: 0)
                Button("Not Now") { session.dismiss(offer) }
                Button(offer.isUpdate ? "Update" : "Save") { Task { await session.save(offer) } }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
        }
        .disabled(session.isBusy)
    }
}
