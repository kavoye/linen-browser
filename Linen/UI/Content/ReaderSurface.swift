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
                if inNewTab, let open = tab.onOpenInNewTab {
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

private struct ReaderToolbar: View {
    let tab: BrowserTab
    let article: ReaderArticle
    let listener: ReaderListener
    let palette: ReaderAppearance.Palette
    let readsWithOpenAI: Bool

    @State private var showsAppearance = false

    private var scheme: ColorScheme {
        palette == .dark ? .dark : .light
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
    }

    private var isListening: Bool {
        listener.isListening(to: tab.id)
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                showsAppearance.toggle()
            } label: {
                Image(systemName: "textformat.size")
                    .font(Theme.Font.control)
            }
            .help("Text appearance")
            .popover(isPresented: $showsAppearance, arrowEdge: .bottom) {
                ReaderAppearancePopover()
                    .chromePopoverAppearance(scheme)
            }

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            if isListening {
                listeningControls
            } else {
                Button {
                    listener.start(article, in: tab)
                } label: {
                    Label("Listen", systemImage: "play.fill")
                        .font(Theme.Font.body)
                }
                .help(Text(listenHelp))
            }

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            Button("Done") { tab.reader.close() }
                .font(Theme.Font.body)
                .help("Hide Reader (⌥⌘R)")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .frame(height: 36)
        .glassSurface(in: shape)
        .environment(\.colorScheme, scheme)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }

    private var pauseHelp: LocalizedStringResource {
        listener.state == .playing ? "Pause" : "Resume"
    }

    private var listenHelp: LocalizedStringResource {
        if readsWithOpenAI {
            return "Read this article aloud. Uses your OpenAI API key."
        }
        return "Read this article aloud"
    }

    @ViewBuilder
    private var listeningControls: some View {
        Button {
            listener.skip(by: -1)
        } label: {
            Image(systemName: "backward.fill")
                .font(Theme.Font.label)
        }
        .disabled(!listener.canSkipBack)
        .help("Previous paragraph")

        Button {
            listener.togglePause()
        } label: {
            Image(systemName: listener.state == .playing ? "pause.fill" : "play.fill")
                .font(Theme.Font.control)
                .frame(width: 14)
        }
        .help(Text(pauseHelp))

        Button {
            listener.skip(by: 1)
        } label: {
            Image(systemName: "forward.fill")
                .font(Theme.Font.label)
        }
        .disabled(!listener.canSkipForward)
        .help("Next paragraph")

        Button {
            listener.stop()
        } label: {
            Image(systemName: "stop.fill")
                .font(Theme.Font.label)
        }
        .help("Stop reading aloud")
    }
}

private struct ReaderToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ReaderToolbarButton(configuration: configuration)
    }
}

private struct ReaderToolbarButton: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var fill: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed {
            return .primary.opacity(0.16)
        }
        return hovering ? .primary.opacity(0.08) : .clear
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tight + 2, style: .continuous)
        configuration.label
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 28)
            .background(fill, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovering = $0 }
    }
}

