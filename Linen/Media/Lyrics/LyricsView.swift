// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct LyricsSurface: View {
    let coordinator: AppCoordinator

    private var media: MediaCenter {
        coordinator.media
    }
    private var lyrics: LyricsModel {
        coordinator.lyrics
    }
    private var model: MediaModel {
        coordinator.lyricsSource
    }

    private var signature: LyricsSignature {
        LyricsSignature(
            tabID: model.controlledTabID,
            title: model.trackTitle.isEmpty ? model.pageTitle : model.trackTitle,
            artist: model.artist,
            album: model.album,
            seconds: Int(model.duration.rounded()),
            isEnabled: coordinator.settings.showsLyrics,
            isPrivate: coordinator.isLyricsTabPrivate,
            isLive: model.isLive
        )
    }

    private var title: String {
        if let matched = lyrics.matched, !matched.track.isEmpty {
            return matched.track
        }
        return model.trackTitle.isEmpty ? model.title : model.trackTitle
    }

    private var isOnScreen: Bool {
        coordinator.sidePanel.isShowing(.lyrics) && !coordinator.isShowingSettings
    }

    private var subtitle: String {
        let matched = lyrics.matched
        let artist = matched?.artist.isEmpty == false ? matched!.artist : model.artist
        let album = matched?.album.isEmpty == false ? matched!.album : model.album
        if artist.isEmpty {
            return album
        }
        let repeats = album.isEmpty || album == artist || album == title
        return repeats ? artist : "\(artist) · \(album)"
    }

    var body: some View {
        let watching = isOnScreen ? coordinator.lyricsTab : nil
        let watch = LyricsWatch(
            tabID: watching?.id,
            isDocked: coordinator.isLyricsSourceDocked,
            isOnScreen: isOnScreen
        )
        LyricsBoard(
            lyrics: lyrics,
            title: title,
            subtitle: subtitle,
            artwork: model.artworkURL,
            isPlaying: model.isPlaying,
            sources: coordinator.lyricsPickerTabs,
            chosen: watching?.id,
            onChoose: coordinator.pinLyrics(to:),
            onSeek: seek(to:)
        )
        .task(id: LyricsLookup(signature: signature, isOnScreen: isOnScreen)) {
            guard isOnScreen else { return }
            await lyrics.load(signature)
        }
        .task(id: watch) { coordinator.watchForLyrics(watching) }
        .onChange(of: model.currentTime, initial: true) { follow() }
        .onChange(of: model.isPlaying) { follow() }
        .onAppear { lyrics.isOnScreen = isOnScreen }
        .onChange(of: isOnScreen, initial: false) { _, showing in lyrics.isOnScreen = showing }
        .onDisappear {
            lyrics.isOnScreen = false
            coordinator.lyricsPinnedTabID = nil
            coordinator.media.stopWatching()
        }
    }

    private func follow() {
        lyrics.sync(time: model.currentTime, isPlaying: model.isPlaying)
    }

    private func seek(to line: LyricsLine) {
        guard model.duration > 0 else { return }
        let seconds = min(max(line.start + lyrics.offset, 0), model.duration)
        if coordinator.isLyricsSourceDocked {
            media.seek(toFraction: seconds / model.duration)
        } else if let tab = coordinator.lyricsTab {
            MediaCenter.seek(to: seconds, on: tab.webView)
        }
    }
}

private struct LyricsWatch: Equatable {
    var tabID: UUID?
    var isDocked: Bool
    var isOnScreen: Bool
}

private struct LyricsLookup: Equatable {
    var signature: LyricsSignature
    var isOnScreen: Bool
}

struct LyricsBackdrop: View {
    let artwork: URL?

    var body: some View {
        Color.black
            .overlay {
                if let artwork {
                    AsyncImage(url: artwork) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 70)
                                .saturation(1.5)
                                .scaleEffect(1.4)
                                .opacity(0.55)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.45), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .drawingGroup()
    }
}

struct LyricsBoard: View {
    let lyrics: LyricsModel
    let title: String
    let subtitle: String
    let artwork: URL?
    let isPlaying: Bool
    var sources: [BrowserTab] = []
    var chosen: UUID?
    var onChoose: (BrowserTab) -> Void = { _ in }
    let onSeek: (LyricsLine) -> Void

    @State private var containerSize: CGSize = .zero
    @State private var sourceAnchor = MenuAnchorBox()

