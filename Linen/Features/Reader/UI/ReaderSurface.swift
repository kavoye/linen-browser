// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct ReaderBadge: View {
    let browser: BrowserModel

    var body: some View {
        if let tab = browser.activeTab, browser.activeSplit == nil, tab.reader.isAvailable {
            let isActive = tab.reader.isActive
            let help: LocalizedStringResource = isActive ? "Hide Reader (⌥⌘R)" : "Show Reader (⌥⌘R)"
            ChromeIcon(
                symbol: isActive ? "doc.plaintext.fill" : "doc.plaintext",
                weight: .semibold,
                tint: isActive ? Theme.systemAccent : nil,
                help: String(localized: help)
            ) {
                tab.reader.toggle()
            }
            .disabled(tab.reader.isOpening)
        }
    }
}

struct ReaderPresenter: View {
    let tab: BrowserTab
    let listener: ReaderListener
    var readsWithOpenAI = false

    @State private var article: ReaderArticle?
    @State private var isRaised = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let article {
                    Color.black
                        .opacity(isRaised ? 0.22 : 0)
                        .allowsHitTesting(false)
                    ReaderSurface(tab: tab, article: article, listener: listener, readsWithOpenAI: readsWithOpenAI)
                        .offset(y: isRaised ? 0 : proxy.size.height)
                }
            }
        }
        .clipped()
        .allowsHitTesting(article != nil)
        .onAppear {
            guard tab.reader.isActive else { return }
            article = tab.reader.article
            isRaised = true
        }
        .onChange(of: tab.reader.isActive) { _, isActive in
            isActive ? raise() : lower()
        }
    }

    private func raise() {
        guard let next = tab.reader.article else { return }
        article = next
        isRaised = false
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.4)) {
                isRaised = true
            }
        }
    }

    private func lower() {
        guard article != nil else { return }
        withAnimation(.smooth(duration: 0.32)) {
            isRaised = false
        } completion: {
            if !tab.reader.isActive {
                article = nil
            }
        }
    }
}

struct ReaderSurface: View {
    let tab: BrowserTab
    let article: ReaderArticle
    let listener: ReaderListener
    var readsWithOpenAI = false

    @Bindable private var appearance = ReaderAppearance.shared
    @Environment(\.colorScheme) private var scheme

    private var palette: ReaderAppearance.Palette {
        appearance.resolvedPalette(isDark: scheme == .dark)
    }

    private var highlightedBlock: Int? {
        listener.isListening(to: tab.id) ? listener.block : nil
    }

    var body: some View {
        ReaderWebView(
            session: tab.reader,
            article: article,
            dataStore: tab.webView.configuration.websiteDataStore,
            typeface: appearance.typeface,
            palette: appearance.palette,
            textSize: appearance.textSize,
            block: highlightedBlock,
            onLoaded: { tab.retranslateShownSurface() },
            onOpenLink: { url, inNewTab, activate in
                if inNewTab, let open = tab.events.onOpenInNewTab {
                    open(url, activate)
                } else {
                    tab.load(url)
                }
            }
        )
        .background(Color(nsColor: ReaderAppearance.background(for: palette)))
        .overlay(alignment: .topTrailing) {
            ReaderToolbar(tab: tab, article: article, listener: listener, palette: palette, readsWithOpenAI: readsWithOpenAI)
                .padding(.top, tab.find.isActive ? 54 : 10)
                .padding(.trailing, 14)
                .animation(Theme.Motion.settle, value: tab.find.isActive)
        }
    }
}
