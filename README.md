<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/mark-white.svg">
  <img src=".github/assets/mark-black.svg" alt="Linen" width="104" height="104">
</picture>

# Linen

**An agentic browser for macOS.**

Ask for the result instead of the page. Linen opens websites, reads them, clicks,
types and scrolls, in the tabs you already have open. Click the page at any time
and it is yours again.

<a href="#what-it-does">What it does</a> ·
<a href="#install">Install</a> ·
<a href="#building">Building</a> ·
<a href="CONTRIBUTING.md">Contributing</a> ·
<a href="ARCHITECTURE.md">Architecture</a> ·
<a href="#known-limitations">Limitations</a> ·
<a href="SECURITY.md">Security</a> ·
<a href="RELEASING.md">Releasing</a>

<a href="https://github.com/kavoye/linen-browser/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/kavoye/linen-browser/ci.yml?branch=main&style=flat-square&label=CI" alt="CI status"></a>
<img src="https://img.shields.io/badge/macOS-26%2B-1c1c1e?style=flat-square" alt="macOS 26 or later">
<img src="https://img.shields.io/badge/universal-Apple%20silicon%20%2B%20Intel-1c1c1e?style=flat-square" alt="Universal binary">
<img src="https://img.shields.io/badge/license-Apache%202.0-1c1c1e?style=flat-square" alt="Apache 2.0 license">

https://github.com/user-attachments/assets/a4a28bdd-6751-4f02-84a5-f0f7fbb87153

Linen showing the sidebar with pinned tabs and a Reading folder, a video playing
in the media dock, and the assistant reading a page to answer a question.

</div>

## What it does

**Ask, and it does the work.** The assistant searches, opens websites, reads
them, clicks, types, scrolls, picks from menus, and opens and closes its own
tabs. A focus ring marks what it is about to touch, before it touches it. The
page it researches on its own stays visible while it works.

**It works where you already are.** Ask in the address field. Your open tabs are
the context. Type `@` to point at one, and the assistant reads that page instead
of starting from a search. The Agent Activity column keeps every step it took,
so the work is yours to check.

**You decide what it can reach.** Research, the page, tabs and media are
separate tools. Each one turns on and off in Settings › Assistant.

**It stops before the things that matter.** Every website is Ask, Read Only,
Allow Control or No Access. The assistant asks you first before it buys, sends
or signs in. It never fills in a password or a card number.

**Your model. Your key.** Apple Intelligence runs on your Mac out of the box.
Add a key for OpenAI, Anthropic, Gemini, DeepSeek, Groq, Mistral, OpenRouter or
xAI, or point Linen at a local server such as Ollama or LM Studio. Keys live in
the macOS Keychain, and each one goes only to the provider it belongs to.

**It fits the model you chose.** Linen measures your model’s context window and
sizes the work to it. A small local model gets a short brief and the core tools.
A large one gets all of them.

**Talk to it.** Hold ⌥Space and speak. Release the key to send. Pick a different
key in Settings › Assistant. Your speech is transcribed on your Mac and goes
nowhere else.

**Still a browser.** Tabs, folders you can drag pages into, pinned pages, split
view, private browsing, a command palette, history, find in page, zoom for each
website, and a media player that follows whatever is playing. Downloads resume,
and the list stays until you empty it. Extensions come from the Chrome Web
Store, update themselves once a day, and include full content blockers such as
[uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home).

**Trackers blocked from the start.** Well-known advertising, analytics and
session-recording networks are blocked when a page loads them from another
website. It is a baseline rather than a full content blocker. Switch it off for
one website in Site Settings, or for every website in Settings › Privacy.

**Profiles keep work and personal apart.** Each one has its own cookies,
history, tabs, website permissions and extensions. Signing in under one profile
does not sign you in under another, and your existing browsing stays where it is
as the first profile.

**Private browsing writes nothing down.** No history, no tabs, no transcript.
⇧⌘N switches into it, and leaving discards the session and brings your tabs
back.

**Tabs give memory back.** When memory runs short, a background tab releases its
own and reloads where you left off when you return. A window left open all day
no longer holds every page in memory.

**Permissions in one place.** Location, camera, microphone and notifications are
asked for in the address bar. Allow once, allow always, or deny. What you chose
stays in Settings › Websites, beside each website’s assistant access.