private struct ReaderAppearancePopover: View {
    @Bindable private var appearance = ReaderAppearance.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                sizeButton(glyphSize: 10, help: "Make text smaller", enabled: appearance.canShrink) {
                    appearance.shrink()
                }
                sizeButton(glyphSize: 20, help: "Make text bigger", enabled: appearance.canGrow) {
                    appearance.grow()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Theme")
                HStack(spacing: 12) {
                    ForEach(ReaderAppearance.Palette.allCases) { palette in
                        PaletteSwatch(palette: palette, isSelected: appearance.palette == palette) {
                            appearance.palette = palette
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Font")
                VStack(spacing: 0) {
                    ForEach(ReaderAppearance.Typeface.allCases) { typeface in
                        fontRow(typeface)
                    }
                }
                .padding(.horizontal, -8)
            }

            Divider()

            Button {
                appearance.reset()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, -8)
            .disabled(appearance.isDefault)
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 220)
    }

    private func sectionTitle(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func sizeButton(
        glyphSize: CGFloat,
        help: LocalizedStringResource,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: "A")
                .font(.system(size: glyphSize, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
        }
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .disabled(!enabled)
        .help(Text(help))
    }

    private func fontRow(_ typeface: ReaderAppearance.Typeface) -> some View {
        checkRow(isSelected: appearance.typeface == typeface) {
            appearance.typeface = typeface
        } label: {
            Text(verbatim: typeface.name)
                .font(typeface.font(size: 15))
        }
    }

    private func checkRow<Label: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 14)
                label()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PaletteSwatch: View {
    let palette: ReaderAppearance.Palette
    let isSelected: Bool
    let action: () -> Void

    private static let side: CGFloat = 36

    private var fill: AnyShapeStyle {
        let light = Color(nsColor: ReaderAppearance.background(for: .light))
        let dark = Color(nsColor: ReaderAppearance.background(for: .dark))
        guard palette == .automatic else {
            return AnyShapeStyle(Color(nsColor: ReaderAppearance.background(for: palette)))
        }
        return AnyShapeStyle(LinearGradient(
            stops: [.init(color: light, location: 0.5), .init(color: dark, location: 0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }

    private var checkColor: Color {
        palette == .dark ? .white : .black
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                Circle()
                    .strokeBorder(isSelected ? Theme.systemAccent : .primary.opacity(0.2), lineWidth: isSelected ? 2 : 0.5)
                if isSelected, palette != .automatic {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(checkColor)
                }
            }
            .frame(width: Self.side, height: Self.side)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(palette.title))
        .accessibilityLabel(Text(palette.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ReaderWebView: NSViewRepresentable {
    let session: ReaderSession
    let article: ReaderArticle
    let dataStore: WKWebsiteDataStore
    let typeface: ReaderAppearance.Typeface
    let palette: ReaderAppearance.Palette
    let textSize: Int
    let block: Int?
    let onLoaded: () -> Void
    let onOpenLink: (URL, _ inNewTab: Bool, _ activate: Bool) -> Void

    func makeCoordinator() -> ReaderPageController {
        ReaderPageController()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WebViewPool.makeConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        session.presentedView = webView
        update(context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: ReaderPageController) {
        if coordinator.session?.presentedView === webView {
            coordinator.session?.presentedView = nil
        }
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    private func update(_ controller: ReaderPageController) {
        controller.session = session
        controller.onLoaded = onLoaded
        controller.onOpenLink = onOpenLink
        controller.show(
            article,
            appearance: .init(typeface: typeface, palette: palette, textSize: textSize),
            block: block
        )
    }
}

@MainActor
final class ReaderPageController: NSObject, WKNavigationDelegate {
    struct Appearance: Equatable {
        let typeface: ReaderAppearance.Typeface
        let palette: ReaderAppearance.Palette
        let textSize: Int
    }

    weak var webView: WKWebView?
    weak var session: ReaderSession?
    var onLoaded: (() -> Void)?
    var onOpenLink: ((URL, Bool, Bool) -> Void)?

    private var article: ReaderArticle?
    private var appearance: Appearance?
    private var block: Int?
    private var isLoaded = false
    private var acceptsNextLoad = false

    private static let middleButton = 4

    func show(_ next: ReaderArticle, appearance nextAppearance: Appearance, block nextBlock: Int?) {
        guard let webView else { return }
        if article != next {
            article = next
            appearance = nextAppearance
            block = nextBlock
            isLoaded = false
            acceptsNextLoad = true
            let html = ReaderPage.html(
                for: next,
                typeface: nextAppearance.typeface,
                palette: nextAppearance.palette,
                textSize: nextAppearance.textSize
            )
            webView.loadHTMLString(html, baseURL: next.url)
            return
        }
        if appearance != nextAppearance {
            appearance = nextAppearance
            if isLoaded {
                run(ReaderPage.appearanceScript(
                    typeface: nextAppearance.typeface,
                    palette: nextAppearance.palette,
                    textSize: nextAppearance.textSize
                ))
            }
        }
        if block != nextBlock {
            block = nextBlock
            if isLoaded {
                run(ReaderPage.highlightScript(block: nextBlock))
            }
        }
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame != false else {
            decisionHandler(.cancel)
            return
        }
        if acceptsNextLoad, navigationAction.navigationType == .other {
            acceptsNextLoad = false
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme)
        else { return }
        if let article, let fragment = url.fragment(), !fragment.isEmpty,
           BrowserTab.withoutFragment(url.absoluteString) == BrowserTab.withoutFragment(article.url.absoluteString) {
            scroll(toFragment: fragment)
            return
        }
        let inNewTab = navigationAction.modifierFlags.contains(.command)
            || navigationAction.buttonNumber == Self.middleButton
        onOpenLink?(url, inNewTab, navigationAction.modifierFlags.contains(.shift))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        onLoaded?()
        if let appearance {
            run(ReaderPage.appearanceScript(
                typeface: appearance.typeface,
                palette: appearance.palette,
                textSize: appearance.textSize
            ))
        }
        if block != nil {
            run(ReaderPage.highlightScript(block: block))
        }
    }

    private func scroll(toFragment fragment: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [fragment], options: []),
              let encoded = String(data: data, encoding: .utf8)
        else { return }
        run("""
        (() => {
          const id = \(encoded)[0];
          const el = document.getElementById(id) || document.getElementsByName(id)[0];
          if (el) el.scrollIntoView({ block: 'start', behavior: 'smooth' });
        })()
        """)
    }
}
