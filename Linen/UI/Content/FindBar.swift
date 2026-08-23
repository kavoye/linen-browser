// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WebKit

@MainActor
struct FindDriver {
    var find: (_ query: String, _ backwards: Bool, _ completion: @escaping @MainActor (Bool) -> Void) -> Void
    var countMatches: (_ query: String, _ completion: @escaping @MainActor (Int) -> Void) -> Void
    var clearHighlight: () -> Void

    static func webKit(_ webView: @escaping @MainActor () -> WKWebView?) -> FindDriver {
        FindDriver(
            find: { query, backwards, completion in
                guard let webView = webView() else {
                    completion(false)
                    return
                }
                let configuration = WKFindConfiguration()
                configuration.backwards = backwards
                configuration.caseSensitive = false
                configuration.wraps = true
                webView.find(query, configuration: configuration) { result in
                    MainActor.assumeIsolated { completion(result.matchFound) }
                }
            },
            countMatches: { query, completion in
                guard let webView = webView() else {
                    completion(0)
                    return
                }
                webView.evaluateJavaScript(FindSession.countScript(for: query)) { value, _ in
                    MainActor.assumeIsolated { completion(value as? Int ?? 0) }
                }
            },
            clearHighlight: {
                webView()?.evaluateJavaScript("window.getSelection().removeAllRanges()")
            }
        )
    }
}

@MainActor
@Observable
final class FindSession {
    var isActive = false
    var query = ""
    var noMatches = false
    private(set) var focusToken = 0

    private(set) var totalMatches = 0
    private(set) var currentMatch = 0

    var driver: FindDriver?

    private var generation = 0

    func open() {
        isActive = true
        focusToken += 1
    }

    func close() {
        isActive = false
        query = ""
        reset()
        driver?.clearHighlight()
    }

    func pageChanged() {
        guard isActive || !query.isEmpty else { return }
        close()
    }

    private func reset() {
        noMatches = false
        totalMatches = 0
        currentMatch = 0
        generation += 1
    }

    func queryDidChange() {
        generation += 1
        let expected = generation
        guard let driver, !query.isEmpty else {
            noMatches = false
            totalMatches = 0
            currentMatch = 0
            return
        }
        driver.countMatches(query) { [weak self] total in
            guard let self, generation == expected else { return }
            totalMatches = total
        }
        driver.find(query, false) { [weak self] found in
            guard let self, generation == expected else { return }
            noMatches = !found
            currentMatch = found ? 1 : 0
        }
    }

    func find(backwards: Bool = false) {
        guard isActive, !query.isEmpty else {
            open()
            return
        }
        guard let driver else { return }
        let expected = generation
        driver.find(query, backwards) { [weak self] found in
            guard let self, generation == expected else { return }
            noMatches = !found
            guard found else {
                currentMatch = 0
                return
            }
            currentMatch = Self.step(from: currentMatch, of: totalMatches, backwards: backwards)
        }
    }

    func findNext(backwards: Bool) {
        find(backwards: backwards)
    }

    nonisolated static func step(from current: Int, of total: Int, backwards: Bool) -> Int {
        guard total > 0 else { return 0 }
        guard current > 0 else { return backwards ? total : 1 }
        if backwards {
            return current == 1 ? total : current - 1
        }
        return current == total ? 1 : current + 1
    }

    nonisolated static func countScript(for query: String) -> String {
        let json = (try? JSONEncoder().encode([query]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"[""]"#
        return """
        (() => {
          const needle = \(json)[0].toLowerCase();
          if (!needle) return 0;
          const haystack = (document.body ? document.body.innerText : '').toLowerCase();
          let count = 0;
          let index = haystack.indexOf(needle);
          while (index !== -1) {
            count += 1;
            index = haystack.indexOf(needle, index + needle.length);
          }
          return count;
        })()
        """
    }
}

struct FindBar: View {
    @Bindable var session: FindSession

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Font.label)
                .foregroundStyle(.secondary)

            TextField("Find on page", text: $session.query)
                .textFieldStyle(.plain)
                .font(Theme.Font.row)
                .frame(width: 200)
                .focused($focused)
                .onSubmit { session.find() }
                .onChange(of: session.query) { _, _ in session.queryDidChange() }

            if !session.query.isEmpty {
                if session.totalMatches > 0 {
                    Text("\(session.currentMatch) of \(session.totalMatches)")
                        .font(Theme.Font.label)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else if session.noMatches {
                    Text("Not found")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.warning)
                }
            }

            Divider()
                .frame(height: 14)

            Button {
                session.find(backwards: true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(Theme.Font.badge)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Previous (⇧⌘G)")

            Button {
                session.find()
            } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.Font.badge)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Next (⌘G)")

            Button("Done") { session.close() }
                .buttonStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .onAppear { focused = true }
        .onChange(of: session.focusToken) { _, _ in focused = true }
        .onKeyPress(.escape) {
            session.close()
            return .handled
        }
    }
}