**Updates arrive in place.** [Sparkle](https://sparkle-project.org) brings them,
with the appcast published on GitHub Releases. See [RELEASING.md](RELEASING.md).

## Install

1. Download `Linen-<version>.dmg` from the
   [latest release](https://github.com/kavoye/linen-browser/releases/latest).
   The zip file beside it is for the updater.
2. Open the disk image, then drag Linen to the Applications folder.

Linen checks for updates on its own, and a banner asks you before it downloads
one.

## Requirements

- macOS 26 or later
- A Mac with Apple silicon, or an Intel Mac that runs macOS 26
- Xcode 26.5 or later, to build the app from source

The app is a universal binary. An Intel Mac runs the browser, but voice input
and Apple Intelligence need Apple silicon. On an Intel Mac, add a provider key
to use the assistant.

## Building

```bash
git clone https://github.com/kavoye/linen-browser.git
cd linen-browser
open Linen.xcodeproj
```

Then set up signing:

1. Select the `Linen` target. Open **Signing & Capabilities**.
2. Set **Team** to your own Apple developer team. The project holds the
   maintainer’s team. Xcode cannot sign for a team that you are not a member
   of.
3. Build and run the `Linen` scheme. Swift Package Manager downloads the
   dependencies at the first build.

The app declares entitlements for the microphone, the camera, location, and
the keychain. Each one needs a signed build. To run the tests without a
signing certificate, remove the entitlements:

```bash
xcodebuild test -project Linen.xcodeproj -scheme Linen \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_ENTITLEMENTS=
```

A build without entitlements cannot store an API key in the keychain. Use a
signed build to test the assistant.

## Known limitations

**No password autofill, no passkeys.** macOS does not offer Password AutoFill
to other browsers, and passkeys work only for websites tied to an app. Use a
password manager extension everywhere else.

**Bookmarks are tabs.** There is no separate bookmarks manager. Pinned pages
and folders do that job. To bring bookmarks in, export them to an HTML file
from the other browser. Then choose that file in Settings › General. Safari,
Chrome, Firefox and Edge all write this file. The bookmarks become one folder
in the sidebar. History does not come across.

**One window.** `window.open` and `target="_blank"` open as tabs.

**No web push.** Website notifications work while Linen is open. Websites
cannot send notifications after you quit.

**No voice on Intel.** Apple ships the on-device speech and model frameworks
only for Apple silicon. The browser runs on an Intel Mac. Add a provider key
to use the assistant there.

## Project layout

| Folder | Contents |
| --- | --- |
| `Linen/App` | The entry point, the app delegate, and the coordinator that connects the components |
| `Linen/Agent` | The agent loop, the tool declarations, the providers, and the Keychain credential store |
| `Linen/Web` | Tabs, navigation, history, downloads, privacy, and the page driver that the agent uses |
| `Linen/UI` | The browser interface: the sidebar, the content area, and the panels |
| `Linen/Settings` | The settings model and the settings pages |
| `Linen/Profiles` | The profile list and where each profile keeps its files |
| `Linen/Voice` | Microphone capture, transcription, and speech output |
| `Linen/Media` | The docked media player and the lyrics view |
| `Linen/Extensions` | Installation, verification, and consent for web extensions |
| `Linen/Updates` | The Sparkle integration and the update banner |
| `Linen/Onboarding` | The first-run screens |
| `Linen/Support` | The database, file stores, and shared utilities |
| `Linen/Stage` | A curated session for screenshots, in debug builds only |

## Security

The assistant drives real pages, the app holds your API keys, and extensions
come from the Chrome Web Store. If you find a security defect in any of that,
report it privately. Use **Security › Report a vulnerability** on this repo.
That thread is private between you and the maintainers. Do not open a public
issue for something an attacker could use. You get an answer within a week, and
credit in the release notes unless you ask for your name to be left out.
[SECURITY.md](SECURITY.md) has the details, including which parts of the app
are worth attacking.

## AI transparency

Linen answers with an AI system. EU AI Act Article 50 applies from 2 August
2026. The open-source exemption in Article 2(12) does not cover Article 50, so
these obligations apply to this app.

Linen tells you that you deal with a machine in four places:

1. The first-run model screen says that replies come from AI.
2. The address field marks every assistant reply with an `AI` badge.
3. The Agent Activity column keeps a caption under the model name.
4. The voice output says it before the first spoken reply of each launch.

The assistant can type text into a page. Before it clicks a control that posts
or sends, Linen asks you to confirm. When the assistant wrote the text in that
form, the dialog says so. You stay the publisher, so the disclosure and the
decision are both yours.

Linen does not watermark generated text. The model provider marks its own
output, and short text is out of scope of the marking obligation.

## Acknowledgements

Linen ships these open source packages. Their full license texts are in the
app, under Settings › About.

- [Sparkle](https://github.com/sparkle-project/Sparkle), for updates.
- [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel), for the
  model providers, with [EventSource](https://github.com/mattt/EventSource),
  [JSONSchema](https://github.com/mattt/JSONSchema) and
  [PartialJSONDecoder](https://github.com/mattt/PartialJSONDecoder).
- Apple’s [swift-atomics](https://github.com/apple/swift-atomics),
  [swift-collections](https://github.com/apple/swift-collections),
  [swift-nio](https://github.com/apple/swift-nio),
  [swift-syntax](https://github.com/swiftlang/swift-syntax) and
  [swift-system](https://github.com/apple/swift-system).

`Linen/Support/Acknowledgements.json` is committed, and the app reads it at
runtime. `Tools/make-acknowledgements.swift` writes it from three inputs:
`Package.resolved` for the names and versions, the resolved checkouts for each
license text, and `Tools/vendored` for code copied in rather than linked. Run
the script after you add or update a package, then commit the result. CI runs
the same script and fails if the output differs.

## License

Apache 2.0, see [LICENSE](LICENSE). The license includes a patent grant
from every contributor. Provider logos belong to their owners.
