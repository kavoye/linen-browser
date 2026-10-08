# Changelog

## 0.8.0

### New

- **Multiple windows.** Open more than one browser window. Linen restores your
  windows after relaunch. Move tabs between windows of the same profile
  without reloading them.
- **Open links in a new window.** Choose Open Link in New Window from a link's
  context menu. Hold Option to open the link in a new private window. Press
  ⇧⌘N to open a private window. Closing it ends that private session.
- **Settings for each profile.** Each profile keeps its own assistant settings,
  approvals, and website settings.
- **Side Panel.** The Side Panel holds the assistant and the integrations you
  add. Choose the add button to add Lyrics or GitHub, and Control-click a tab
  to remove it. Press ⌥⌘S to show or hide the Side Panel.
- **GitHub integration.** Connect GitHub to review pull requests in the Side
  Panel. See review requests, mentions, and your pull requests in one inbox.
  Filter and sort pull requests, and open one to see its checks, reviews,
  comments, and files.
- **GitHub notifications and previews.** Get notified when your pull requests
  get reviews, comments, or check results. Hover over a pull request tab to
  see its status, or Shift-click a pull request link to peek at it.
- **Search GitHub from the address bar.** Type "github" and press Tab to search
  pull requests. Ask the assistant to explain a pull request or a failing
  check.
- **Reader.** Linen now has Reader. It shows just the main text of an article.
  Choose the font, style, and text size, and have the article read aloud.
  Press ⌥⌘R to show or hide Reader.
- **Page translation.** Translate a page on this Mac. Choose Translate Page from
  the View menu, and choose View Original to switch back. You can always
  translate a language.
- **Page watches.** Ask the assistant to watch a page. Linen checks the page on
  a schedule and notifies you when it changes. Apple Intelligence compares the
  page on your Mac, so page content stays on your Mac. See and stop watched
  pages in the Side Panel.
- **Tab archiving.** Archive tabs you haven't used. Choose a time in Settings >
  General. Pinned tabs stay open, and you can find archived tabs with ⌘K.
- **Site search in the command palette.** Type a name such as YouTube, Reddit,
  GitHub, or Amazon, then press Tab. Press Return to open results in a new
  tab, or Option-Return to open them in the current tab.
- **Handoff.** Continue the current tab on iPhone or iPad. Private tabs are not
  shared.
- **Voice settings.** Voice settings have their own page. Recognize speech and
  read answers aloud with this Mac at no cost or with OpenAI. You can also
  have every answer read aloud automatically.
- **Tab switcher previews.** Press Control-Tab to see previews of your recent
  tabs while you switch.
- **Web Inspector shortcut.** Choose View > Developer > Show Web Inspector, or
  press ⌥⌘I.
- **Track controls.** The media card has Previous Track and Next Track buttons.

### Improved

- **Permission to open apps.** Websites ask before they open another app. Allow
  an app once or always for a website, and change your choice in website
  settings.
- **Better form filling.** The assistant can fill up to 32 form controls at
  once, including dates, colors, sliders, checkboxes, and radio buttons. It
  reports the fields it could not fill.
- **Rate limit recovery.** When a provider's rate limit is reached, the
  assistant waits and tries again. If the limit continues, your progress is
  saved so you can continue later.
- **Clearer assistant pauses.** Pause messages say why the task stopped and what
  to do next.
- **Questions stay in their space.** Assistant questions appear only in the
  space where you started the request.
- **Less background work.** Idle media players, hidden pages, and lyrics no
  longer update, and external assistant connections no longer check for
  messages while idle.
- **PDF downloads.** PDFs open in Linen are saved through Downloads.
- **Better tab titles.** Tabs show PDF filenames, and pages without a title get
  a better name.
- **Solid Side Panel.** Turn on Solid background in Appearance settings to show
  the Side Panel without transparency.
- **Folder deletion.** When you delete a folder, you can close its tabs too.
- **Split view by drag.** Drag a tab onto the page to open it in split view.
- **Codex setup.** Codex setup finds the Codex CLI included with the Codex app.

### Fixed

- **Scroll position.** Restored pages keep their scroll position.
- **Command palette shortcuts.** Editing shortcuts work with Caps Lock on and
  with keyboard layouts that change letters while Command is held.
- **Autofill placement.** Autofill suggestions no longer appear in the wrong
  place when a field moves after it gets focus.
- **Assistant key presses.** The assistant no longer reports a key press as
  failed when the page handles the key.
