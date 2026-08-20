# Changelog

## 0.1.1

### New

- **Preview channel.** Settings › About has an Update channel. Set it to Preview and Linen follows the newest commit on `main` instead of waiting for the next release. Set it back to Release at any time.
- **One-click install.** Install in the update banner does the whole thing — it downloads the update, installs it and starts Linen again. Linen asks once.
- **Release notes in the app.** The notes for a new version open in a tab after it lands. Linen › Release Notes opens them whenever you want them.
- **⌃⇥ goes back to your last tab.** Tap it and Linen returns the way ⌘⇥ returns you to the last app. Hold ⌃ and ⌃⇥ walks down the sidebar, ⌃⇧⇥ walks up.
- **Dictation sends itself.** Click the orb and talk: Linen sends what you said once you stop speaking. ⌥Space still sends when you let go.
- **Stop the assistant from the orb.** Click it while a turn is running and the turn stops.
- **⌘↩ and ⇧↩ in the command palette.** ⌘↩ asks the assistant about what you typed. ⇧↩ opens a search in a new tab.

### Improved

- **A long conversation no longer breaks the turn.** The assistant recovers from a full context window and carries on.
- **The assistant counts only the links it listed for you.**

### Fixed

- A pasted link no longer brings its own styling into the address field.
- The first profile starts grey.
- A tab stops spinning after a back that stays on the same page.
- The scroll wheel no longer pulls the page while the command palette is up.
- A sleeping tab shows an opaque badge and a grey preview.
- The activity column’s toggle, resize edge and attention dot settle where they belong.

## 0.1.0

First release.

Linen is a WebKit browser for macOS 26 and later. The assistant works in the
tabs you already have open. It searches, opens websites, reads them, clicks,
types and scrolls. Ask in the address field, or hold ⌥Space and speak. Click
the page and it’s yours again.

Apple Intelligence runs on-device out of the box. Add your own key for OpenAI,
Anthropic, Gemini, DeepSeek, Groq, Mistral, OpenRouter or xAI, or point Linen at
a local server like Ollama or LM Studio.

The assistant asks first before it buys, sends or signs in. It never fills a 
password or a card number.

The rest is a normal browser: tabs, folders, pinned tabs, profiles, private
browsing, split view, a command palette, history, downloads that resume, find in
page and per-website zoom. Extensions install from the Chrome Web Store.

This is a 0.x release. The formats that Linen writes to disk for sessions,
history and profiles can still change between versions.

The README lists the known limitations. The main ones are one window, no
password autofill, no web push, and no on-device voice on Intel Macs.
