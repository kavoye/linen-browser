// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AgentTaskTraceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let trace: ConversationLog.TaskTrace
    let tabID: UUID
    let browser: BrowserModel
    let onRetry: (ConversationLog.TaskTrace) -> Void
    let onEdit: (ConversationLog.TaskTrace) -> Void
    var isSpeaking = false
    var readsWithOpenAI = false
    let onSpeak: (ConversationLog.TaskTrace) -> Void

    var isLatest = true

    @State private var showsSteps = false
    @State private var hovering = false

    private var isThinking: Bool {
        trace.state == .running && trace.response.isEmpty && trace.liveProgress == nil
    }

    private var showsWorkHistory: Bool {
        showsSteps || (trace.state == .running && (!trace.progressUpdates.isEmpty || trace.liveProgress != nil))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentActivityMetrics.turnGap) {
            if !trace.attachments.isEmpty {
                AttachmentList(files: trace.attachments)
                if trace.attachmentTextOnly, trace.attachments.contains(where: { !$0.images.isEmpty }) {
                    Text("This model received the extracted text. Visual details weren’t included.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if trace.hasUserPrompt {
                ChatUserMessage(
                    text: trace.prompt,
                    when: Self.when(trace),
                    showsActions: hovering,
                    onEdit: { onEdit(trace) },
                    onCopy: { copy(trace.prompt) },
                    onRetry: { onRetry(trace) }
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                ChatTurnFooter(
                    label: workLabel,
                    providerID: trace.providerID,
                    stepCount: trace.steps.filter(\.isVisibleInChat).count,
                    hasDetails: !trace.progressUpdates.isEmpty
                        || !(trace.checkpoint?.openAI?.presentation?.summaries.isEmpty ?? true),
                    isThinking: isThinking,
                    stepsAreShown: showsSteps,
                    showsActions: (hovering || isSpeaking) && !trace.response.isEmpty,
                    isSpeaking: isSpeaking,
                    readsWithOpenAI: readsWithOpenAI,
                    onToggleSteps: {
                        withAnimation(Theme.Motion.quick) { showsSteps.toggle() }
                    },
                    onCopy: { copy(trace.response) },
                    onSpeak: { onSpeak(trace) }
                )

                if showsWorkHistory {
                    AgentWorkHistory(trace: trace, tabID: tabID, browser: browser, showsDetails: showsSteps)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
                }

                ChatAssistantMessage(
                    text: trace.response,
                    state: trace.state,
                    onRetry: { onRetry(trace) },
                    onOpenLink: open(_:),
                    allowsContinuation: isLatest
                )
                if let output = trace.checkpoint?.openAI?.presentation {
                    OpenAIOutputView(output: output, providerID: trace.providerID, onOpenLink: open(_:))
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onChange(of: trace.state) { _, _ in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                showsSteps = false
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: trace.state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: trace.response.isEmpty)
        .animation(Theme.Motion.quick, value: hovering)
        .contextMenu {
            Button("Copy Answer") { copy(trace.response) }
                .disabled(trace.response.isEmpty)
            if trace.hasUserPrompt {
                Button("Copy Question") { copy(trace.prompt) }
                Button("Ask Again") { onRetry(trace) }
                Button("Edit Question") { onEdit(trace) }
            }
            Button("Copy Diagnostics") { copy(trace.diagnostics.exported()) }
            Divider()
            if isSpeaking {
                Button("Stop Speaking") { onSpeak(trace) }
            } else {
                Button("Speak Answer") { onSpeak(trace) }
                    .disabled(trace.response.isEmpty)
            }
        }
    }

    static func when(_ trace: ConversationLog.TaskTrace) -> String {
        guard trace.state != .running else { return String(localized: "now") }
        let age = Date().timeIntervalSince(trace.startedAt)
        guard age >= 45 else { return String(localized: "just now") }
        return trace.startedAt.formatted(.relative(presentation: .numeric))
    }

    private func open(_ url: URL) {
        guard let tab = browser.tabs.first(where: { $0.id == tabID }) else { return }
        browser.activate(tab)
        tab.load(url)
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var workLabel: String {
        guard let took else {
            return trace.state == .running ? String(localized: "Working") : ""
        }
        return took
    }

    private var took: String? {
        guard let finishedAt = trace.finishedAt else { return nil }
        let seconds = finishedAt.timeIntervalSince(trace.startedAt)
        guard seconds >= 0.05 else { return nil }
        let places = seconds < 10 ? 1 : 0
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: places))
        )
    }
}

extension ConversationLog.Step {
    var isVisibleInChat: Bool {
        !AgentToolCatalog.outcomeToolIDs.contains(toolName ?? "")
    }
}

private struct ChatUserMessage: View {
    let text: String
    let when: String
    let showsActions: Bool
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.leading, AgentActivityMetrics.bubbleInset)
                .padding(.trailing, AgentActivityMetrics.bubbleInset + ChatBubble.tail)
                .padding(.top, 6)
                .padding(.bottom, 6 + ChatBubble.drop)
                .background {
                    ChatBubble()
                        .fill(.ultraThinMaterial)
                        .overlay { ChatBubble().fill(Theme.Wash.hairline) }
                }
                .padding(.leading, AgentActivityMetrics.bubbleGutter)

            HStack(spacing: 2) {
                if showsActions {
                    ChatCopyAction(help: "Copy this question", action: onCopy)
                    ChatAction(symbol: "arrow.clockwise", help: "Ask this again", action: onRetry)
                    ChatAction(symbol: "pencil", help: "Edit this question", action: onEdit)
                } else {
                    Text(verbatim: when)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.metaInk)
                        .padding(.trailing, 4)
                }
            }
            .frame(height: AgentActivityMetrics.action)
            .padding(.trailing, 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ChatAssistantMessage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    let state: ConversationLog.TaskTrace.State
    let onRetry: () -> Void
    let onOpenLink: (URL) -> Void

    var allowsContinuation = true

    private var isStreaming: Bool {
        state == .running
    }

    /// Avoid creating AppKit text views for selectable text while the answer is streaming.
    @ViewBuilder private var answer: some View {
        if isStreaming {
            Text(verbatim: text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .transition(.opacity)
        } else {
            ChatMarkdown(text: text, onOpenLink: onOpenLink)
                .textSelection(.enabled)
                .transition(.opacity)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !text.isEmpty {
                answer
                    .frame(maxWidth: AgentActivityMetrics.answerWidth, alignment: .leading)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }

            switch state {
            case .failed:
                HStack(spacing: 10) {
                    AgentOutcomeChip(label: "Failed", tint: Theme.warning)
                    Button("Try Again", action: onRetry)
                        .buttonStyle(AgentInlineButtonStyle())
                }
            case .paused, .cancelled:
                HStack(spacing: 8) {
                    AgentOutcomeChip(label: "Paused", tint: .secondary)
                    if allowsContinuation {
                        Button("Continue", action: onRetry)
                            .buttonStyle(AgentInlineButtonStyle())
                    }
                }
            case .running, .completed:
                EmptyView()
            }
        }
        .padding(.trailing, AgentActivityMetrics.bubbleGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatTurnFooter: View {
    let label: String
    let providerID: String?
    let stepCount: Int
    let hasDetails: Bool
    let isThinking: Bool
    let stepsAreShown: Bool
    let showsActions: Bool
    let isSpeaking: Bool
    let readsWithOpenAI: Bool
    let onToggleSteps: () -> Void
    let onCopy: () -> Void
    let onSpeak: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if isThinking {
                ComposingOrb(size: 15)
                    .frame(width: AgentActivityMetrics.action, height: AgentActivityMetrics.action)
            } else if let providerID {
                ProviderBrandIcon(providerID: providerID, size: 12)
                    .frame(width: AgentActivityMetrics.railWidth, height: AgentActivityMetrics.action)
            }

            if !label.isEmpty {
                Text(verbatim: label)
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.metaInk)
            }

            if stepCount > 0 || hasDetails {
                StepsToggle(count: stepCount, hasDetails: hasDetails, isShown: stepsAreShown, action: onToggleSteps)
            }

            if showsActions && !isThinking {
                HStack(spacing: 0) {
                    ChatCopyAction(help: "Copy this answer", action: onCopy)
                    if isSpeaking {
                        ChatAction(symbol: "stop.fill", help: "Stop reading aloud", action: onSpeak)
                    } else if readsWithOpenAI {
                        ChatAction(symbol: "speaker.wave.2", help: "Read this answer aloud. Uses your OpenAI API key.", action: onSpeak)
                    } else {
                        ChatAction(symbol: "speaker.wave.2", help: "Read this answer aloud", action: onSpeak)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: AgentActivityMetrics.action)
        .padding(.trailing, AgentActivityMetrics.bubbleGutter)
    }
}

private struct StepsToggle: View {
    let count: Int
    let hasDetails: Bool
    let isShown: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(verbatim: "·")
                if hasDetails {
                    Text("Details").font(Theme.Font.caption)
                } else if count > 0 {
                    Text("\(count) steps").font(Theme.Font.caption).monospacedDigit()
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .rotationEffect(.degrees(isShown ? 0 : -90))
                    .hoverLift(hovering)
            }
            .foregroundStyle(hovering ? Color.primary : Theme.metaInk)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(isShown ? Text("Hide details") : Text("Show details"))
        .accessibilityValue(isShown ? Text("Expanded") : Text("Collapsed"))
    }
}

private struct ChatCopyAction: View {
    let help: LocalizedStringResource
    let action: () -> Void

    @State private var copyID: UUID?

    var body: some View {
        ChatAction(symbol: copyID == nil ? "doc.on.doc" : "checkmark", help: help) {
            action()
            copyID = UUID()
        }
        .task(id: copyID) {
            guard copyID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                copyID = nil
            } catch {
                // A new copy or a disappearing button cancels the previous reset.
            }
        }
    }
}

private struct ChatAction: View {
    let symbol: String
    let help: LocalizedStringResource
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .imageScale(.small)
                .foregroundStyle(hovering ? Color.primary : Theme.metaInk)
                .hoverLift(hovering)
                .frame(width: AgentActivityMetrics.action, height: AgentActivityMetrics.action)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.quick, value: hovering)
        .help(Text(help))
    }
}
