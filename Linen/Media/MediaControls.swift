// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WebKit

struct MediaPlayerSurface: View {
    let media: MediaCenter
    var webView: WKWebView
    var crop: CGRect
    var width: CGFloat
    var cornerRadius: CGFloat
    var isStowed = false

    private var isOut: Bool {
        isStowed
    }

    private var height: CGFloat {
        MediaCropMath.cardHeight(width: width, crop: crop)
    }

    var body: some View {
        ZStack {
            Color.black

            MediaCropSurface(webView: webView, crop: crop)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black, lineWidth: 0.5)
        }
        .frame(height: isOut ? 0 : height, alignment: .top)
        .opacity(isOut ? 0 : 1)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            media.playPause()
        }
        .help(media.model.isPlaying ? Text("Pause") : Text("Play"))
    }
}

enum MediaCropMath {
    nonisolated static let minimumVisibleSide: CGFloat = 48

    nonisolated static func visibleCrop(
        viewportRect: CGRect,
        viewBounds: CGRect,
        topInset: CGFloat
    ) -> CGRect? {
        let visible = viewportRect.offsetBy(dx: 0, dy: topInset).intersection(viewBounds)
        guard visible.width >= minimumVisibleSide, visible.height >= minimumVisibleSide else {
            return nil
        }
        return visible
    }

    nonisolated static func cardHeight(width: CGFloat, crop: CGRect) -> CGFloat {
        guard width > 0, crop.width > 0, crop.height > 0 else { return (width * 9 / 16).rounded() }
        let natural = width * crop.height / crop.width
        return min(max(natural, width * 9 / 21), width).rounded()
    }

    nonisolated static func scaledBounds(cardSize: CGSize, crop: CGRect) -> CGRect? {
        guard cardSize.width > 0, cardSize.height > 0, crop.width > 0 else { return nil }
        let scale = cardSize.width / crop.width
        let height = cardSize.height / scale
        return CGRect(x: crop.minX, y: crop.midY - height / 2, width: crop.width, height: height)
    }
}

struct MediaCropSurface: NSViewRepresentable {
    let webView: WKWebView
    var crop: CGRect

    func makeNSView(context: Context) -> MediaCropContainer {
        let container = MediaCropContainer()
        container.crop = crop
        container.install(webView)
        return container
    }

    func updateNSView(_ nsView: MediaCropContainer, context: Context) {
        nsView.crop = crop
        nsView.install(webView)
    }

    static func dismantleNSView(_ nsView: MediaCropContainer, coordinator: ()) {
        nsView.uninstall()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MediaCropContainer,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: max(0, width), height: max(0, height))
    }
}

final class MediaCropContainer: NSView {
    var crop: CGRect = .zero {
        didSet {
            guard crop != oldValue else { return }
            applyCrop()
        }
    }

    private weak var installedWebView: WKWebView?

    override var isFlipped: Bool {
        true
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install(_ webView: WKWebView) {
        if let installedWebView, installedWebView !== webView, installedWebView.superview === self {
            WebViewParking.park(installedWebView)
        }
        installedWebView = webView
        attachIfHosted()
    }

    private func attachIfHosted() {
        guard window != nil, let webView = installedWebView, webView.superview !== self else { return }
        let size = webView.bounds.size
        webView.removeFromSuperview()
        webView.autoresizingMask = []
        webView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(size.width, 640),
            height: max(size.height, 480)
        )
        addSubview(webView)
        applyCrop()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfHosted()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil,
              let installedWebView, installedWebView.superview === self else { return }
        WebViewParking.park(installedWebView)
    }

    func uninstall() {
        if let installedWebView, installedWebView.superview === self {
            WebViewParking.park(installedWebView)
        }
        installedWebView = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyCrop()
    }

    private func applyCrop() {
        guard let webView = installedWebView, webView.superview === self,
              frame.width > 0, frame.height > 0,
              let scaled = MediaCropMath.scaledBounds(cardSize: frame.size, crop: crop)
        else { return }
        if webView.frame.origin != .zero {
            webView.frame.origin = .zero
        }
        setBoundsSize(scaled.size)
        setBoundsOrigin(scaled.origin)
    }
}

struct MediaTransport: View {
    let media: MediaCenter
    var isCompact = false

    private var model: MediaModel {
        media.model
    }

    private var isMusic: Bool {
        model.canGoToPreviousTrack || model.canGoToNextTrack
    }

    private var playPauseHelp: LocalizedStringResource {
        model.isPlaying ? "Pause" : "Play"
    }

    private var spacing: CGFloat {
        isCompact ? 6 : 9
    }