- **MCP connections.** External assistants that send experimental MCP
  capabilities can connect.
- **Local website icons.** Website icons load for local development servers.
- **Sidebar drop targets.** Drop targets stay visible on light websites.
- **Folder previews.** Folder preview icons are easier to see in Dark Mode.
- **Dock menu titles.** Page titles in the Dock menu are limited to 40
  characters.

### Removed

- **Show lyrics setting.** Add Lyrics to the Side Panel instead.
- **⌥⌘A and ⌥⌘Y shortcuts.** Press ⌥⌘S to show the Side Panel.
- **Recent downloads list.** The list is no longer in Downloads settings.
  Choose Open downloads to see your downloads.

## 0.7.1

### New

- New Tab opens the command palette. Enter an address or search, then choose
  a result to create the tab. Choose Open Start Page to open the start page.
- The assistant can drag and double-click on pages, interact with embedded
  pages, upload files you select, and check downloads. Page permissions apply.

### Improved

- The assistant checks page and download results before marking a task complete
  and reports outcomes it cannot verify.
- Pages opened by the assistant appear in the active tab so you can follow
  its work.
- Conversation context limits now account for the selected provider and model.
- Settings search opens the relevant page and highlights the matching control,
  including controls within OpenAI settings.
- Sleeping tabs release more memory. Reloading can recover pages whose browser
  process has stopped responding.

### Fixed

- The assistant retries temporary provider failures without repeating browser
  actions that already ran.
- Voice configuration uses the provider you selected.
- Moving the pointer over command palette suggestions no longer replaces
  what you typed.
- Autofill can reuse a recent authentication on the same page. It asks again
  after you navigate or switch profiles.
- Writing fields that mention an email address or name no longer trigger
  contact autofill suggestions.
- Repaired update sources for older Firefox extension installations and fixed
  compatibility with extension icons and keyboard shortcuts.
- Certificate checks no longer hang the browser.
- The address bar loading indicator feels smoother when loading the page.

### Removed

- The OpenAI document-search library. You can still attach files to messages.
- The blank-page and custom-homepage options for new tabs.

## 0.7.0

### New

- Save and fill passwords, payment cards, and contact details. Manage saved
  entries in Settings > Autofill. Passwords and cards require system
  authentication. You can also use a password manager extension.
- Attach images, PDFs, and text files to assistant messages.
- Have a voice conversation with the assistant through OpenAI. Choose a voice
  in assistant settings, interrupt a reply, and review the conversation in chat.
- Use OpenAI models to search the web, create images, and work with data.
  Supported tools are available automatically. OpenAI usage charges apply.
- Connect external services to the OpenAI assistant through MCP.
- Use the assistant's page screenshot, pointer, and keyboard tools to interact
  with a page. Browser control requires your permission.
- Connect an external assistant to Linen through its MCP server. Share selected
  tabs with read-only access or permission to control them. Setup is available
  for Codex, Claude Desktop, Claude Code, and Cursor.

### Improved

- The assistant saves progress so you can continue interrupted tasks. It checks
  uncertain actions before retrying them and pauses when it keeps getting stuck.
- Long conversations can compact their working context automatically or on
  demand. A context indicator shows estimated usage.
- Assistant activity now shows progress updates and groups completed work.
- OpenAI settings have separate pages for voice, connections, and privacy
  settings. Advanced options are under Developer Settings.
- Collapse a Peek preview and reopen it without losing the page.
- Use the arrow keys in the address field to preview a suggested address before
  opening it.
- Website icons stay readable against light and dark backgrounds. New settings
  default to website tint and tab color effects.
- Website permission controls and download progress are easier to read.
- Diagnostic logs omit page content, conversation text, and raw provider errors.

### Fixed

- Page commands now act on the visible Peek preview.
- Updating a pinned page no longer moves it within the sidebar.
- Starting a new tab no longer shows a loading state for its background warm-up.

## 0.6.1

### New

- Right-click a link for Open Link in Peek and Summarize Link.
- Sign in to websites with a passkey.

### Improved

- Moving tabs, folders and tab pinning in the sidebar is clearer.
- The assistant shows the same thinking mark in the side panel and on the
  summary card.

### Fixed

- Linen could quit unexpectedly when a website stopped responding.
- With the side panel open, the page ignored the pointer.

### Removed

- Intel Macs. Linen needs a Mac with Apple silicon.
- Dropping a tab on another tab no longer makes a folder. Use New Folder, or
  the tab’s menu.

## 0.6.0

### New

