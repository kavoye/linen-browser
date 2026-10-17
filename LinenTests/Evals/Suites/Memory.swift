// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@testable import Linen

nonisolated enum MemoryTasks {
    private static let lamp = """
        <main><h1>Aster desk lamp</h1><p>A brass desk lamp with a linen shade. Price $129.</p>
        <form method="post" action="/order"><label>Colour <select id="colour" name="colour"><option>Black</option><option>Brass</option><option>White</option></select></label>
        <button>Place order</button></form></main>
        """

    private static let routes: [String: EvalSite.Handler] = [
        "/": { _ in .page("Aster desk lamp", lamp) },
        "/order": { _ in .page("Order placed", "<h1>Order placed</h1>") },
    ]

    static let all: [EvalTask] = [
        EvalTask(
            id: "learn-preference", covers: ["askUser", "selectOption"], requires: ["selectOption"],
            instruction: "Set the Aster desk lamp on this page to my usual colour. Do not place an order.",
            routes: routes,
            answers: ["Brass"],
            checks: [
                .page("colour is Brass", "document.getElementById('colour').value === 'Brass'"),
                .remembers("usual colour", "Brass"),
                .never("did not place the order") { $0.path == "/order" },
            ]
        ),
        EvalTask(
            id: "recall-preference", covers: ["selectOption"], requires: ["selectOption"],
            instruction: "Set the Aster desk lamp on this page to my usual colour. Do not place an order.",
            routes: routes,
            setup: { context in _ = context.browser.memory.remember("usual colour", is: "Brass", source: .answer) },
            checks: [
                .page("colour is Brass", "document.getElementById('colour').value === 'Brass'"),
                .notUsed("askUser"),
                .never("did not place the order") { $0.path == "/order" },
            ]
        ),
        EvalTask(
            id: "volunteered-fact", covers: ["readPage"],
            instruction: "I'm vegetarian. Which dinner recipe on this page could I make tonight?",
            routes: ["/": { _ in .page("Dinner recipes", """
                <main><h1>Dinner recipes</h1><ul>
                <li>Chicken and leek pie, 50 minutes</li><li>Mushroom risotto, 35 minutes, vegetarian</li><li>Grilled salmon with greens, 25 minutes</li>
                </ul></main>
                """) },
            ],
            checks: [.answer("risotto"), .remembersValue("vegetarian")]
        ),
        EvalTask(
            id: "remember-request",
            instruction: "Please remember that my shoe size is 42.",
            routes: routes,
            checks: [.remembers("shoe size", "42")]
        ),
        EvalTask(
            id: "remember-like",
            instruction: "Please remember that I like cars.",
            routes: routes,
            checks: [.remembersExactly("cars")]
        ),
        EvalTask(
            id: "volunteered-interest",
            instruction: "I'm really into jazz, so keep that in mind for later.",
            routes: routes,
            checks: [.remembersExactly("jazz")]
        ),
    ]
}
