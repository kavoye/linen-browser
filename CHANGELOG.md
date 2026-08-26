# Changelog

## 0.4.0

### New

- **Assistant** replaces Activity in the side panel: a chat, with its own thread
  for each tab. Pick which assistant answers, its model, and how much it thinks,
  under the message you are writing.
- The assistant can ask you questions. Answer it, skip a question, or let it
  choose.
- Type `@` in the panel to attach another tab to your question.
- Answers are formatted, and each one can be copied, read aloud, asked again, or
  edited and sent back.
- **Thinking** shows only the levels the chosen model supports, including
  **Minimal**.
- Apple Intelligence answers stream in as they are written.
- Settings, History, Downloads, Release Notes and new tabs have addresses, so
  Back and Forward work with them.
- Suggestions on the start page are a section you can move or turn off.
- **Settings > Extensions** lists the Safari extensions on your Mac. Each
  profile keeps its own.
- **Settings > Advanced > Feature flags** lists the WebKit switches Safari
  keeps to itself, with search and a reset.
- Extensions from the Chrome Web Store update themselves once a day, and
  **Check for Updates** in an extension’s menu checks right away. An update
  that asks for more access waits for you.

### Improved

- A side panel conversation stays out of the address field.
- Tab previews cover folders, split panes and Linen’s own pages.
- Settings pages fit a narrow window.
- Folder colors are quieter, and a folder’s menu matches them.
- The split view’s drag pill matches the sidebar and side panel pills.
- **Website Settings** is off on Linen’s own pages.
- Linen checks for updates in place, and again after finding one.
- Extensions say when WebKit cannot run them.
- Switching profiles is five to eight times faster.
- The profile switcher opens beside its button in the sidebar, and every
  profile icon is a circle.
- The downloads button is always in the sidebar, and a file you download flies
  from where you clicked into it.
- Settings is built from one set of rows: nothing lights up under the pointer,
  every card shares a surface, and anything that opens a page is a row with a
  chevron rather than a button.
- A setting that is off because another one is says so, and links to it.
- **Block known trackers** moved to **Settings > Privacy**, beside the rest of
  what Linen keeps to itself.
- **Keep loaded** for a website is now **Keep this website awake**.
- Each sub-page keeps its own action — Reset, Remove All, Delete Profile —
  next to the button that goes back.
- The media player fits the sidebar, its controls appear when you point at it,
  and the title takes the room they leave.

### Fixed

- A website could open one of Linen’s own pages by asking for a `linen:`
  address.
- Signing in to a Mac app from a website did nothing.
- **Read aloud** stayed silent while spoken replies were muted.
- Release notes broke wrapped lines apart.
- The window moved while you dragged a button in the toolbar.
- Space did not reach the page.
- Sidebar rows sat at different distances from the edge.
- Placeholder text jumped when a search field took focus.
- The downloads button stayed selected after you opened downloads.
- A live stream showed a scrubber and a lyrics button it had no use for.
- The media player kept a picture from a page you had left.

## 0.3.1

### New

- **Window style** in **Settings > Appearance** sets how the toolbar and the
  sidebar are drawn. Standard keeps them solid. Liquid Glass makes them clear,
  so the window takes on whatever sits behind it. When you choose Liquid Glass,
  **Glass transparency** decides how far it goes: clear shows more of your
  desktop, tinted gives text and controls more contrast.

### Improved

- **Match website color** is now **Website tint**, and **Refract tab color** is
  now **Tint selected tab**. Both are off to begin with, so Linen keeps its own
  look on every website until you ask for the website’s color.
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
  translucent surface, and the sidebar, the side panel, and Settings share it.
- The window picks up a hint of color from the site you are on. Turn off
  **Match website color** in **Settings > Appearance** to keep Linen's usual
  Light or Dark theme instead.
- Turn on **Refract tab color** in **Settings > Appearance**, and the selected
  tab takes on the color of that site's icon.
- The theme picker shows you what Light, Dark, and Auto look like before you
  choose.
- Linen always brings back the tabs you had open. Your tabs are how you keep
  pages, so nothing throws them away.
- **Sleep inactive tabs** in **Settings > General** lets Linen free up memory
  when your Mac runs low. It is off to begin with.
- The address field is now on every page, including a new tab.
- **Website Settings** is now a compact panel with page zoom, assistant access,
  tracker blocking, and camera, microphone, location, and notification choices
  for the site you are on. Its tracker details show which known tracker domains
  Linen found on the page.

### Improved

- Type `@` in the address field to point the assistant at one of your tabs. The
  list of tabs opens as soon as you type it, with your question at the top.