- Hold Shift over a link to see a summary before opening it.
- Shift-click a link to open it in a panel over the page. Keep it as a tab,
  or press Escape to close it.
- Rename a tab: click the name of the tab you are on, or choose Rename in its
  menu.
- Drag a tab into the pinned section to pin it, and out of it to unpin it.
- Choose what a website may auto-play, and what its pop-ups do, in Website
  Settings.
- Setup offers a few extensions to add.

### Improved

- Bookmarks are now called pins.
- Each provider keeps its own Thinking setting.
- Assistant settings are now grouped by model, behavior and permissions.
- The link address at the bottom of the page says what a ⌘-click or a ⇧-click
  does.
- Extensions activate when you open a supported website.

### Fixed

- A dark website flashed white as it opened.

## 0.5.0

### New

- Extensions install from Firefox Add-ons as well as the Chrome Web Store.
- Extensions can now exchange messages with a companion app on your Mac.
- Middle-click a link to open it in a new tab.
- Point at a link to see its address at the bottom of the page.
- Settings, History and Downloads open in a tab of their own.
- Turn Automatic Picture in Picture off for one website, in **Settings >
  Websites** or in Website Settings in the toolbar.
- Minimizing the window sends a playing video to Picture in Picture, as
  leaving its tab already did.

### Improved

- Address bar suggestions favor the pages you visit most and most recently.
- History gathers a day’s repeat visits to one page into a single entry.
- Open a history entry in a new tab with a middle-click or a ⌘-click.
- Picture in Picture now works on websites that used to refuse it.
- Tracker blocking says when a page refers to no known trackers, instead of
  showing an empty list.
- The Liquid Glass window style is now called Transparent.
- Website Controls in the toolbar is now Website Settings.

### Fixed

- The toolbar took the color of the page you were opening before that page
  appeared, so it changed color twice.
- A link to a tracker domain did not open. Only the requests a page makes in
  the background are blocked.
- Turning a Safari extension off in the toolbar menu took it off the list
  instead of disabling it.
- A tab stayed marked as muted after the page unmuted itself.
- Linen did not come forward when you sent the floating video back to its tab.
- A new tab opened from a bookmarked tab landed among the bookmarked ones,
  instead of below them.
- In the release notes, the line after a list ran into the last bullet above
  it.

## 0.4.2

### Improved

- Bookmarked tabs stay at the top of the sidebar. A new tab now opens below
  them instead of pushing them down, and a line separates the two groups.
- Linen asks before you close a bookmarked tab, because the bookmark closes
  with it.
- Back to Bookmarked Page is now ⇧⌘D. macOS keeps ⌥⌘D for the Dock.
- Control-click empty space in the sidebar for New Tab, New Folder and
  Organize Tabs.
- The sidebar and the toolbar take much more color from the website you are
  reading when **Settings > Appearance > Website tint** is enabled.
- Hover highlights now adapt to the website tint for visibility on dark and
  light websites.

### Fixed

- Dragging inside the address field moved the window, so you could not select
  the address.
- The update notice stayed hidden while Settings was open.
- The top of a chat faded out even with nothing scrolled above it.
- The dots on the split view handle took the accent color on the pane you were
  using, instead of staying white.

## 0.4.1

### Improved

- History, Settings and Downloads now open in the tab you are using, like a
  normal web page.
- The assistant chat now names the website it is reading, such as “Ask about the
  GitHub page”.
- The assistant can now show tables in its answers.
- The media player title now uses the full width. Its buttons fade in over the
  end of the title when you point at the player, so the title no longer moves.
- When more than one tab is playing, a new button in the media player opens a
  list of them.
- The loading bar now runs the full width of the page.
- The selected thinking level now appears beside the Thinking heading.
- Hide Browser has gone from the View menu. ⌘H hides Linen and ⌘W closes the
  window, as in any Mac app.
- “Report a bug” is now “Send feedback”.

### Fixed

- The window disappeared from your desktop when you swiped back from a
  full-screen app, and another app came to the front.
- The assistant reading a page turned JavaScript back on in every tab, even
  with JavaScript turned off in Settings.
- Back from History closed the tab when you had opened History from the start
  page.

## 0.4.0

### New

- The side panel is now a chat with the assistant, and each tab keeps its own
  thread. Choose the provider, model and reasoning level below the message field.
- The assistant can ask for clarification. Answer it, skip
  the question, or let the assistant choose.
