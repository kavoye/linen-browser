# Changelog

## 0.2.0

### New

- **Lyrics for the song that is playing.** Linen finds the words on LRCLIB and lights each line as it is sung. Open them from the media player, from View › Show Lyrics, or with ⌥⌘Y. The words follow the tab you are watching, and the title opens a menu to pick another tab when more than one is playing. Change the text size, nudge the timing earlier or later, or choose a different match when the first one is wrong. Only the name of the song and the name of the artist leave your Mac, and never from a private tab. Turn it off in Settings › General.
- **One side panel on the right.** Activity and Lyrics are tabs in the same panel now. A single toolbar button opens it, marked with the assistant’s state or a music note, and the arrows expand the panel to fill the window beside the sidebar.
- **Picture in Picture.** A button in the address field sends the video of the page to a floating window. Turn on Automatic Picture in Picture in Settings › General and the video leaves on its own when you go to another tab or another app, then comes home when you come back.
- **The player follows what every tab plays.** Linen watches each tab, so the player knows which tab to control and the lyrics know which tab to read.
- **Media settings.** Settings › General has a Media section: Show media player, Automatic Picture in Picture, and Show lyrics.
- **An Experiments page in Settings.** It holds unfinished work you can try, and anything there can change or go away. The first one moves the video of a playing tab into the sidebar player when you leave that tab.
- **Import bookmarks from any browser.** Export a bookmarks HTML file from Safari, Chrome, Firefox, Edge or anything else, then choose it in Settings › General. Linen no longer reads another browser’s files, so macOS stops asking for access to them. History no longer comes across.
- **Save Page As… and Print Page… in the page menu.** Right-click a page and both sit under Reload Page. Save writes a web archive of the page you are on.
- **A new tab opens below the tab that opened it.** A link that opens in its own tab lands beside its page instead of at the top of the sidebar.

### Improved

- **Voice settings moved to Settings › Assistant.** Read aloud and Push to talk are how you speak to the assistant, so they now sit on its page. The Voice page is gone.
- **Agent Activity is Assistant Activity.** The menu item and the command palette use the same word as the rest of the app.
- Closing a tab takes you to the tab below it, not to the top of the sidebar.
- Every menu marks the chosen item the way macOS does.

### Fixed

- The media player no longer holds a frozen track after the web content process of its tab dies.
- Settings, History and the other internal pages slide in only when they actually move.

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

First release. Linen is a WebKit browser for macOS 26 and later.

### The assistant

- **It works in the tabs you already have open.** It searches, opens websites, reads them, clicks, types and scrolls.
- **Ask in the address field, or hold ⌥Space and speak.** Click the page and it’s yours again.
- **It asks first before it buys, sends or signs in.** It never fills a password or a card number.

### Models

- **Apple Intelligence runs on-device out of the box.**
- **Add your own key** for OpenAI, Anthropic, Gemini, DeepSeek, Groq, Mistral, OpenRouter or xAI.
- **Or point Linen at a local server** like Ollama or LM Studio.

### The browser

- Tabs, folders, pinned tabs and split view.
- Profiles and private browsing.
- A command palette, history and find in page.
- Downloads that resume, and per-website zoom.
- Extensions install from the Chrome Web Store.

### Before you start

- This is a 0.x release. The formats that Linen writes to disk for sessions, history and profiles can still change between versions.
- The main limitations are one window, no password autofill, no web push, and no on-device voice on Intel Macs. The README lists them all.
