# Contributing to Linen

Keep changes focused, explain the user benefit, and leave the code easier to
test than you found it.

## Set up the project

You need macOS 26 or later, Apple silicon, and Xcode 26.5 or later.

```bash
git clone https://github.com/kavoye/linen-browser.git
cd linen-browser
xcodebuild test \
  -project Linen.xcodeproj \
  -scheme Linen \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_ENTITLEMENTS=
```

The command removes the entitlements, because the keychain access group needs
a provisioning profile. CI runs the same command. To build the app in Xcode,
set **Team** in **Signing & Capabilities** to your own Apple developer team
first. See [Building](README.md#building).

The project uses Swift 6, Swift Testing, and Main Actor isolation by default.
Do not weaken concurrency checks to make a change compile.

## Make changes

- Keep UI, state, persistence, and external-service code behind clear seams.
- Give each type one main responsibility. Split a file when it contains
  independent features or changes for unrelated reasons.
- Make each distinct SwiftUI section a separate `View` with narrow inputs.
  Computed `some View` properties do not create invalidation boundaries.
- Prefer `@Observable` models. Keep view-local `@State` private.
- Use the existing design primitives in `Linen/UI/Chrome` and
  `Linen/Settings/SettingsPrimitives.swift` before adding another style.
- Keep user-facing strings localizable. Prefer `LocalizedStringResource` in
  models and string literals in SwiftUI controls.

## Write useful comments

ASD-STE100 is not a project requirement. It is intended for controlled
technical procedures, while this repository also contains product copy and
framework terminology. Use the parts that help: common words, active voice,
short sentences, and one idea per sentence.

Add a comment when it explains:

- an invariant or a non-obvious reason;
- a security, privacy, concurrency, or performance constraint;
- a framework limitation or private API fallback;
- an interoperability format that the code must match.

Do not narrate the code, preserve edit history, or justify a design by saying
that another product does the same thing. Product names belong only where they
identify a real format, service, import source, or compatibility contract.

## Test behavior

- Add tests for new behavior and for every fixed regression.
- Assert observable outcomes, not merely that code executed.
- Cover success, failure, boundary, cancellation, and persistence paths where
  they apply.
- Prefer deterministic fakes and injected dependencies to sleeps or live
  network calls. Wait for a condition with `waitUntil`, which returns as soon as
  it holds; a fixed sleep spends its whole budget on every run and still fails
  on a slow one.
- Do not assert on a timer you cannot control. Inject the clock or the interval
  instead, as `DownloadFlights` and the extension update sweep do.
- Take a dependency the whole process shares — a stub on a static, a shared
  store — with a trait that keeps other suites out, as `.exclusiveExternalApp`
  does. Serializing one suite does not protect a global from the rest.
- Do not hide a persistent failure with `withKnownIssue`. Either make the test
  deterministic or keep the unsupported check out of the automated suite.

Run the full suite before opening a pull request. CI also measures app-target
line coverage and rejects regressions below the repository floor. CI runs
`Tools/check-format.sh`, which fails on SwiftLint violations (`brew install
swiftlint` to run it locally). The configuration is `.swiftlint.yml`. Put a
switch case’s body on the line after the label. Do not write a declaration or
control-flow body inside single-line braces; short closures, `guard … else
{ return }` and accessor lists (`{ get set }`) stay inline. Coverage is
a guardrail, not a substitute for meaningful assertions. It also checks the
blank-tab, tab-switching, command-palette, Start Page and Ask surface budgets in
`Tools/check-performance.sh`.

A case that builds a live WebKit view takes `.boundedWebViews`, which holds one
of a small number of slots — half the machine’s cores. Starting every case
together exhausts WebContent processes and turns resource pressure into
unrelated navigation failures. Put the trait on the tests that build a view, not
on the suite around them, so pure cases do not queue for a resource they never
use. Add `.serialized` as well when the cases in a suite share state.

`Linen.xctestplan` runs with per-test timeouts: 120 seconds by default, 300 at
most. A wedged test therefore fails by name instead of holding the whole run.
Both frameworks run from this plan, and a new test needs no entry in it — the
plan lists the target, not its tests.

Tests get their own support directory, so a test can create profiles, write
permissions or fill the download list without reaching the files of an installed
copy.

## Keep copy and design consistent

- Use the shortest familiar label that is unambiguous.
- Use Title Case for menu items, window titles, settings page names, and
  buttons that name a command. Use sentence case for options, captions, and
  row titles. One command keeps one capitalization on every surface of the
  same kind.
- Use US English in user-facing strings, a typographic apostrophe, and an em
  dash. Code comments stay ASCII.
- Name the feature “assistant” in copy the user reads. Use “agent” only for
  the machinery it runs on: tools, activity, the trace. Use “AI” only in
  disclosure contexts.
- Do not explain standard controls unless the consequence is unusual.
- Put consequences before implementation details in alerts and permission
  prompts.
- Support keyboard use, VoiceOver labels, reduced motion, and increased
  contrast when the surrounding component does.

## Stage the app for screenshots and video

Stage mode fills a launch with a curated session, so a screenshot or a screen
recording shows a browser someone has been using instead of an empty one.

Set the session in `Linen/Stage/StageSet.swift`: pinned tabs, folders, loose
tabs, history and downloads.

```bash
LINEN_STAGE=1 build/DD/Build/Products/Debug/Linen.app/Contents/MacOS/Linen
```

Do the warm-up pass once. The staged tabs are real websites, and a data store
with no cookies in it shows cookie banners and region prompts.

1. Launch with `LINEN_STAGE=1`.
2. Dismiss every banner on every staged tab.
3. Add a model API key in Settings if a recording needs an agent turn.
4. Quit. The answers stay in the stage data store and the next launch is clean.

A stage run writes to its own support directory, its own website data store and
its own preference domain. It cannot change the real installation’s history,
cookies, tabs or settings. Delete `$TMPDIR/linen-stage` to reset it, or set
`LINEN_STAGE_HOME` to keep more than one staged session.

## Write commit messages

Linen uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Start the subject with a type, then a colon and a summary. Write the summary in
the imperative mood. Start it with a lower-case letter. Do not put a period at
the end. Keep the subject to 72 characters or less.

Use one of these types:

- `feat`: a new capability a person can use.
- `fix`: a correction to behavior.
- `perf`: a change that makes existing behavior faster.
- `refactor`: a change that keeps behavior the same.
- `test`: a change to tests only.
- `docs`: a change to documentation only.
- `build`: a change to the Xcode project or to a package dependency.
- `ci`: a change to a workflow in `.github/workflows`.
- `chore`: a change that no other type describes.

Add a scope in parentheses when the change belongs to one area, for example
`fix(sidebar): keep the selection after a drag`. Put an exclamation mark after
the type for a change that breaks an existing setup, for example `feat!:`.

Give the reason for the change in the body:

```
ci: stop re-running tests in the release workflow

CI tests every push to main, and a tag must point at a commit on main, so
the release job ran the same suite a second time.
```

## Pull request checklist

- The app builds without new warnings.
- The full test suite passes locally.
- New behavior has meaningful tests.
- User-facing strings remain localizable.
- The change uses existing visual and interaction patterns.
- Comments explain constraints, not syntax or product comparisons.
- Each commit message follows Conventional Commits.

## License of your contribution

Linen is Apache 2.0. Section 5 of the license puts each contribution under the
same terms, unless you say otherwise in the pull request. There is no separate
agreement to sign.

Your contribution also carries a patent license to everybody who uses Linen.
That license covers only patents you own that your own contribution needs. Do
not submit code that you cannot license this way.