- Type `@` in the panel to attach another tab to your question.
- Answers arrive formatted. Copy one, hear it read aloud, ask it again, or edit
  your message and send it back.
- Thinking offers only the levels your model supports, including Minimal.
- Apple Intelligence answers stream in as they are written.
- Settings, History, Downloads, Release Notes and new tabs have addresses, so
  Back and Forward work with them.
- Suggestions on the start page are a section you can move or turn off.
- Settings > Extensions lists the Safari extensions on your Mac, and each
  profile keeps its own.
- Settings > Advanced > Feature flags lists WebKit feature flags,
  with search and a reset.
- Extensions from the Chrome Web Store update themselves once a day. Check for
  Updates in an extension’s menu checks right away, and an update that asks for
  more access waits for you.
- Your downloads stay in the list after you quit. Settings > Downloads decides
  when the list empties.

### Improved

- Switching profiles is five to eight times faster.
- Restored background tabs load only when opened, reducing startup time for
  large sessions.
- The profile switcher opens beside its button in the sidebar, and every profile
  icon is a circle.
- The downloads button is always in the sidebar, and a file you download flies
  from where you clicked it into the button.
- Settings is built from one set of rows. Nothing lights up under the pointer,
  every card shares a surface, and anything that opens a page is a row with a
  chevron rather than a button.
- A setting that is off because another setting is off tells you which one, and
  takes you there.
- Block known trackers moved to Settings > Privacy.
- Keep loaded for a website is now Keep this website awake.
- Each settings page keeps its own action, such as Reset, Remove All or Delete
  Profile, next to the button that takes you back.
- The media player fits the sidebar. Its controls appear when you point at it,
  and the title takes the room they leave.
- A side panel conversation stays out of the address field.
- Tab previews cover folders, split panes and Linen’s own pages.
- Settings pages fit a narrow window.
- Folder colors are less saturated, and folder menus use the same colors.
- The split view’s drag pill matches the sidebar and side panel pills.
- Website Settings is off on Linen’s own pages.
- Linen checks for updates in place, and again after finding one.
- Extensions tell you when WebKit cannot run them.

### Fixed

- A website could open one of Linen’s own pages by asking for a `linen:`
  address.
- Signing in to a Mac app from a website did nothing.
- Read aloud stayed silent while spoken replies were muted.
- Release notes broke wrapped lines apart.
- The window moved while you dragged a button in the toolbar.
- Space did not reach the page.
- Sidebar rows sat at different distances from the edge.
- Placeholder text jumped when a search field took focus.
- The downloads button stayed selected after you opened downloads.
- Live streams showed an unusable playback slider and lyrics button.
- The media player kept a picture from a page you had left.
- A tab could display the color of another website’s icon.
- The address bar showed nothing while it checked a connection.

## 0.3.1

### New

- Window style in Settings > Appearance sets how the toolbar and the sidebar are
  displayed. Standard uses an opaque background; Liquid Glass uses a
  translucent one. Glass transparency offers Clear to show more of the desktop
  and Tinted for stronger text and control contrast.

### Improved

- Match website color is now Website tint, and Refract tab color is now Tint
  selected tab. Both are off by default.
- Appearance now comes before Search in Settings.

### Fixed

- The pages you had open in one profile were added to another profile’s history
  when you switched profiles.
- Files you downloaded in a private tab stayed in your downloads after private
  browsing ended. A download that is still going now stops when you leave
  private browsing.
- A website’s icon could be saved in the wrong profile.
- The assistant still remembered what you asked it in the profile you left.

## 0.3.0

### New

- Linen uses Liquid Glass, with translucent backgrounds for the page, sidebar,
  side panel and Settings.
- The window uses a tint from the current website. Turn off
  Match website color in Settings > Appearance to keep Linen’s usual Light or
  Dark theme instead.
- Turn on Refract tab color in Settings > Appearance, and the selected tab takes
  on the color of that website’s icon.
- The theme picker shows you what Light, Dark and Auto look like before you
  choose.
- Linen restores open tabs when you launch the app.
- Sleep inactive tabs in Settings > General frees memory when your Mac runs low.
  It is off by default.
- The address field is now on every page, including a new tab.
- Website Settings is now a compact panel. It holds page zoom, assistant access,
  tracker blocking, and the camera, microphone, location and notification
  choices for the website you are on, and its tracker details show which known
  tracker domains Linen found on the page.

### Improved

- Type `@` in the address field to point the assistant at one of your tabs. The
  list of tabs opens as soon as you type it, with your question at the top.