- You can make the window much narrower. Sites switch to their compact layouts
  when you do.
- Tabs slide behind the top of the sidebar instead of fading away.
- The side panel shows a music note only when there are words to follow.
- The edges you drag to resize the sidebar and the side panel are easier to see.
- Settings is quieter, with lighter shadows and gentler highlights.
- Removing an extension is now a button in a menu beside it, along with that
  extension's own settings.

### Fixed

- Scrolling the sidebar or the side panel could reload the page behind it.
- Pointing at the side panel could highlight things on the page underneath.
- Dragging an extension button moved the whole window.
- The address field corrected what you typed. A web address now arrives the way
  you typed it.
- A tab you pointed at with `@` came out blank.
- A new tab said the assistant could read it.
- Text in the toolbar was hard to read on some sites.
- An answer from the assistant appeared behind the side panel.
- A tab's title moved when it started playing sound.
- The color of the window changed a moment after you picked a tab.
- Some dark sites left the window light, and some sites did not color the
  window until you reloaded them.
- ⌘← and ⌘→ went back or forward while you were editing the address field
  instead of moving through its text.
- Website Settings could be difficult to read over a busy or dark page.

## 0.2.0

### New

- Linen finds the words to the song you are playing and lights each line as it
  comes. Open them from the media player, from **View > Show Lyrics**, or with
  ⌥⌘Y. Change the text size, nudge the timing, or pick a different match when
  the first one is wrong. Only the song and artist names leave your Mac, and
  never from a private tab. To turn this off, go to **Settings > General**.
- Activity and Lyrics now share one panel on the right. One button in the
  toolbar opens it, and the arrows widen it to fill the window.
- A button in the address field sends the video you are watching to a floating
  window. Turn on **Automatic Picture in Picture** in **Settings > General**
  and it leaves on its own when you move away, then comes back when you return.
- The media player follows whichever tab is playing, so you can pause or skip
  from anywhere.
- **Settings > Experiments** holds unfinished work you can try. Anything there
  can change or disappear.
- You can bring your bookmarks from any browser. Export a bookmarks file from
  Safari, Chrome, Firefox, or Edge, then choose it in **Settings > General**.
- **Save Page As…** and **Print Page…** are in the menu you get when you
  right-click a page.
- A link that opens in its own tab now lands below the tab it came from.

### Improved

- **Read aloud** and **Push to talk** moved to **Settings > Assistant**, beside
  everything else about the assistant.
- Closing a tab takes you to the one below it.
- Menus mark what you chose the way the rest of the Mac does.

### Fixed

- The media player kept showing a track that had stopped.
- Settings and History slid in when they had not moved.

## 0.1.1

### New

- **Settings > About** lets you follow Preview builds instead of waiting for the
  next release. You can go back to Release at any time.
- **Install** in the update banner does the whole job, and asks you once.
- The notes for a new version open in a tab after it arrives. To read them again,
  choose **Linen > Release Notes**.
- ⌃⇥ returns you to your last tab, the way ⌘⇥ returns you to your last app. Hold
  ⌃ to walk down the sidebar, and ⌃⇧⇥ to walk up.
- Click the orb and talk. Linen sends what you said once you stop. Click it again
  while the assistant is working to stop it.
- In the command palette, ⌘↩ asks the assistant about what you typed, and ⇧↩
  searches in a new tab.

### Improved

- A long conversation no longer breaks. The assistant carries on when it runs out
  of room to remember.

### Fixed

- A pasted link brought its styling into the address field.
- A tab kept spinning after going back.
- The scroll wheel moved the page behind the command palette.

## 0.1.0

First release. Linen is a browser for macOS 26 and later.

### The assistant

- The assistant works in the tabs you already have open. It searches, opens
  sites, reads them, clicks, types, and scrolls.
- Ask in the address field, or hold ⌥Space and speak. Click the page to take it
  back.
- It asks you first before it buys, sends, or signs in, and never fills in a
  password or a card number.

### Models

- Apple Intelligence works on your Mac out of the box.
- Or add your own key for OpenAI, Anthropic, Gemini, DeepSeek, Groq, Mistral,
  OpenRouter, or xAI.
- Or point Linen at a local server, such as Ollama or LM Studio.

### The browser

- Tabs, folders, pinned tabs, and split view.
- Profiles and private browsing.
- A command palette, history, and find in page.
- Downloads that resume, and zoom you set for each site.
- Extensions from the Chrome Web Store.

### Before you start

- This is an early release. What Linen saves to disk can still change between
  versions.
- Linen opens one window at a time, and does not yet fill in passwords or show
  web notifications. The README lists everything.
