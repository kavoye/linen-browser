// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

extension AgentToolkit {
    nonisolated enum Descriptions {
        static let searchWeb = """
            Search one to four queries concurrently, optionally restricted to a domain. Return deduplicated links and summaries without navigating the current page.
            """
        static let navigate = """
            Open a web URL in the active tab so the user can see it. Return its rendered text and controls.
            """
        static let newTab = "Open a new tab. Use this only when the user asks for another tab."
        static let askUser = """
            Ask everything you still need to know in ONE call and wait: the answers come back as \
            this tool's result. ONE thing per question - never join two with "and", send them as \
            separate questions and the person steps through them. Put the choices in options, \
            never in the question text: ask "Where would you like to go?" with options, not \
            "Where would you like to go - the park, a museum, or the shops?". Leave options empty \
            only when the answer is open, like a date or a name. Ask once, then carry on.
            """
        static let listTabs = """
            List every tab open in this window, with its title and site. Use this when the user \
            asks about their tabs as a whole. The list names every tab; reading one still needs \
            you to switch to it, or the person to attach it.
            """
        static let switchTab = """
            Switch to a page in this conversation - on screen, attached by the user, or opened \
            during this task - by part of its title or site name.
            """
        static let closeTab = "Close the active tab, or close a tab in this conversation by part of its title."
        static let readPage = """
            Read a page on screen and list each control with a [ref] number. Use lookingFor to return \
            the relevant part. Pass pageID when targeting another page. Use pagination for more content. \
            Actions return fresh observations; read again when stale or missing needed content. \
            Control offsets are list positions, not [ref] numbers. Start at 0 when changing the query, scope, or viewport filter.
            """
        static let clickOnPage = """
            Click a control by its [ref], or by its label when no ref is available. The browser asks \
            before payments, money transfers, account deletion, or posting as the user. Stop if the \
            user declines. Click a read-only date field to open its calendar, then click a day.
            """
        static let typeOnPage = """
            Type into a field by its [ref] or label, with optional submission. The browser refuses \
            passwords, payment details, codes, and account or identity numbers.
            """
        static let selectOption = "Choose an option in a native select control by its [ref] or label. For custom dropdowns, use clickOnPage on a visible option."
        static let scrollPage = "Scroll up, down, left, or right. Supply a ref inside a container to scroll that container."
        static let goBack = "Go back one page."
        static let playVideo = "Find a video by topic and play it in a background tab."
        static let closeVideo = "Pause the video and close the media player. Keep its tab open."
        static let controlMedia = "Use pip to enter Picture in Picture, or exitPip to leave it."
    }
}
