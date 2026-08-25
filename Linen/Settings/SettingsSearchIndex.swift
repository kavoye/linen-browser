// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct SettingsEntry: Identifiable, Hashable {
    let id: String
    let category: SettingsCategory
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let keywords: [String]

    init(
        _ id: String,
        _ category: SettingsCategory,
        _ title: LocalizedStringResource,
        _ detail: LocalizedStringResource,
        _ keywords: [String] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.keywords = keywords
    }

    var searchableTitle: String {
        String(localized: title)
    }
    var searchableDetail: String {
        String(localized: detail)
    }

    static func == (lhs: SettingsEntry, rhs: SettingsEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SettingsIndex {
    private enum Rank: Int {
        case titlePrefix = 0
        case titleWord = 1
        case titleContains = 2
        case detail = 3
        case keyword = 4
    }

    static let all: [SettingsEntry] = [
        SettingsEntry("general.newTab", .general, "New tabs", "The start page, your homepage, or nothing.",
                      ["new tab", "start page", "blank", "empty", "homepage"]),
        SettingsEntry("general.homepage", .general, "Homepage", "New tabs open with this page.",
                      ["home", "home page", "landing", "url"]),
        SettingsEntry("general.sleepTabs", .general, "Sleep inactive tabs",
                      "Frees memory when the Mac runs low. Tabs reload when you return to them.",
                      ["sleep", "sleeping", "discard", "unload", "memory", "ram", "background tabs", "reload"]),
        SettingsEntry("general.mediaPlayer", .general, "Show media player",
                      "The sidebar shows what’s playing, so you can pause or skip from any tab.",
                      ["media", "player", "video", "audio", "dock", "sidebar", "picture in picture", "pip", "now playing"]),
        SettingsEntry("general.automaticPiP", .general, "Automatic Picture in Picture",
                      "Video moves into a floating window when you leave its tab or switch to another app.",
                      ["picture in picture", "pip", "automatic", "auto", "float", "floating", "video",
                       "pop out", "always on top", "media", "player", "overlay",
                       ]),
        SettingsEntry("general.lyrics", .general, "Show lyrics",
                      "Linen looks up lyrics on LRCLIB. Only the song and artist names leave your Mac, and never from a private tab.",
                      ["lyrics", "words", "sing", "karaoke", "music", "song", "lrclib", "synced", "media", "player"]),
        SettingsEntry("general.agentOnly", .search, "Always ask the assistant", "Questions go to the assistant. Links still open normally.",
                      ["agent", "assistant", "ask", "search", "no search", "web search", "address bar",
                       "omnibox", "command palette", "start page", "model", "llm", "chat",
                       "ask instead of search", "ai", "always ask",
                       ]),
        SettingsEntry("experiments.videoInPlayer", .experiments, "Show video in the player",
                      "When you leave a playing tab, its video moves into the sidebar player. Automatic Picture in Picture turns off while this is on.",
                      ["experiment", "experimental", "video", "player", "media", "sidebar", "picture",
                       "borrow", "flag",
                       ]),
        SettingsEntry("general.import", .general, "Bookmarks",
                      "An HTML file exported from Safari, Chrome, Firefox, or Edge.",
                      ["import", "bookmarks", "favourites", "favorites", "html", "file", "safari",
                       "chrome", "google", "firefox", "edge", "arc", "brave", "opera", "vivaldi",
                       "migrate", "switch", "transfer",
                      ]),
        SettingsEntry("search.engine", .search, "Search engine", "Used when you or the assistant search the web.",
                      ["search engine", "google", "duckduckgo", "bing", "brave", "kagi", "ecosia", "startpage", "wikipedia"]),
        SettingsEntry("search.custom", .search, "Search URL", "Use %s where the search term goes.",
                      ["custom", "own", "template", "url", "%s"]),
        SettingsEntry("search.suggestions", .search, "Search suggestions", "Suggestions from your search engine as you type.",
                      ["autocomplete", "suggest", "predictions", "typing", "omnibox", "address bar"]),
        SettingsEntry("general.defaultBrowser", .general, "Open links from other apps", "Whether Linen is your default browser.",
                      ["default browser", "default", "links", "handler", "http", "https", "system"]),

        SettingsEntry("appearance.theme", .appearance, "Theme", "Light, dark, or match your Mac.",
                      ["dark mode", "light mode", "theme", "appearance", "colour", "color", "night"]),
        SettingsEntry("appearance.windowStyle", .appearance, "Window style", "Choose Standard or Liquid Glass.",
                      ["loom", "window", "standard", "liquid glass", "clear", "opacity",
                       "transparency", "transparent", "translucent", "contrast", "toolbar",
                       "sidebar", "chrome",
                      ]),
        SettingsEntry("appearance.websiteTint", .appearance, "Website tint",
                      "Use the current website’s color in the toolbar and sidebar.",
                      ["website", "colour", "color", "tint", "favicon", "toolbar", "sidebar", "chrome",
                      ]),
        SettingsEntry("appearance.zoom", .appearance, "Page zoom", "The default for every website. Individual tabs can still be zoomed.",
                      ["zoom", "text size", "font size", "magnify", "bigger", "smaller", "scale"]),
        SettingsEntry("appearance.sidebar", .appearance, "Show sidebar", "Show or hide the list of tabs.",
                      ["sidebar", "tabs", "tab list", "column", "hide"]),
        SettingsEntry("appearance.refraction", .appearance, "Tint selected tab", "The selected tab uses the website icon’s color.",
                      ["refract", "glass", "colour", "color", "tint", "selected tab", "favicon", "sidebar"]),
        SettingsEntry("appearance.sidebarStyle", .appearance, "Icons only", "Narrow the sidebar to its icons.",
                      ["sidebar", "icons", "narrow", "compact", "tabs"]),
        SettingsEntry("appearance.reportIssue", .appearance, "Show report button", "Opens the project’s issue page.",
                      ["report", "bug", "issue", "ladybug", "feedback", "github", "sidebar", "hide"]),

        SettingsEntry("profiles.current", .profiles, "Current profile", "What the current profile stores.",
                      ["profile", "current", "open now", "tabs", "history", "extensions", "websites",
                       "size", "disk", "storage",
                       ]),
        SettingsEntry("profiles.list", .profiles, "Other profiles", "Open a profile, or change its name, symbol, and color.",
                      ["profile", "profiles", "work", "personal", "switch", "rename", "delete", "symbol",
                       "icon", "colour", "color", "grey", "gray", "tint", "order", "reorder", "drag",
                       "separate", "kept separate", "clear history",
                       ]),
        SettingsEntry("profiles.add", .profiles, "Add Profile…", "A new profile starts with no history, tabs, or sign-ins.",
                      ["profile", "new profile", "add", "create", "second", "another", "work", "school"]),
        SettingsEntry("profiles.launch", .profiles, "Linen opens in", "Which profile Linen opens in.",
                      ["launch", "startup", "start up", "open", "default profile", "boot"]),

        SettingsEntry("privacy.clear", .privacy, "Clear browsing data", "History, cookies, and cached files, over a chosen time range.",
                      ["cookies", "cache", "reset", "storage", "site data", "delete", "erase", "wipe",
                       "local storage", "clear", "history", "time range", "last hour",
                       ]),
        SettingsEntry("privacy.storage", .privacy, "Website data", "How many websites store data on this Mac.",
                      ["cookies", "storage", "sites", "local storage", "data"]),
        SettingsEntry("privacy.history", .privacy, "Keep history for", "How long visited pages are kept.",
                      ["history", "retention", "forget", "expire", "keep"]),
        SettingsEntry("privacy.quit", .privacy, "Clear on quit", "Cookies, site data, and cached files, every time Linen closes.",
                      ["quit", "exit", "private", "automatic", "cookies", "cache"]),
        SettingsEntry("privacy.assistant", .provider, "Allowed without asking", "Websites the assistant may act on without asking.",
                      ["agent", "assistant", "permission", "always allow", "consent", "purchase", "checkout",
                       "payment", "delete", "post", "revoke", "grant", "confirm", "ask",
                       ]),

        SettingsEntry("websites.javascript", .websites, "JavaScript", "Turn scripts off for every website.",
                      ["javascript", "js", "scripts", "disable"]),
        SettingsEntry("websites.trackers", .websites, "Block known trackers", "Block trackers on every website.",
                      ["tracker", "trackers", "ads", "advertising", "analytics", "block", "privacy",
                       "content blocker", "adblock", "ad blocker", "telemetry", "pixel",
                       ]),
        SettingsEntry("websites.popups", .websites, "Block pop-ups", "Links you click still open.",
                      ["popup", "pop up", "block", "ads", "windows"]),
        SettingsEntry("websites.autoplay", .websites, "Autoplay", "Whether video and sound may start on their own.",
                      ["autoplay", "video", "sound", "audio", "media", "mute"]),
        SettingsEntry("websites.permissions", .websites, "Permissions", "Which websites may use your location, camera, microphone, and notifications.",
                      ["permission", "location", "camera", "microphone", "mic", "notifications", "geolocation",
                       "gps", "webcam", "video call", "allow", "deny", "revoke", "getusermedia",
                       ]),
        SettingsEntry("websites.list", .websites, "Websites you’ve changed", "Every website with a rule of its own, and what that rule allows.",
                      ["site settings", "per site", "exceptions", "assistant access", "read only", "control",
                       "keep active", "always active", "always loaded", "memory", "unload", "background",
                       "trackers", "tracker exception", "reset website",
                       ]),

        SettingsEntry("downloads.folder", .downloads, "Save files to", "Where downloaded files are saved.",
                      ["downloads", "folder", "location", "directory", "save", "files"]),
        SettingsEntry("downloads.ask", .downloads, "Ask where to save each file", "Choose a location every time.",
                      ["ask", "prompt", "where", "save as"]),
        SettingsEntry("downloads.list", .downloads, "Recent downloads", "What you’ve downloaded, and where it was saved.",
                      ["downloads", "files", "recent", "history"]),

        SettingsEntry("provider.model", .provider, "Model", "The model the assistant answers with.",
                      ["gpt", "claude", "llama", "model id", "llm", "provider", "answers"]),
        SettingsEntry("provider.thinking", .provider, "Thinking", "How much reasoning effort the model spends.",
                      ["reasoning", "effort", "thinking"]),
        SettingsEntry("assistant.tools", .provider, "Tools", "What the assistant may do in the browser.",
                      ["tools", "skills", "abilities", "permissions", "search", "click", "type",
                       "read page", "tabs", "video", "context window",
                      ]),
        SettingsEntry("provider.connected", .provider, "Providers",
                      "Every provider you’ve set up.",
                      ["api key", "token", "secret", "keychain", "openai", "anthropic", "google", "groq",
                       "mistral", "deepseek", "openrouter", "xai", "apple intelligence",
                       "base url", "endpoint", "custom", "ollama", "lm studio", "localhost", "server",
                       "add provider", "connect",
                      ]),
        SettingsEntry("voice.readAloud", .provider, "Read aloud", "Speak answers as they arrive.",
                      ["speech", "speak", "mute", "voice", "aloud"]),
        SettingsEntry("voice.talk", .provider, "Push to talk", "Hold while speaking. Release to send.",
                      ["shortcut", "hotkey", "microphone", "mic", "option key", "activation"]),
        SettingsEntry("extensions.installed", .extensions, "Installed extensions", "Chrome extensions running in Linen.",
                      ["chrome", "web store", "add-ons", "plugins", "adblock"]),

        SettingsEntry("advanced.inspector", .advanced, "Web Inspector", "Adds Inspect Element to the page’s right-click menu.",
                      ["developer", "devtools", "inspector", "inspect", "debug", "console"]),
        SettingsEntry("advanced.certificates", .advanced, "Certificate exceptions", "Continue past a certificate macOS rejects. Forgotten when you quit.",
                      ["certificate", "ssl", "tls", "https", "self-signed", "proxy", "untrusted",
                       "invalid certificate", "exception", "warning",
                       ]),
        SettingsEntry("advanced.userAgent", .advanced, "User agent", "Linen uses the system user agent. Changing this can break websites.",
                      ["user agent", "ua", "safari", "spoof", "identify"]),
        SettingsEntry("advanced.reset", .advanced, "Reset settings", "Put appearance, search, privacy, websites, and downloads back to their defaults.",
                      ["reset", "defaults", "factory", "start over"]),
        SettingsEntry("about.updates", .about, "Software update", "Which version is running, and whether a newer one exists.",
                      ["update", "version", "release", "build", "upgrade"]),
        SettingsEntry("about.updates.channel", .about, "Update channel",
                      "Whether updates arrive on releases, or early on preview builds.",
                      ["channel", "preview", "beta", "tip", "nightly", "early", "release",
                       "prerelease", "pre-release", "test build",
                       ]),
        SettingsEntry("about.acknowledgements", .about, "Acknowledgements", "The open source packages Linen is built with.",
                      ["acknowledgements", "acknowledgments", "credits", "licence", "license", "open source",
                       "third party", "attribution", "notice", "sparkle", "mit", "apache",
                       ]),
    ]

    static func search(_ raw: String) -> [SettingsEntry] {
        let needle = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }

        return all
            .compactMap { entry -> (SettingsEntry, Rank)? in
                rank(entry, for: needle).map { (entry, $0) }
            }
            .sorted { left, right in
                left.1.rawValue == right.1.rawValue
                    ? left.0.searchableTitle.localizedStandardCompare(right.0.searchableTitle) == .orderedAscending
                    : left.1.rawValue < right.1.rawValue
            }
            .map(\.0)
    }

    private static func rank(_ entry: SettingsEntry, for needle: String) -> Rank? {
        let title = entry.searchableTitle.lowercased()
        if title.hasPrefix(needle) {
            return .titlePrefix
        }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
            return .titleWord
        }
        if title.contains(needle) {
            return .titleContains
        }
        if entry.keywords.contains(where: { $0.contains(needle) }) {
            return .keyword
        }
        if entry.searchableDetail.lowercased().contains(needle) {
            return .detail
        }
        return nil
    }
}

