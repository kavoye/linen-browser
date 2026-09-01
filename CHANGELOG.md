# Changelog

## 0.5.0

### New

- Extensions install from Firefox Add-ons as well as the Chrome Web Store.
- Extensions can now exchange messages with a companion app on your Mac.
- Middle-click a link to open it in a new tab.
- Point at a link to see its address at the foot of the page.
- Settings, History and Downloads open in a tab of their own.
- Turn Automatic Picture in Picture off for one website, in **Settings >
  Websites** or in Website Settings in the toolbar.
- Minimizing the window sends a playing video to Picture in Picture, as
  leaving its tab already did.

### Improved

- Address bar suggestions favour the pages you visit most and most recently.
- History gathers a day’s repeat visits to one page into a single entry.
- Open a history entry in a new tab with a middle-click or a ⌘-click.
- Picture in Picture now works on websites that used to refuse it.
- Tracker blocking says when a page refers to no known trackers, instead of
  showing an empty list.
- The Liquid Glass window style is now called Transparent.
- Website Controls in the toolbar is now Website Settings.

### Fixed

- The toolbar took the colour of the page you were opening before that page
  appeared, so it changed colour twice.
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
- The sidebar and the toolbar take much more colour from the website you are
  reading when **Settings > Appearance > Website tint** is enabled.
- Hover effect under the pointer now reads against that colour, so
  highlights stay visible on a dark website and stay gentle on a light one.

### Fixed

- Dragging inside the address field moved the window, so you could not select
  the address.
- The update notice stayed hidden while Settings was open.
- The top of a chat faded out even with nothing scrolled above it.
- The dots on the split view handle took the accent colour on the pane you were
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
- The thinking level now sits beside the Thinking heading, so the slider and
  what it is set to read as one line.
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
  thread. Choose which assistant answers, which model it uses, and how much it
  thinks, under the message you are writing.
- The assistant asks you a question when it needs one answered. Answer it, skip
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
- Settings > Advanced > Feature flags lists the WebKit switches Safari keeps to
  itself, with search and a reset.
- Extensions from the Chrome Web Store update themselves once a day. Check for
  Updates in an extension’s menu checks right away, and an update that asks for
  more access waits for you.
- Your downloads stay in the list after you quit. Settings > Downloads decides
  when the list empties.

### Improved

- Switching profiles is five to eight times faster.
- A background tab that has not been opened since Linen started now costs
  nothing until you open it, so a large session comes back sooner.
- The profile switcher opens beside its button in the sidebar, and every profile
  icon is a circle.
- The downloads button is always in the sidebar, and a file you download flies
  from where you clicked it into the button.
- Settings is built from one set of rows. Nothing lights up under the pointer,
  every card shares a surface, and anything that opens a page is a row with a
  chevron rather than a button.
- A setting that is off because another setting is off tells you which one, and
  takes you there.
- Block known trackers now lives in Settings > Privacy, beside the rest of what
  Linen keeps to itself.
- Keep loaded for a website is now Keep this website awake.
- Each settings page keeps its own action, such as Reset, Remove All or Delete
  Profile, next to the button that takes you back.
- The media player fits the sidebar. Its controls appear when you point at it,
  and the title takes the room they leave.
- A side panel conversation stays out of the address field.
- Tab previews cover folders, split panes and Linen’s own pages.
- Settings pages fit a narrow window.
- Folder colors are quieter, and a folder’s menu matches them.
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
- A live stream showed a scrubber and a lyrics button it had no use for.
- The media player kept a picture from a page you had left.
- A tab could wear the color of another website’s icon.
- The address bar showed nothing while it checked a connection.

## 0.3.1

### New

- Window style in Settings > Appearance sets how the toolbar and the sidebar are
  drawn. Standard keeps them solid, and Liquid Glass makes them clear, so the
  window takes on whatever sits behind it. With Liquid Glass, Glass transparency
  decides how far it goes. Clear shows more of your desktop, and tinted gives
  text and controls more contrast.

### Improved

- Match website color is now Website tint, and Refract tab color is now Tint
  selected tab. Both start off, so Linen keeps its own look on every website
  until you ask for the website’s color.
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

- Linen has a new look, built on Liquid Glass. The page floats on a soft,
  translucent surface, and the sidebar, the side panel and Settings share it.
- The window picks up a hint of color from the website you are on. Turn off
  Match website color in Settings > Appearance to keep Linen’s usual Light or
  Dark theme instead.
- Turn on Refract tab color in Settings > Appearance, and the selected tab takes
  on the color of that website’s icon.
- The theme picker shows you what Light, Dark and Auto look like before you
  choose.
- Linen always brings back the tabs you had open. Your tabs are how you keep
  pages, so nothing throws them away.
- Sleep inactive tabs in Settings > General frees memory when your Mac runs low.
  It starts off.
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
- The side panel shows a music note only when there are words to follow.
- The edges you drag to resize the sidebar and the side panel are easier to see.
- Settings is quieter, with lighter shadows and gentler highlights.
- Removing an extension is now a button in a menu beside it, along with that
  extension’s own settings.

### Fixed

- Scrolling the sidebar or the side panel could reload the page behind it.
- Pointing at the side panel could highlight things on the page underneath.
- Dragging an extension button moved the whole window.
- The address field corrected what you typed. A web address now arrives the way
  you typed it.
- A tab you pointed at with `@` came out blank.
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

- Linen finds the words to the song you are playing and lights each line as it
  comes. Open them from the media player, from View > Show Lyrics, or with
  ⌥⌘Y. Change the text size, nudge the timing, or pick a different match when
  the first one is wrong. Only the song and artist names leave your Mac, and
  never from a private tab. Turn this off in Settings > General.
- Activity and Lyrics now share one panel on the right. One button in the
  toolbar opens it, and the arrows widen it to fill the window.
- A button in the address field sends the video you are watching to a floating
  window. Turn on Automatic Picture in Picture in Settings > General and the
  video leaves on its own when you move away, then comes back when you return.
- The media player follows whichever tab is playing, so you can pause or skip
  from anywhere.
- Settings > Experiments holds unfinished work you can try. Anything there can
  change or disappear.
- You can bring your bookmarks from any browser. Export a bookmarks file from
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
- Install in the update banner does the whole job, and asks you once.
- The notes for a new version open in a tab after it arrives. To read them
  again, choose Linen > Release Notes.
- ⌃⇥ returns you to your last tab, the way ⌘⇥ returns you to your last app. Hold
  ⌃ to walk down the sidebar, and ⌃⇧⇥ to walk up.
- Click the orb and talk. Linen sends what you said once you stop. Click the orb
  again while the assistant is working to stop it.
- In the command palette, ⌘↩ asks the assistant about what you typed, and ⇧↩
  searches in a new tab.

### Improved

- A long conversation no longer breaks. The assistant carries on when it runs
  out of room to remember.

### Fixed

- A pasted link brought its styling into the address field.
- A tab kept spinning after going back.
- The scroll wheel moved the page behind the command palette.

## 0.1.0

First release. Linen is a browser for macOS 26 and later.

### The assistant

- The assistant works in the tabs you already have open. It searches, opens
  websites, reads them, clicks, types and scrolls.
- Ask in the address field, or hold ⌥Space and speak. Click the page to take it
  back.
- It asks you first before it buys, sends or signs in, and never fills in a
  password or a card number.

### Models

- Apple Intelligence works on your Mac out of the box.
- Or add your own key for OpenAI, Anthropic, Gemini, DeepSeek, Groq, Mistral,
  OpenRouter or xAI.
- Or point Linen at a local server, such as Ollama or LM Studio.

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
  web notifications. The README lists everything.
