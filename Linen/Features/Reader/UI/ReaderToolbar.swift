// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import WebKit

struct ReaderToolbar: View {
    let tab: BrowserTab
    let article: ReaderArticle
    let listener: ReaderListener
    let palette: ReaderAppearance.Palette
    let readsWithOpenAI: Bool

    @State private var showsAppearance = false
    @State private var showsSpeed = false

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
        .environment(\.chromeWash, nil)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }

    fileprivate static func speedLabel(_ rate: Float) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...1))))×"
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
            showsSpeed.toggle()
        } label: {
            ZStack {
                Text(Self.speedLabel(0.5)).hidden()
                Text(Self.speedLabel(listener.rate))
            }
            .font(Theme.Font.label)
            .monospacedDigit()
        }
        .help("Playback speed")
        .popover(isPresented: $showsSpeed, arrowEdge: .bottom) {
            ReaderSpeedPopover(listener: listener)
                .chromePopoverAppearance(scheme)
        }

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
        isEnabled && configuration.isPressed ? .primary.opacity(0.16) : .clear
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tight + 2, style: .continuous)
        configuration.label
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 28)
            .background(fill, in: shape)
            .hoverSheet(isActive: isEnabled && (hovering || configuration.isPressed), in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovering = $0 }
    }
}

private struct ReaderSpeedPopover: View {
    let listener: ReaderListener

    @State private var draft: Float?
    @State private var isDragging = false

    private var shownRate: Float {
        draft ?? listener.rate
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(ReaderToolbar.speedLabel(shownRate))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Slider(value: Binding { shownRate } set: { draft = $0 }, in: ReaderListener.rateRange, step: 0.1) {
                Text("Playback speed")
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill")
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "hare.fill")
                    .foregroundStyle(.secondary)
            } onEditingChanged: { editing in
                isDragging = editing
                if !editing {
                    commit()
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
        .padding(16)
        .onChange(of: draft) {
            if !isDragging {
                commit()
            }
        }
    }

    private func commit() {
        guard let draft else { return }
        listener.setRate(draft)
        self.draft = nil
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