    private var volumeWidth: CGFloat {
        isCompact ? 28 : 36
    }

    var body: some View {
        HStack(spacing: spacing) {
            if !model.isLive {
                if isMusic {
                    MediaSkipButton(systemName: "backward.fill", size: 11, help: "Previous Track") {
                        if model.canGoToPreviousTrack {
                            media.previousTrack()
                        } else {
                            media.skip(by: -15)
                        }
                    } onHold: {
                        media.skip(by: -5)
                    }
                } else {
                    MediaSkipButton(systemName: "gobackward.15", size: 11, help: "Back 15 seconds") {
                        media.skip(by: -15)
                    } onHold: {
                        media.skip(by: -5)
                    }
                }
            }

            MediaButton(
                systemName: model.isPlaying ? "pause.fill" : "play.fill",
                size: 15,
                help: playPauseHelp
            ) {
                media.playPause()
            }

            if !model.isLive {
                if isMusic {
                    MediaSkipButton(systemName: "forward.fill", size: 11, help: "Next Track") {
                        if model.canGoToNextTrack {
                            media.nextTrack()
                        } else {
                            media.skip(by: 15)
                        }
                    } onHold: {
                        media.skip(by: 5)
                    }
                } else {
                    MediaSkipButton(systemName: "goforward.15", size: 11, help: "Forward 15 seconds") {
                        media.skip(by: 15)
                    } onHold: {
                        media.skip(by: 5)
                    }
                }
            } else {
                LiveBadge(font: .system(size: 10, weight: .medium))
                    .padding(.leading, 1)
            }

            Spacer(minLength: isCompact ? 4 : 8)

            SpeakerButton(media: media, iconSize: 11)

            MediaSlider(value: model.isMuted ? 0 : model.volume, height: 3) {
                media.setVolume($0)
            }
            .frame(width: volumeWidth)
        }
    }
}

enum MediaTimelineFace: Equatable {
    case live
    case pending(elapsed: Double)
    case scrubber(elapsed: Double, remaining: Double, progress: Double)

    static func face(isLive: Bool, currentTime: Double, duration: Double) -> MediaTimelineFace {
        if isLive {
            return .live
        }
        let elapsed = max(currentTime, 0)
        guard duration > 0 else { return .pending(elapsed: elapsed) }
        return .scrubber(
            elapsed: elapsed,
            remaining: max(duration - elapsed, 0),
            progress: min(max(elapsed / duration, 0), 1)
        )
    }
}

struct MediaTimeline: View {
    let media: MediaCenter
    var isCompact: Bool

    private var model: MediaModel {
        media.model
    }
    private var font: Font {
        .system(size: isCompact ? 9.5 : 11, weight: .medium).monospacedDigit()
    }
    private var trackHeight: CGFloat {
        isCompact ? 3 : 4
    }

    private var face: MediaTimelineFace {
        MediaTimelineFace.face(
            isLive: model.isLive,
            currentTime: model.currentTime,
            duration: model.duration
        )
    }

    var body: some View {
        let face = face
        let isCollapsed = face == .live
        HStack(spacing: 7) {
            switch face {
            case .live:
                EmptyView()
            case .pending(let elapsed):
                clockText(elapsed, style: .secondary)
                MediaTrackPlaceholder(height: trackHeight)
                Text(verbatim: Self.unknownClock)
                    .font(font)
                    .foregroundStyle(.tertiary)
            case .scrubber(let elapsed, let remaining, let progress):
                clockText(elapsed, style: .secondary)
                MediaSlider(value: progress, height: trackHeight) { fraction in
                    media.seek(toFraction: fraction)
                }
                clockText(remaining, style: .tertiary)
            }
        }
        .frame(height: isCollapsed ? 0 : (isCompact ? 14 : 18))
        .opacity(isCollapsed ? 0 : 1)
        .clipped()
        .animation(Self.liveSwitch, value: isCollapsed)
    }

    private static let liveSwitch: Animation = Theme.Motion.drift

    @ViewBuilder
    private func clockText(_ seconds: Double, style: HierarchicalShapeStyle) -> some View {
        Text(verbatim: Self.clock(seconds))
            .font(font)
            .foregroundStyle(style)
    }

    static let unknownClock = "--:--"

    private static let longestClock: Double = 100 * 3600 - 1

    static func clock(_ seconds: Double) -> String {
        let total = seconds.isFinite && seconds >= 0 ? min(seconds, longestClock) : 0
        let clock = Duration.seconds(total.rounded())
        return total >= 3600
            ? clock.formatted(.time(pattern: .hourMinuteSecond))
            : clock.formatted(.time(pattern: .minuteSecond))
    }
}