// MARK: - Anchors

extension EnvironmentValues {
    @Entry var settingsHighlight: String?
    @Entry var settingsIsCompact = false

    @Entry var settingsCardInset: CGFloat = 0

    @Entry var settingsSectionLit = false
}

extension View {
    func settingsAnchor(_ anchor: String) -> some View {
        modifier(SettingsAnchorModifier(anchor: anchor))
    }
}

private struct SettingsAnchorModifier: ViewModifier {
    let anchor: String

    @Environment(\.settingsHighlight) private var highlight
    @Environment(\.settingsCardInset) private var cardInset
    @Environment(\.colorScheme) private var colorScheme

    private var isLit: Bool {
        highlight == anchor
    }

    private static let gap: CGFloat = 4

    private var isInCard: Bool {
        cardInset > 0
    }

    func body(content: Content) -> some View {
        content
            .background(alignment: .center) {
                if isInCard {
                    RoundedRectangle(cornerRadius: Theme.Radius.card - Self.gap, style: .continuous)
                        .fill(isLit ? Theme.Wash.hover : .clear)
                        .padding(.horizontal, -(cardInset - Self.gap))
                        .padding(.vertical, Self.gap - SettingsMetrics.cardInsetV)
                }
            }
            .environment(\.settingsSectionLit, isInCard ? false : isLit)
            .id(anchor)
            .animation(.easeOut(duration: 0.28), value: isLit)
    }
}
