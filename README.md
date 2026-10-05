<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/mark-white.svg">
  <img src=".github/assets/mark-black.svg" alt="Linen" width="104" height="104">
</picture>

# Linen

A macOS browser with a built-in assistant.

Ask the assistant to search, read websites, and use the tabs you have open.
It can click, type, and scroll. Click the page to stop the assistant and
continue browsing yourself.

<a href="#install">Install</a> ·
<a href="#what-it-does">Features</a> ·
<a href="#building">Build</a> ·
<a href="CONTRIBUTING.md">Contribute</a>

<a href="https://github.com/kavoye/linen-browser/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/kavoye/linen-browser/ci.yml?branch=main&style=flat-square&label=CI" alt="CI status"></a>
<img src="https://img.shields.io/badge/macOS-26%2B-1c1c1e?style=flat-square" alt="macOS 26 or later">
<img src="https://img.shields.io/badge/Apple%20silicon-1c1c1e?style=flat-square" alt="Apple silicon">
<img src="https://img.shields.io/badge/license-Apache%202.0-1c1c1e?style=flat-square" alt="Apache 2.0 license">

![Linen browser screenshot](https://github.com/user-attachments/assets/9ccadd3b-9090-46a1-8ad7-f17d648a60c1)

</div>

## Install

Requires **macOS 26 or later** and **Apple silicon**.

Download the disk image from the [latest release](https://github.com/kavoye/linen-browser/releases/latest),
open it, and drag Linen to Applications. The app checks for updates automatically
and asks before downloading.

This README describes the current source. See the [release notes](CHANGELOG.md)
for changes in published versions.

## What it does

- Browse in separate windows with tabs, folders, pins, and split view. Move tabs
  between windows and restore your windows after relaunch. Search your history
  and resume downloads. Play media in Picture in Picture and view synced lyrics.
- Import bookmarks from another browser's HTML export in Settings › General.
- Choose Open Link in New Window from a link's context menu. Hold Option to open
  it in a new private window. These actions are also available for history and
  frequent sites.
- Type a request to the assistant in the address field or hold ⌥Space to speak.
  Use `@` to include a tab. You can also attach files and review the assistant's
  actions in Agent Activity.
- Hold Shift while hovering over a link to read a summary, or Shift-click to
  preview the page.
- Save passwords, payment cards, and contact details in Settings › Autofill.
  Unlock saved passwords and cards with Touch ID or your Mac password.
  To sign in with a passkey, follow the macOS sign-in prompt.
- Install extensions from the Chrome Web Store or Firefox Add-ons.
- Use profiles to keep cookies, history, tabs, permissions, and extensions
  separate. Press ⇧⌘N to open a private window. Closing it ends that private session.

### Choose a model

Use Apple Intelligence on your Mac, add a provider API key, or connect to a local
server such as Ollama or LM Studio. Supported providers include OpenAI,
Anthropic, Gemini, DeepSeek, Groq, Mistral, OpenRouter, and xAI.

External assistants can access only the tabs you share through Linen's
[MCP server](MCP.md).

## Privacy and control

- Set the assistant's access for each website and enable its tools in
  Settings › Assistant. The assistant asks before making purchases, sending
  information, or signing in. It cannot fill passwords or card numbers.
  You can fill these with browser autofill.
- API keys stay in Keychain and are sent only to their provider. Submitted
  messages, shared page content, and attachments go to the selected model.
- On-device voice converts speech to text on your Mac. OpenAI dictation and voice
  conversations send microphone audio to OpenAI.
- Private browsing does not save history, tabs, or assistant transcripts.
- Linen blocks known third-party trackers by default. Extensions can block
  additional trackers.

The assistant uses AI and can make mistakes. Check important information.
Report vulnerabilities privately through [Security](SECURITY.md).

## Building

Requires **Xcode 26.5 or later**.

```bash
git clone https://github.com/kavoye/linen-browser.git
cd linen-browser
open Linen.xcodeproj
```

Select the `Linen` target, set your team in **Signing & Capabilities**, then build
and run the `Linen` scheme. Dependencies resolve automatically.

If your team lacks the passkey entitlement, remove this entry from
`Linen/Linen.entitlements`. Passkeys will be unavailable in that build.

```xml
<key>com.apple.developer.web-browser.public-key-credential</key>
<true/>
```

Use a signed build for Keychain access. See [Contributing](CONTRIBUTING.md) for
test commands and development guidelines, [Architecture](ARCHITECTURE.md) for the
code structure, and [Releasing](RELEASING.md) for distribution.

## License and acknowledgements

Linen is licensed under [Apache 2.0](LICENSE). Provider logos belong to their owners.

Linen uses [Sparkle](https://github.com/sparkle-project/Sparkle),
[AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel), and other
open source packages. Full credits and license texts are in **Settings › About**
and [Acknowledgements.json](Linen/Support/Acknowledgements.json).
