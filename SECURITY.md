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

- The action policy of the agent. The agent must get consent before it does an
  action that has consequences. The agent must refuse to complete a sensitive
  field (`Linen/Web/Privacy/SensitiveAction.swift`,
  `Linen/Web/Assistant/AgentActionPolicy.swift`).
- The installation and the verification of extensions
  (`Linen/Extensions/CRXVerifier.swift`).
- The handling of credentials (`Linen/Agent/Providers/CredentialStore.swift`). A key must
  go only in the Authorization header of its own provider.
- The handling of download filenames (`Linen/Web/System/DownloadManager.swift`). The
  app does not run in a sandbox. Thus treat each filename from a server as a
  path until you prove that it is safe. The app also puts each completed file
  in quarantine, so that Gatekeeper examines it. A path that avoids the
  quarantine stamp is a defect.
- The certificate exception (`Linen/Web/Privacy/CertificateTrust.swift`). The app sends
  each server-trust challenge to the system. It offers a way past a refusal
  only when the Privacy page permits it. An exception belongs to one host
  paired with one certificate fingerprint. The app holds it in memory only. A
  path that accepts a certificate without a prompt, that keeps an exception
  after the setting goes off, or that applies an exception to a different
  certificate on the same host, is a defect.
- The separation of profiles (`Linen/Profiles/Profile.swift`,
  `ProfileStore.swift`). Each profile has its own website data store,
  database, permission file and extension directory. A path that lets data
  from one profile reach another is a defect.
- The website permissions (`Linen/Web/Privacy/SitePermissions.swift`,
  `PermissionCenter.swift`). A permission belongs to one origin: the scheme,
  the host and the port. A page that is not on TLS gets a refusal, and the app
  does not ask the user. The camera, the microphone, the location and the
  notifications are for the main frame only. A path that lets a frame spend
  the permission of the page around it is a defect.