- You can make the window much narrower, and websites switch to their compact
  layouts when you do.
- Tabs slide behind the top of the sidebar instead of fading away.
- The side panel shows a music note only when lyrics are available.
- The edges you drag to resize the sidebar and the side panel are easier to see.
- Settings uses lighter shadows and less prominent highlights.
- Removing an extension is now a button in a menu beside it, along with that
  extension’s own settings.

### Fixed

- Scrolling the sidebar or the side panel could reload the page behind it.
- Pointing at the side panel could highlight things on the page underneath.
- Dragging an extension button moved the whole window.
- The address field applied autocorrection to web addresses. It now preserves
  what you type.
- Tabs selected with `@` could return blank content.
- A new tab said the assistant could read it.
- Text in the toolbar was hard to read on some websites.
- An answer from the assistant appeared behind the side panel.
- A tab’s title moved when it started playing sound.
- The color of the window changed a moment after you picked a tab.
- Some dark websites left the window light, and some did not color the window
  until you reloaded them.
- ⌘← and ⌘→ went back or forward while you were editing the address field
  instead of moving through its text.
- Website Settings could be difficult to read over a busy or dark page.

## 0.2.0

### New

- Linen shows synced lyrics for the current song. Open them from the media
  player, from View > Show Lyrics, or with ⌥⌘Y. Adjust text size and timing,
  or choose a different match. Only the song and artist names leave your Mac, and
  never from a private tab. Turn this off in Settings > General.
- Activity and Lyrics now share one panel on the right. One button in the
  toolbar opens it, and the arrows widen it to fill the window.
- A button in the address field sends the video you are watching to a floating
  window. Turn on Automatic Picture in Picture in Settings > General and the
  video opens in Picture in Picture when you leave the tab and returns when
  you reopen it.
- The media player follows whichever tab is playing, so you can pause or skip
  from anywhere.
- Settings > Experiments contains features in development. They may change or
  be removed.
- Import bookmarks from another browser. Export a bookmarks file from
  Safari, Chrome, Firefox or Edge, then choose it in Settings > General.
- Save Page As… and Print Page… are in the menu you get when you right-click a
  page.
- A link that opens in its own tab now lands below the tab it came from.

### Improved

- Read aloud and Push to talk moved to Settings > Assistant, beside everything
  else about the assistant.
- Closing a tab takes you to the one below it.
- Menus mark what you chose the way the rest of the Mac does.

### Fixed

- The media player kept showing a track that had stopped.
- Settings and History slid in when they had not moved.

## 0.1.1

### New

- Settings > About lets you follow Preview builds instead of waiting for the
  next release. You can go back to Release at any time.
- Install in the update banner downloads and installs the update without a
  second confirmation.
- The notes for a new version open in a tab after it arrives. To read them
  again, choose Linen > Release Notes.
- ⌃⇥ returns you to your last tab, the way ⌘⇥ returns you to your last app. Hold
  ⌃ and press ⇥ to select the next tab, or ⇧⇥ to select the previous tab.
- Click the orb and talk. Linen sends what you said once you stop. Click the orb
  again while the assistant is working to stop it.
- In the command palette, ⌘↩ asks the assistant about what you typed, and ⇧↩
  searches in a new tab.

### Improved

- The assistant can continue long conversations that exceed its context limit.

### Fixed

- A pasted link brought its styling into the address field.
- A tab kept spinning after going back.
- The scroll wheel moved the page behind the command palette.

## 0.1.0

First release. Linen is a browser for macOS 26 and later.

### The assistant

- The assistant works in the tabs you already have open. It searches, opens
  websites, reads them, clicks, types and scrolls.
- Ask in the address field, or hold ⌥Space and speak. Click the page to stop the
  assistant and use it yourself.
- It asks you first before it buys, sends or signs in, and never fills in a
  password or a card number.

### Models

- Apple Intelligence runs on your Mac without an API key.
- Or add your own key for OpenAI, Anthropic, Gemini, DeepSeek, Groq, Mistral,
  OpenRouter or xAI.
- Or connect Linen to a local server, such as Ollama or LM Studio.

### The browser

- Tabs, folders, pinned tabs and split view.
- Profiles and private browsing.
- A command palette, history and find in page.
- Downloads that resume, and zoom you set for each website.
- Extensions from the Chrome Web Store.

### Before you start

- This is an early release. What Linen saves to disk can still change between
  versions.
- Linen opens one window at a time, and does not yet fill in passwords or show
  web notifications. See the README for limitations.
