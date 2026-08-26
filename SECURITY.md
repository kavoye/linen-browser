# Security

Linen keeps API keys in the macOS Keychain. An agent operates live web pages,
and the app installs extensions from the Chrome Web Store. If you find a
security defect in one of these areas, report it privately.

## Reporting a vulnerability

Use GitHub’s private vulnerability reporting on this repository
([**Security › Report a vulnerability**](https://github.com/kavoye/linen-browser/security/advisories/new)).
Do not open a public issue for a defect that a person can use to attack a
system.

You get an acknowledgment in one week or less. There is no bounty program,
because this is a small open-source project. The release notes give credit to
each person who reports a defect. If you do not want this credit, say so in
your report.

## Scope

- The assistant’s action policy. The assistant asks before it does anything
  with consequences, and refuses to fill a sensitive field
  (`Linen/Web/Privacy/SensitiveAction.swift`,
  `Linen/Web/Assistant/AgentActionPolicy.swift`).
- Installing, verifying and updating extensions
  (`Linen/Extensions/CRXVerifier.swift`,
  `Linen/Extensions/ExtensionUpdates.swift`). Linen takes an update from the
  Chrome Web Store once a day. An update that asks for access the extension
  does not already have waits for the person to accept it. A path that widens
  an extension’s access without that answer is a defect.
- Credentials (`Linen/Agent/Providers/CredentialStore.swift`). A key goes only
  in the Authorization header of the provider it belongs to.
- Download filenames (`Linen/Web/System/DownloadManager.swift`). The app does
  not run in a sandbox, so treat a filename from a server as a path until you
  have proved it safe. Linen quarantines each completed file for Gatekeeper to
  examine, and a path that skips the quarantine stamp is a defect. The list of
  finished downloads is written to disk; a private download never is.
- Certificate exceptions (`Linen/Web/Privacy/CertificateTrust.swift`). Linen
  sends every server-trust challenge to the system, and offers a way past a
  refusal only when the Privacy page permits it. An exception belongs to one host
  paired with one certificate fingerprint. The app holds it in memory only. A
  path that accepts a certificate without a prompt, that keeps an exception
  after the setting goes off, or that applies an exception to a different
  certificate on the same host, is a defect.
- Profile separation (`Linen/Profiles/Profile.swift`,
  `ProfileStore.swift`). Each profile has its own website data store,
  database, permission file and extension directory. A path that lets data
  from one profile reach another is a defect.
- Website permissions (`Linen/Web/Privacy/SitePermissions.swift`,
  `PermissionCenter.swift`, `NotificationBridge.swift`). A permission belongs to
  one origin: the scheme, the host and the port. A page that is not on TLS is
  refused without asking the person. Camera, microphone, location and
  notifications are for the main frame only, and what a page is told about its
  permission has to match what Linen stored. A path that lets a frame spend the
  permission of the page around it — or that tells a page it was granted
  something it was not — is a defect.
- The lyrics lookup (`Linen/Media/Lyrics/LyricsModel.swift`). Linen sends the
  track and artist names to lrclib.net, only while the setting is on and never
  for a private tab. A lookup from a private tab, or one made while the setting
  is off, is a defect.
