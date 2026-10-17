// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation

@testable import Linen

nonisolated enum FlowTasks {
    private static let header = """
        <header><nav><a href="/">Home</a> · <a href="/lamps">Lamps</a> · <a href="/textiles">Textiles</a> · <a href="/cart">Cart</a></nav></header>
        """

    private static func page(_ title: String, _ body: String) -> EvalSite.Handler {
        { _ in .page(title, header + body) }
    }

    private static func cart(_ store: EvalStore) -> EvalSite.Handler {
        { request in
            if request.method == "POST" {
                let product = request.form["product"] ?? ""
                let quantity = Int(request.form["qty"] ?? "1") ?? 1
                store[product] = String((Int(store[product] ?? "0") ?? 0) + max(1, quantity))
                return .redirect("/cart")
            }
            let lines = [("aster", "Aster desk lamp", 129), ("birch", "Birch desk lamp", 99)].compactMap { id, name, price -> (String, Int)? in
                guard let count = Int(store[id] ?? "0"), count > 0 else { return nil }
                return ("<li>\(name) × \(count) — $\(price * count)</li>", price * count)
            }
            guard !lines.isEmpty else { return .page("Cart", header + "<h1>Cart</h1><p>Your cart is empty.</p>") }
            return .page("Cart", header + """
                <h1>Cart</h1><ul>\(lines.map(\.0).joined())</ul><p>Total: $\(lines.map(\.1).reduce(0, +))</p>
                <form method="post" action="/checkout"><button>Check out</button></form>
                """)
        }
    }

    private static func product(_ id: String, _ name: String, _ price: Int) -> EvalSite.Handler {
        page(name, """
            <main><h1>\(name)</h1><p>Price $\(price)</p>
            <form method="post" action="/cart"><input type="hidden" name="product" value="\(id)">
            <label>Quantity <input type="number" name="qty" value="1" min="1"></label>
            <button>Add to cart</button></form></main>
            """)
    }

    static let all: [EvalTask] = [
        EvalTask(
            id: "cart-total", covers: ["typeOnPage", "clickOnPage", "readPage"],
            instruction: "Add two Aster desk lamps to the cart, then tell me the cart total.",
            routes: ["/": product("aster", "Aster desk lamp", 129)],
            stateful: { store in ["/cart": cart(store), "/checkout": { _ in .page("Order placed", "<p>Thanks for your order.</p>") }] },
            maxRequests: 20,
            checks: [.stored("aster", "2"), .answer("258"), .never("did not check out") { $0.path == "/checkout" }]
        ),
        EvalTask(
            id: "save-setting", covers: ["navigate", "typeOnPage", "clickOnPage"],
            instruction: "In my account settings on this site, change the city to Lviv and save it.",
            routes: ["/": page("Account", "<main><h1>Your account</h1><p>Signed in as Ada Lovelace.</p><a href=\"/settings\">Settings</a></main>")],
            stateful: { store in
                store["name"] = "Ada Lovelace"
                store["city"] = "Kyiv"
                return ["/settings": { request in
                    if request.method == "POST" {
                        store["name"] = request.form["name"] ?? ""
                        store["city"] = request.form["city"] ?? ""
                        return .redirect("/settings?saved=1")
                    }
                    let saved = request.query["saved"] == "1" ? "<p>Settings saved.</p>" : ""
                    return .page("Settings", header + """
                        <main><h1>Settings</h1>\(saved)<form method="post" action="/settings">
                        <label>Name <input name="name" value="\(store["name"] ?? "")"></label>
                        <label>City <input name="city" value="\(store["city"] ?? "")"></label>
                        <button>Save</button></form></main>
                        """)
                },
            ]
            },
            maxRequests: 20,
            checks: [.stored("city", "Lviv"), .stored("name", "Ada Lovelace")]
        ),
        EvalTask(
            id: "compare-prices", covers: ["navigate", "clickOnPage", "readPage"],
            instruction: "Which is cheaper on this shop, the Aster or the Birch desk lamp? Tell me its price.",
            routes: [
                "/": page("Shop", "<main><h1>Linen Home</h1><p>Lamps and textiles for calm rooms.</p></main>"),
                "/lamps": page("Lamps", "<main><h1>Lamps</h1><ul><li><a href=\"/lamps/aster\">Aster desk lamp</a></li><li><a href=\"/lamps/birch\">Birch desk lamp</a></li></ul></main>"),
                "/lamps/aster": product("aster", "Aster desk lamp", 129),
                "/lamps/birch": product("birch", "Birch desk lamp", 99),
            ],
            maxRequests: 20,
            checks: [.answer("Birch"), .answer("99")]
        ),
        EvalTask(
            id: "book-table", covers: ["selectOption", "fillFields", "clickOnPage"],
            instruction: "Book a table on this page for 4 people on Friday at 19:00 under the name Ada.",
            routes: [:],
            stateful: { store in [
                "/": { request in
                    if request.method == "POST" {
                        store["party"] = request.form["party"]
                        store["day"] = request.form["day"]
                        return .redirect("/details")
                    }
                    return .page("Book a table", header + """
                        <main><h1>Book a table</h1><form method="post" action="/">
                        <label>Party size <select name="party"><option>2</option><option>3</option><option>4</option><option>5</option></select></label>
                        <label>Day <select name="day"><option>Thursday</option><option>Friday</option><option>Saturday</option></select></label>
                        <button>Next</button></form></main>
                        """)
                },
                "/details": { request in
                    if request.method == "POST" {
                        store["time"] = request.form["time"]
                        store["name"] = request.form["name"]
                        store["booked"] = "yes"
                        return .page("Booked", header + "<p>Booked: a table for \(store["party"] ?? "") on \(store["day"] ?? "").</p>")
                    }
                    return .page("Booking details", header + """
                        <main><h1>Booking details</h1><form method="post" action="/details">
                        <label>Time <select name="time"><option>18:00</option><option>19:00</option><option>20:00</option></select></label>
                        <label>Name <input name="name"></label>
                        <button>Confirm booking</button></form></main>
                        """)
                },
            ] },
            maxRequests: 20,
            checks: [.stored("party", "4"), .stored("day", "Friday"), .stored("time", "19:00"), .stored("name", "Ada"), .stored("booked", "yes")]
        ),
        EvalTask(
            id: "filter-list", covers: ["typeOnPage", "readPage"],
            instruction: "Show only textiles under $50 on this shop's textiles page and tell me how many there are.",
            routes: [
                "/": page("Shop", "<main><h1>Linen Home</h1><p>Lamps and textiles for calm rooms.</p></main>"),
                "/textiles": { request in
                    let items = [("Linen napkin", 25), ("Tea towel", 35), ("Cushion cover", 45), ("Table runner", 49), ("Throw", 80), ("Duvet cover", 120)]
                    let limit = request.query["max"].flatMap { Int($0) }
                    let shown = items.filter { limit == nil || $0.1 < limit! }
                    return .page("Textiles", header + """
                        <main><h1>Textiles</h1><form method="get" action="/textiles">
                        <label>Maximum price <input name="max" type="number"></label><button>Apply</button></form>
                        <p>\(limit == nil ? "Showing all textiles." : "\(shown.count) results under $\(limit!).")</p>
                        <ul>\(shown.map { "<li>\($0.0)</li>" }.joined())</ul></main>
                        """)
                },
            ],
            maxRequests: 20,
            checks: [.request("filtered under $50") { $0.path == "/textiles" && $0.query["max"] == "50" }, .answer("4")]
        ),
        EvalTask(
            id: "cart-no-checkout", covers: ["clickOnPage", "readPage"],
            instruction: "Add the Birch desk lamp to my cart, but don't check out.",
            routes: ["/": product("birch", "Birch desk lamp", 99)],
            stateful: { store in ["/cart": cart(store), "/checkout": { _ in .page("Order placed", "<p>Thanks for your order.</p>") }] },
            maxRequests: 20,
            checks: [.stored("birch", "1"), .never("did not check out") { $0.path == "/checkout" }]
        ),
    ]
}
