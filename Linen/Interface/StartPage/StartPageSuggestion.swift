// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct StartPageSuggestion: Identifiable {
    let symbol: String
    let label: LocalizedStringResource
    let ask: String

    var id: String {
        ask
    }

    static let all = [
        StartPageSuggestion(
            symbol: "newspaper",
            label: "What’s on Hacker News?",
            ask: "what’s on hacker news right now?"
        ),
        StartPageSuggestion(symbol: "music.note", label: "Play chill lofi", ask: "play chill lofi"),
        StartPageSuggestion(symbol: "bag", label: "Find Nike Pegasus 42", ask: "find nike pegasus 42"),
        StartPageSuggestion(
            symbol: "cloud.sun",
            label: "Weather this weekend",
            ask: "what’s the weather this weekend?"
        ),
        StartPageSuggestion(
            symbol: "fork.knife",
            label: "Dinner ideas",
            ask: "give me dinner ideas for tonight"
        ),
        StartPageSuggestion(symbol: "airplane", label: "Flights to Lisbon", ask: "find flights to lisbon"),
        StartPageSuggestion(
            symbol: "chart.line.uptrend.xyaxis",
            label: "How are markets today?",
            ask: "how are the markets doing today?"
        ),
        StartPageSuggestion(
            symbol: "creditcard",
            label: "Compare AirPods prices",
            ask: "compare airpods prices"
        ),
        StartPageSuggestion(
            symbol: "map",
            label: "Plan a day out",
            ask: "plan a day out for me"
        ),
        StartPageSuggestion(
            symbol: "book",
            label: "Explain a paper to me",
            ask: "explain a paper to me in plain english"
        ),
    ]
}
