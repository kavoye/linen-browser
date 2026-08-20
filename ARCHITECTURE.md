# Architecture

Linen is a macOS SwiftUI app around WebKit. Swift 6 strict concurrency and
Main Actor default isolation are enabled for the app target.

## Runtime shape

```mermaid
flowchart LR
    App["AppDelegate"] --> Coordinator["AppCoordinator"]
    Coordinator --> Browser["BrowserModel"]
    Coordinator --> Turns["AgentTurnModel"]
    Turns --> Agent["AgentRunner"]
    Coordinator --> Input["Voice and keyboard input"]
    Browser --> Tabs["BrowserTab"]
    Tabs --> Process["TabProcessState"]
    Tabs --> WebKit["WKWebView"]
    Agent --> Toolkit["AgentToolkit"]
    Tabs --> Access["TabAssistantAccessCenter"]
    Access --> Permissions["SitePermissions"]
    Toolkit --> Access
    Access --> Driver["PageDriver"]
    Driver --> WebKit
    Browser --> Stores["Profile stores"]
    Turns --> Log["ConversationLog"]
    Stores --> Database["AppDatabase / GRDB"]
    Log --> Database
    Coordinator --> Views["SwiftUI views"]
```

`AppCoordinator` owns the running feature graph. Views observe the coordinator
and its focused models; they should not contain persistence, networking or
WebKit policy. New work should prefer a narrow model or protocol over another
coordinator responsibility.

`VoiceInputModel` owns microphone and transcription state. `AgentTurnModel`
owns one turn’s task, reply, tab activity and durable completion state. Both
models expose small observable values while their service dependencies stay
outside observation.

## Browser state

`BrowserModel` owns tab and folder order, activation, session restoration and
history integration. `BrowserTab` owns one page’s observable state and WebKit
lifecycle. `TabProcessState` owns process-protection signals, unload status and
unexpected-termination throttling. `WebViewPool` prepares reusable views
without owning tab state.

A tab may release its WebContent process under memory pressure. Its title,
address, favicon and WebKit interaction state remain so activation can rebuild
the view. Code that adds a new kind of in-progress page work must decide whether
that work prevents discarding.

Profiles are hard boundaries. Each profile has its own WebKit data store,
database, permission records and extension directory. Private browsing uses an
ephemeral profile and an in-memory database. Never add profile identity as a
column to a shared persistent store.

`BrowserModel` owns the active profile’s permission store and gives that exact
store to every new `BrowserTab`. A profile switch closes the outgoing tabs and
replaces the database and permission store together before restoring the next
session.

## Agent trust boundaries

The model is not a security boundary. Page text is untrusted, even when the
model describes it as an instruction.

- `AgentToolkit` exposes the supported browser actions.
- `TabAssistantAccessCenter` authorizes visible-page reads and controls by
  origin before `AgentToolkit` reaches the page driver.
- `PageDriver` resolves actual page elements and enforces sensitive-field and
  consequential-action rules.
- `AgentActionConsent` asks from trusted app UI. The model cannot suppress it.
- `AgentActionPolicy` stores narrow, revocable category-and-host grants.
- `ConversationLog` persists the activity trail inside the active profile.

Background research uses a non-persistent WebKit data store for each task. It
does not inherit cookies, logins or website storage from the active profile.
Loading the chosen result into a tab does not grant the assistant access to it.

Add enforcement below the model prompt. Prompts can improve behavior but cannot
authorize access, protect credentials or confirm an irreversible action.

## State and SwiftUI

Shared mutable models use Observation. View-local state is private. A distinct
screen or independently changing section should be a real `View` type with
narrow inputs; a computed `some View` property does not create an observation
boundary.

Use the components and metrics in `Linen/UI/Chrome` and
`Linen/Settings/SettingsPrimitives.swift`. `Theme` owns shared visual tokens.
User-facing strings remain localizable; protocol values, URLs, model IDs and
third-party error text remain verbatim.

## Persistence

GRDB stores structured browser and agent data. Small preferences use
`UserDefaults`; provider secrets use Keychain. File-backed models use atomic
writes through the support layer. A write needed for quit or profile teardown
must be awaited or flushed synchronously before its owner is released.

## Tests

Tests use Swift Testing. Prefer pure parsing and policy functions, injected
stores, temporary databases and local WebKit fixtures. `HTTPFixtureServer`
serves deterministic loopback pages for navigation and origin-boundary tests.
A test should assert a user-observable result or an enforced invariant. Live
services and fixed sleeps do not belong in the default suite.

CI runs the full suite with code coverage and rejects app-target coverage below
the repository floor. See [CONTRIBUTING.md](CONTRIBUTING.md) for the change
checklist.