private struct LiveBadge: View {
    var font: Font

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.danger)
                .frame(width: 5, height: 5)
            Text("Live")
                .font(font)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live")
    }
}

private struct SpeakerButton: View {
    let media: MediaCenter
    var iconSize: CGFloat

    private var model: MediaModel {
        media.model
    }

    private var symbol: String {
        if model.isMuted || model.volume <= 0 {
            return "speaker.slash.fill"
        }
        if model.volume < 0.34 {
            return "speaker.fill"
        }
        if model.volume < 0.67 {
            return "speaker.wave.1.fill"
        }
        return "speaker.wave.2.fill"
    }

    private var help: LocalizedStringResource {
        model.isMuted ? "Unmute" : "Mute"
    }

    var body: some View {
        MediaButton(
            systemName: symbol,
            size: iconSize,
            help: help
        ) {
            media.toggleMute()
        }
        .frame(width: iconSize + 5, alignment: .leading)
    }
}

private struct MediaTrackPlaceholder: View {
    var height: CGFloat

    var body: some View {
        Capsule()
            .fill(Theme.Wash.strong)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .frame(height: max(height * 3, 10))
    }
}

struct MediaSlider: View {
    var value: Double
    var height: CGFloat
    var onChange: (Double) -> Void

    @State private var dragged: Double?
    @State private var hovering = false

    private var shown: Double {
        min(max(dragged ?? value, 0), 1)
    }

    private var isActive: Bool {
        hovering || dragged != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Wash.strong)
                Capsule()
                    .fill(isActive ? Color.primary.opacity(0.8) : Theme.Wash.scrim)
                    .frame(width: shown * width)
            }
            .frame(height: isActive ? height + 2 : height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = min(max(drag.location.x / width, 0), 1)
                        dragged = fraction
                        onChange(fraction)
                    }
                    .onEnded { drag in
                        let fraction = min(max(drag.location.x / width, 0), 1)
                        dragged = nil
                        onChange(fraction)
                    }
            )
        }
        .frame(height: max(height * 3, 10))
        .animation(Theme.Motion.quick, value: isActive)
        .onHover { hovering = $0 }
    }
}

struct MediaSkipButton: View {
    let systemName: String
    var size: CGFloat
    var help: LocalizedStringResource
    let onTap: () -> Void
    let onHold: () -> Void

    @State private var hovering = false
    @State private var hold: Task<Void, Never>?
    @State private var didHold = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .hoverLift(hovering)
            .frame(width: (size * 1.5).rounded(), height: (size * 1.5).rounded())
            .contentShape(Rectangle())
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press() }
                    .onEnded { _ in release() }
            )
            .onDisappear { hold?.cancel() }
            .help(Text(help))
            .accessibilityElement()
            .accessibilityLabel(Text(help))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
    }

    private func press() {
        guard hold == nil else { return }
        didHold = false
        hold = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            while !Task.isCancelled {
                didHold = true
                onHold()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func release() {
        hold?.cancel()
        hold = nil
        if !didHold {
            onTap()
        }
        didHold = false
    }
}

struct MediaButton: View {
    let systemName: String
    var size: CGFloat
    var tint: Color?
    var help: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .hoverLift(hovering)
                .frame(width: (size * 1.5).rounded(), height: (size * 1.5).rounded())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? (hovering ? Color.primary : Color.secondary))
        .onHover { hovering = $0 }
        .help(Text(help))
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let width: CGFloat
    var isMoving = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var start = Date()

    private static let gap: CGFloat = 36
    private static let speed: CGFloat = 24
    private static let rest: Double = 2.5
    private static let fade: CGFloat = 12

    private var overflows: Bool {
        textWidth > width + 0.5
    }

    var body: some View {
        Group {
            if overflows, isMoving, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let shift = offset(at: context.date)
                    HStack(spacing: Self.gap) {
                        label
                        label
                    }
                    .offset(x: -shift)
                    .frame(width: width, alignment: .leading)
                    .mask { edgeFade(leading: min(shift, Self.fade)) }
                }
            } else {
                Text(verbatim: text)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .background(alignment: .leading) {
            label
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
        }
        .onChange(of: text) { start = .now }
        .onChange(of: isMoving) { start = .now }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: text))
    }

    private func edgeFade(leading: CGFloat) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: leading)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
        }
    }

    private var label: some View {
        Text(verbatim: text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let travel = textWidth + Self.gap
        let cycle = Self.rest + Double(travel / Self.speed)
        let elapsed = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        guard elapsed > Self.rest else { return 0 }
        return CGFloat(elapsed - Self.rest) * Self.speed
    }
}