    private var fontSize: CGFloat {
        LyricsMetrics.fontSize(forWidth: containerSize.width, scale: lyrics.textSize.scale)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
            footer
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .colorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            artworkThumb

            nowPlaying

            Spacer(minLength: 8)

            sizeButton

            matchButton
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if sources.count > 1 {
            Button {
                sourceMenu().popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: -4),
                    in: sourceAnchor.view ?? NSView()
                )
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    titleBlock
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose Which Tab the Words Follow")
            .background { MenuAnchor(box: sourceAnchor) }
        } else {
            titleBlock
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    private func sourceMenu() -> NSMenu {
        let menu = NSMenu()
        let playing = sources.filter(\.isPlayingAudio)
        let quiet = sources.filter { !$0.isPlayingAudio }
        for tab in playing + quiet {
            if tab.id == quiet.first?.id, !playing.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(title: tab.title) { onChoose(tab) }
            menu.items.last?.state = chosen == tab.id ? .on : .off
        }
        return menu
    }

    @ViewBuilder
    private var artworkThumb: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white.opacity(0.1))
            .frame(width: 38, height: 38)
            .overlay {
                if let artwork {
                    AsyncImage(url: artwork) { phase in
                        if case let .success(image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var sizeButton: some View {
        LyricsChromeMenuButton(symbol: "textformat.size", help: "Text Size") {
            let menu = NSMenu()
            for size in LyricsTextSize.allCases {
                menu.addItem(title: String(localized: size.label)) { lyrics.textSize = size }
                menu.items.last?.state = lyrics.textSize == size ? .on : .off
            }
            return menu
        }
    }

    private var matchButton: some View {
        LyricsChromeMenuButton(symbol: "ellipsis", help: "Choose a Different Match") {
            let menu = NSMenu()
            if lyrics.alternatives.isEmpty {
                menu.addItem(title: String(localized: "Find Another Match")) {
                    Task { await lyrics.findAlternatives() }
                }
                menu.items.last?.isEnabled = !lyrics.isFindingAlternatives
            } else {
                for match in lyrics.alternatives {
                    menu.addItem(title: match.label) { lyrics.use(match) }
                    menu.items.last?.state = lyrics.matched?.id == match.id ? .on : .off
                }
            }
            return menu
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private var stage: some View {
        switch lyrics.phase {
        case .idle:
            PanelNotice(
                symbol: "music.note",
                title: "Nothing is playing",
                caption: "Play a song in any tab. Linen reads its title, looks the words up on LRCLIB, and follows along with the music."
            )
        case .off:
            PanelNotice(
                symbol: "quote.bubble",
                title: "Lyrics are off",
                caption: "Turn them on in Settings › General."
            )
        case .looking:
            PanelNotice(symbol: nil, title: "Looking for lyrics…")
        case .instrumental:
            PanelNotice(symbol: "music.quarternote.3", title: "Instrumental")
        case .missing:
            PanelNotice(
                symbol: "text.magnifyingglass",
                title: "No lyrics found",
                caption: "Nothing on LRCLIB matches this track."
            )
        case .words:
            if let plain = lyrics.plainText {
                LyricsPlainText(text: plain, fontSize: fontSize, width: containerSize.width)
            } else {
                LyricsScroll(
                    lyrics: lyrics,
                    isPlaying: isPlaying,
                    fontSize: fontSize,
                    width: containerSize.width,
                    height: containerSize.height,
                    onSeek: onSeek
                )
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Lyrics from LRCLIB")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))

            Spacer(minLength: 8)

            if lyrics.isSynced {
                HStack(spacing: 2) {
                    LyricsChromeButton(symbol: "minus", help: "Show Lyrics Earlier") {
                        lyrics.nudge(by: -LyricsModel.offsetStep)
                    }

                    Button {
                        lyrics.resetOffset()
                    } label: {
                        Text(verbatim: offsetLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(lyrics.offset == 0 ? 0.4 : 0.85))
                    .help("Reset the Timing")

                    LyricsChromeButton(symbol: "plus", help: "Show Lyrics Later") {
                        lyrics.nudge(by: LyricsModel.offsetStep)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private var offsetLabel: String {
        guard lyrics.offset != 0 else { return String(localized: "In sync") }
        let seconds = lyrics.offset.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        return String(localized: "lyrics.offset.seconds", defaultValue: "\(seconds) s")
    }
}

// MARK: - The scrolling column

private struct LyricsScroll: View {
    let lyrics: LyricsModel
    let isPlaying: Bool
    let fontSize: CGFloat
    let width: CGFloat
    let height: CGFloat
    let onSeek: (LyricsLine) -> Void

    @State private var heldUntil: Date = .distantPast

    private var gap: CGFloat {
        LyricsMetrics.lineGap(forFontSize: fontSize)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: gap) {
                    Color.clear.frame(height: height * LyricsMetrics.focus)
                    ForEach(lyrics.lines) { line in
                        LyricsLineRow(
                            line: line,
                            distance: distance(to: line.id),
                            isPlaying: isPlaying,
                            fontSize: fontSize,
                            elapsed: { lyrics.elapsed() },
                            onSeek: { onSeek(line) }
                        )
                        .id(line.id)
                    }
                    Color.clear.frame(height: height * (1 - LyricsMetrics.focus))
                }
                .frame(width: LyricsMetrics.columnWidth(forWidth: width), alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onScrollPhaseChange { _, phase in
                guard phase == .interacting || phase == .decelerating else { return }
                heldUntil = Date().addingTimeInterval(LyricsMetrics.holdAfterScrolling)
            }
            .onChange(of: lyrics.activeIndex) { _, index in
                guard Date() >= heldUntil else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                    proxy.scrollTo(index ?? 0, anchor: UnitPoint(x: 0, y: LyricsMetrics.focus))
                }
            }
            .onAppear {
                proxy.scrollTo(lyrics.activeIndex ?? 0, anchor: UnitPoint(x: 0, y: LyricsMetrics.focus))
            }
        }
    }

    private func distance(to id: Int) -> Int {
        guard let active = lyrics.activeIndex else { return id + 1 }
        return id - active
    }
}

private struct LyricsLineRow: View {
    let line: LyricsLine
    let distance: Int
    let isPlaying: Bool
    let fontSize: CGFloat
    let elapsed: () -> Double
    let onSeek: () -> Void

    @State private var hovering = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .scaleEffect(distance == 0 ? 1 : 0.96, anchor: .leading)
            .brightness(hovering && distance != 0 ? 0.25 : 0)
            .onHover { hovering = $0 }
            .onTapGesture(perform: onSeek)
            .animation(.easeOut(duration: 0.28), value: distance == 0)
    }

    @ViewBuilder
    private var content: some View {
        if line.isGap {
            LyricsGapDots(
                line: line,
                isActive: distance == 0,
                isPlaying: isPlaying,
                fontSize: fontSize,
                elapsed: elapsed
            )
        } else if distance == 0 {
            TimelineView(.animation(paused: !isPlaying)) { _ in
                sung(at: elapsed())
                    .font(.system(size: fontSize, weight: .bold))
            }
        } else {
            Text(verbatim: line.text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(.white.opacity(LyricsMetrics.fade(atDistance: distance)))
        }
    }

    private func sung(at time: Double) -> Text {
        guard !line.words.isEmpty else { return Text(verbatim: line.text) }

        let last = line.words.count - 1
        var built = AttributedString()
        for (index, word) in line.words.enumerated() {
            var run = AttributedString(index == last ? word.text : word.text + " ")
            run.foregroundColor = .white.opacity(
                LyricsMetrics.wordOpacity(LyricsMetrics.sungShare(of: word, at: time))
            )
            built += run
        }
        return Text(built)
    }
}

private struct LyricsGapDots: View {
    let line: LyricsLine
    let isActive: Bool
    let isPlaying: Bool
    let fontSize: CGFloat
    let elapsed: () -> Double

    var body: some View {
        if isActive {
            TimelineView(.animation(paused: !isPlaying)) { _ in
                dots(progress: LyricsMetrics.gapProgress(line, at: elapsed()))
            }
        } else {
            dots(progress: 0)
                .opacity(0.35)
        }
    }

    private func dots(progress: Double) -> some View {
        let swell = progress > 0.88 ? 1 + (progress - 0.88) / 0.12 * 0.2 : 1
        return HStack(spacing: fontSize * 0.26) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.28 + 0.72 * LyricsMetrics.dotFill(index, progress: progress)))
                    .frame(width: fontSize * 0.3, height: fontSize * 0.3)
            }
        }
        .scaleEffect(swell, anchor: .leading)
        .padding(.vertical, fontSize * 0.14)
    }
}

private struct LyricsPlainText: View {
    let text: String
    let fontSize: CGFloat
    let width: CGFloat

    var body: some View {
        ScrollView(.vertical) {
            Text(verbatim: text)
                .font(.system(size: max(fontSize * 0.62, 14), weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(width: LyricsMetrics.columnWidth(forWidth: width), alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
    }
}

private struct LyricsChromeButton: View {
    let symbol: String
    let help: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LyricsGlyph(symbol: symbol, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(help))
    }
}

/// The same button, opening a menu under itself rather than under the pointer.
/// A SwiftUI `Menu` is bridged to an NSPopUpButton, which paints its own label
/// and ignores the tint and the hover the timing buttons use.
private struct LyricsChromeMenuButton: View {
    let symbol: String
    let help: LocalizedStringResource
    let menu: () -> NSMenu

    @State private var anchor = MenuAnchorBox()
    @State private var hovering = false

    var body: some View {
        Button {
            let menu = menu()
            guard let view = anchor.view else {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                return
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        } label: {
            LyricsGlyph(symbol: symbol, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(help))
        .background { MenuAnchor(box: anchor) }
    }
}

@MainActor
private final class MenuAnchorBox {
    weak var view: NSView?
}

private struct MenuAnchor: NSViewRepresentable {
    let box: MenuAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

private struct LyricsGlyph: View {
    let symbol: String
    let hovering: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.55))
            .frame(width: 22, height: 22)
            .hoverBackground(isActive: hovering)
            .environment(\.chromeIsLight, false)
    }
}
