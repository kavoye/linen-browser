# Browser autofill

`AutofillPage` installs one model and focus bridge in the `LinenAutofill`
isolated content world, once per content controller, in every frame. Password,
card, contact, and save clients share that model. No autofill UI is inserted into
the document and there is no page-world credential bridge.

## Form model

`AutofillFormScript` owns document, form, and field identities, semantic field
classification, section ownership, and bounded DOM/open-shadow-root discovery.
Native form ownership and `form` attributes take precedence. Unowned controls
get synthetic groups from their structure; nested component groups normalize
to consistent ownership. Standalone fields do not require a submit button.
Mutation and focus notifications invalidate cached structure. Field values are
not part of the structural cache.

The category and field kind used to offer/fill a record are also used to capture
it. `autocomplete` takes precedence over label heuristics. Login usernames are
classified with their password group, so contact filling cannot claim them.
Hidden/disabled controls cannot be filled. An explicit hidden username belonging
to a native form can supply account metadata for saving a multipage login.

## Suggestion presentation

Focus and click share a field token, so native code reuses pending lookups and
visible panels. Empty or failed lookups remain silent. DOM mutations can dismiss
a disconnected target but never open suggestions or trigger metadata lookups.
Only a visible, populated panel runs the geometry watcher; ownership, policy and
origin are still revalidated before presentation and around authenticated filling.
Typing or dismissal requires another focus/click interaction to reopen the panel.

## Submission lifecycle

`AutofillSaveScript` tracks trusted edits and separates an attempt from evidence
of completion. Submit events, Enter, and structural action controls stage an
attempt without inspecting their wording. Form disappearance covers SPA and
automatic submission. A replacement password field, a disabled form, or a
recognized verification-code step delays completion. Snapshots and attempts are
bounded and expire after two minutes.

`AutofillSubmissionTracker` retains pending candidates in the tab's memory across
navigation. It checks registered frame reports for a settled new document or a
removed login frame before requesting the native save UI. Ordinary browser
navigation, HTTP errors, genuine navigation failures, profile changes, locking,
and policy changes discard pending state. Canceled redirects can continue the
flow. Username steps are restricted to their HTTPS origin and expire after five
minutes. A native address-bar popover presents the pending offer without changing
page layout. Closing it keeps the offer available from its icon until expiry or
explicit dismissal. Only explicit Save/Update writes a candidate to the existing vaults.

Native code binds messages to WKFrameInfo origins. Filling additionally checks
the document/form/field identity, selection token, focus, geometry, and policy
before and after authentication. A new document at the same URL is still a
different document. Browser password fills reuse an authenticated context for
five minutes on the same top-level document, profile, and credential origin.
The context is cleared on policy changes, authentication failure, sleep,
screen lock, or user-session switch. Password settings own
a separate, page-scoped context that is invalidated on page dismissal, sleep,
screen lock, and user-session switch. Browser fills and save prompts never share
that context. Diagnostics contain static event names/counts only.

## Limits and validation

Completion signals are heuristics, not proof that a server accepted a password
or payment. This uses public WKWebView APIs; it does not implement Chromium's
network/renderer hooks or server predictions. Closed shadow roots and arbitrary
custom editing widgets remain unsupported. Fields belonging to different
frames are not combined. Embedded dropdown geometry currently requires a
resolvable focused frame chain; multiple unrelated nested origins can be refused.

Regression fixtures cover structural ownership, standalone fields, non-English
actions, protected fields, and fill boundaries. Use a normally signed build for
manual checks. Removing entitlements prevents validation of real Keychain access.
System authentication, the Contacts picker, and live sign-in need manual testing.

## Manual checks

Use synthetic credentials and card details on a test page.

- Save and fill a normal login, a username-first login, and a form without a
  native HTML form. Check that embedded logins match the frame's HTTPS origin.
- Submit with a button and with Enter. Failed sign-in, a replacement password
  field, or a verification-code step must not trigger a premature save offer.
- Change the page or field while authentication is open. Filling must stop when
  the original document or field no longer exists.
- Check password changes, open shadow roots, non-English labels, and separate
  shipping and billing sections. Hidden fields must not receive saved details.
- Submit prefilled test values with a real user gesture. Script-generated clicks
  alone must not authorize saving.
- Delete a saved entry and submit it again. The browser should offer to save it.
- Switch profiles and enter private browsing. Saved data must not cross profiles,
  and private browsing must not use saved autofill.
- Leave password settings, lock the screen, or switch macOS users. Returning to
  password settings must require authentication again.
