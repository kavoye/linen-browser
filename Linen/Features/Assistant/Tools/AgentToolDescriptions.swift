// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

extension AgentToolkit {
    nonisolated enum Descriptions {
        static let searchWeb = "Search the web for one to four queries, optionally on one domain. Return links and summaries without leaving the page."
        static let navigate = """
            Open a web URL in the active tab so the user can see it. Return its rendered text and controls.
            """
        static let newTab = "Open a new tab. Use this only when the user asks for another tab."
        static let askUser = "Ask everything you still need in one call and wait for the answers. One thing per question; put the choices in options."
        static let listTabs = """
            List every tab open in this window, with its title and site. Use this when the user \
            asks about their tabs as a whole. The list names every tab; reading one still needs \
            you to switch to it, or the person to attach it.
            """
        static let switchTab = """
            Switch to a page in this conversation - on screen, attached by the user, or opened \
            during this task - by part of its title or site name. For any other tab, ask the user to \
            attach it with @ or switch to it themselves.
            """
        static let closeTab = "Close the active tab, or close a tab in this conversation by part of its title."
        static let readPage = "Read the page text and list each control with a [ref] number. Use lookingFor to return only the relevant part."
        static let readArticle = "Read only the main text of an article, post, or documentation page."
        static let clickOnPage = "Click a control by its [ref], or by its label. The browser asks before payments and posting; stop if the user declines."
        static let typeOnPage = "Type into a control by [ref] or label, optionally submitting. Use fillFields for several fields. The browser refuses passwords and payment details."
        static let fillFields = """
            Fill up to 32 fields in one call without submitting: text, dropdowns, dates, #RRGGBB colors, numbers, and true/false \
            for checkboxes and radios. Copy the latest observationID. Skips sensitive, read-only, and file fields.
            """
        static let selectOption = "Choose an option in a native select control by its [ref] or label. For custom dropdowns, use clickOnPage on a visible option."
        static let scrollPage = "Scroll up, down, left, or right. Supply a ref inside a container to scroll that container."
        static let goBack = "Go back one page."
        static let playVideo = "Find a video by topic and play it in a background tab."
        static let closeVideo = "Pause the video and close the media player. Keep its tab open."
        static let controlMedia = "Use pip to enter Picture in Picture, or exitPip to leave it."
        static let watchPage = """
            Check a page in the background on a schedule and notify the person once when it shows \
            what they are waiting for, like a price drop, a restock or a finished build. Use this \
            only when the person asks to be told later. Open the page first; the watch reads it \
            signed in as the person, from their own browser.
            """
        static let listWatches = "List the pages being watched, with what each watch is waiting for."
        static let stopWatch = "Stop watching a page, by watch ID or part of its title, address or condition."
    }
}
