# Releasing Linen

Linen uses [Sparkle 2.9.6](https://sparkle-project.org) for updates. The app
does not show the Sparkle windows. The update interface is only the banner in
`Linen/Updates/UpdateBanner.swift`.

Two files contain the hosting configuration. The values in these two files must
agree:

- `Linen/Updates/UpdateFeed.swift` — the `owner` and `repository` values
- `Linen/Info.plist` — the `SUFeedURL` value

The feed URL is
`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`.
GitHub redirects that URL to the asset of the same name in the most recent
release, so you need no web server and no `gh-pages` branch. Attach
`appcast.xml` to each release, and the permalink follows it.

## The signing tools

Sparkle ships `generate_keys`, `sign_update` and `generate_appcast` in an
artifact bundle rather than as package products, so Swift Package Manager
downloads them without building them. Point a variable at them once, and you do
not have to find the path again:

```bash
export SPARKLE_BIN=$(dirname "$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts/sparkle/Sparkle/bin/sign_update' -print -quit)")
```

The path lives in DerivedData, so cleaning the build folder removes it and the
next build puts it back. You can also download the release tarball from
https://github.com/sparkle-project/Sparkle/releases.

## One-time: the Sparkle signing keys

The EdDSA key pair already exists. `Linen/Info.plist` holds the public key as
`SUPublicEDKey`, and this Mac’s login keychain holds the private key, where
`sign_update` finds it. Nothing else needs configuring.

Back up the private key and keep the backup for at least two years. If you lose
it, no installed copy can ever update again, and the only way out is to ask
everyone to download the app afresh.

To export a copy:

```bash
"$SPARKLE_BIN/generate_keys" -x sparkle-private-key.txt
```

This file has the same importance as a password. It gives full authority to
release updates. Put the file in a password manager. Then delete the file.

`generate_keys -p` shows the public key again at any time. If you run
`generate_keys` with no arguments, it keeps the existing key pair. It does not
make a new key pair.

## One-time: the Developer ID certificate

The workflow signs the app with a Developer ID Application certificate. Only the
Account Holder of the team can make this certificate. A Developer ID certificate
is valid for five years.

1. Open Xcode › Settings › Accounts.
2. Select your Apple ID, then the team.
3. Select Manage Certificates.
4. Select the add button, then Developer ID Application.
5. Run `security find-identity -v -p codesigning`. The output must contain
   `Developer ID Application`.

Then export the certificate for the workflow:

1. Open Keychain Access › login › My Certificates.
2. Select the Developer ID Application certificate. A private key must show
   below it. The Certificates category gives a file with no key, and the
   workflow then finds no signing identity.
3. Select File › Export Items. Save a `.p12` file. Set a password.
4. Put the file in the `DEVELOPER_ID_CERTIFICATE_P12` secret below.
5. Put the password in the `DEVELOPER_ID_CERTIFICATE_PASSWORD` secret.
6. Put a copy of the file and the password in a password manager. Then delete
   the file from the disk.

The portal permits a small number of these certificates. If the portal shows a
certificate that this Mac does not have, the private key is on a different Mac.
Export the key from that Mac, or revoke the certificate and make a new one. A
revoked certificate does not stop a release that is already public. The workflow
signs with `--timestamp`.

## One-time: the provisioning profile

`Linen.entitlements` declares two restricted entitlements. The app stores API
keys in the data-protection keychain. That keychain refuses an item from code
that has no keychain access group, so the file declares `keychain-access-groups`.
The app also lets a website use a passkey, so the file declares
`com.apple.developer.web-browser.public-key-credential`. A Developer ID
signature can only carry a restricted entitlement when an embedded profile
authorizes it. Gatekeeper refuses to launch an app that declares an entitlement
without the profile.

Once, in the Apple Developer portal:

1. Open Certificates, Identifiers & Profiles › Identifiers.
2. Select the `com.kavoye.Linen` App ID, or register it.
3. Enable the Web Browser Public Key Credential Requests capability. Apple
   assigns this capability to the account. You must also enable it on the
   App ID.
4. Open Profiles. Add a profile.
5. Select the Developer ID type, under Distribution.
6. Select the `com.kavoye.Linen` App ID and your Developer ID Application
   certificate.
7. Give the profile a name, for example `Linen Developer ID`. Do not use the
   characters `&`, `<` or `>`. The export step puts the name in a plist.
8. Download the profile as `Linen.provisionprofile`.
9. Run this command. The output must contain `keychain-access-groups` and
   `com.apple.developer.web-browser.public-key-credential`:

   ```bash
   security cms -D -i Linen.provisionprofile | plutil -extract Entitlements xml1 -o - -
   ```

10. Put the profile in the `DEVELOPER_ID_PROVISIONING_PROFILE` secret below.

The App ID prefix gives the access group. The portal has no Keychain Sharing
capability. That switch is in Xcode, and it only writes the entitlements file.
The passkey capability is the opposite. Only the portal can enable it. A build
fails at the provisioning step until you do.

Make the profile again when it expires, and when you add a restricted
entitlement. The release then fails at the Install provisioning profile step,
and at the checks after the export.

## One-time: who can release

A tag starts the release. Only an account with write access can push a tag, but
the workflow gives that tag a Developer ID certificate, a notarization key and
the Sparkle private key. The Sparkle key is the most important of the three: it
decides what every installed copy of Linen updates to. Set up all three
controls below before you make the repository public.

**1. The release environment.** The workflow jobs declare
`environment: release`, and the secrets live in that environment. Only a job
that runs from an approved ref can read them.

1. Open Settings › Environments. Add an environment. Name it `release`.
2. Find Deployment branches and tags. Select Selected branches and tags.
3. Select Add deployment branch or tag rule. Set the ref type to Tag. Enter
   the pattern `v*`.
4. Select Add deployment branch or tag rule again. Set the ref type to
   **Branch**. Enter `main`.
5. Make sure the list reads "1 branch and 1 tag allowed". A release comes from
   the tag. A preview build comes from the branch, because `workflow_run` runs
   from `main` and not from a tag. With no branch in the list, each preview
   build fails when it asks for the certificate.
6. Add the seven secrets from the next section as environment secrets.

Do not add a required reviewer. A reviewer stops the release until you come
back and approve it, and stops each preview build the same way. The tag ruleset
below controls who can start a release.

**2. A tag ruleset.** This stops the tag from being made at all.

1. Open Settings › Rules › Rulesets. Add a new tag ruleset.
2. Set Enforcement status to Active.
3. Under Target tags, add the pattern `v*`.
4. Select Restrict creations, Restrict updates and Restrict deletions.
5. Leave the bypass list empty, then add only yourself.

**3. A branch ruleset for `main`.** The release only builds a commit that is on
`main`, so `main` is what an attacker must reach.

1. Add a branch ruleset that targets the default branch.
2. Select Require a pull request before merging. Require one approval.
3. Select Require status checks to pass. Add the CI check.
4. Select Block force pushes. Select Restrict deletions.

The workflow refuses a tag that points at a commit that is not on `main`, but a
ruleset is what stops the commit getting to `main`.

## One-time: the release secrets

`.github/workflows/release.yml` needs seven secrets. Add them to the `release`
environment, in Settings › Environments › release › Environment secrets. Do not
add them in Settings › Secrets and variables › Actions: a repository secret is
available to every workflow run, with no approval:

| Secret | Description |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | The `.p12` file from the certificate section above. Run `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password that you set on the `.p12` file |
| `DEVELOPER_ID_PROVISIONING_PROFILE` | The Developer ID profile from the section above. Run `base64 -i Linen.provisionprofile \| pbcopy` |
| `AC_API_KEY_P8` | The full contents of the App Store Connect API key `.p8` file. Include the `BEGIN` and `END` lines |
| `AC_API_KEY_ID` | The ID of the key. This is the `ABCD1234EF` part of `AuthKey_ABCD1234EF.p8` |
| `AC_API_ISSUER_ID` | The issuer UUID. App Store Connect shows it above the list of keys |
| `SPARKLE_PRIVATE_KEY` | The EdDSA private key, from `generate_keys -x` |

Make the App Store Connect API key in Users and Access › Integrations › App
Store Connect API. Give the key the Developer role. App Store Connect downloads
the `.p8` file one time only. `notarytool` uses this key to authenticate. An app-specific
password also works, but you can revoke the API key on its own,
and the API key does not give access to all of your Apple ID.

The team ID is not a secret. The workflow already contains it.

## Each release

The release does not run the tests. CI tests each push to `main`, and the
workflow reads the result. Push the tag:

```bash
git tag v1.1 && git push origin v1.1
```

Push the tag as soon as the commit is on `main`. You do not have to wait for
CI, because the `gate` job waits for you. From there the workflow:

1. Confirms the tag is on `main`.
2. Waits for the CI run on that commit, and stops if it fails.
3. Builds an archive.
4. Signs the app with the Developer ID certificate and the profile.
5. Sends the app to Apple for notarization.
6. Staples the notarization ticket to the app.
7. Builds a zip file.
8. Builds a disk image holding the app and a link to the Applications folder.
9. Signs the disk image.
10. Sends the disk image to Apple for notarization.
11. Staples the notarization ticket to the disk image.
12. Signs the app for Sparkle.
13. Writes `appcast.xml`.
14. Publishes the GitHub release with the three assets.

The workflow takes 20 to 40 minutes, plus the time that CI still needs. The
Apple notary service uses most of this time, and the workflow waits for it two
times.

If CI fails on that commit, the `gate` job stops the release. No signing key is
used. Correct the code, push it, then make the next tag. Do not move a tag that
you already pushed.

Important information:

- **Each asset has one job.** A person downloads the disk image. Sparkle
  downloads the zip file. `appcast.xml` points only at the zip file. Keep the
  disk image out of the `dist` folder. `generate_appcast` reads a disk image
  also, and then the feed contains two items for one version.
- **The app asks to move itself.** A copy that runs from another folder cannot
  always update itself, so Linen offers to move itself to the Applications
  folder at the first launch. `Linen/App/InstallLocation.swift` makes that
  decision. Linen asks one time only. The disk image is what makes the correct
  installation obvious, so keep the link to the Applications folder in it.
- **The tag sets the version.** `MARKETING_VERSION` comes from the tag without
  the `v` character. `CURRENT_PROJECT_VERSION` comes from `git rev-list --count
  HEAD`, the number of commits, so the `CFBundleVersion` that Sparkle compares
  always increases, in both channels. Do not use the number of the
  workflow run: that counter restarts if the workflow file is replaced, and a
  build number that goes down stops every installed copy from updating. Do not
  change a version by hand in the Xcode project. The values in the Xcode project
  apply only to local builds.
- **The release body supplies the “What’s New” sheet.** The workflow makes the
  body from two parts. `CHANGELOG.md` is optional: make it only when a release
  needs notes of its own. If it contains a `## 1.1` section, that section comes
  first. GitHub then adds the list of the commits and the pull
  requests after the previous tag, and a New Contributors section, so every
  contributor gets credit with or without a changelog. The app reads the body
  from the API each time it shows the sheet, so you can edit a release later to
  correct the text without publishing a new one.
- **Give credit to a security reporter by hand.** [SECURITY.md](SECURITY.md)
  promises the reporter credit in the release notes. The workflow cannot know
  the name. Put the name in the `CHANGELOG.md` section before you make the tag.
  Do not use the name if the reporter asked you to keep it out.
- **The format of the tag is important.** The notes sheet finds the release with
  the name `v<version>`. If it does not find that name, it uses `<version>`.
  Only the formats `vX.Y` and `vX.Y.Z` start the workflow.
- **The workflow writes `appcast.xml` from the app bundle**, so the version,
  the minimum system version and the architectures in the feed always match the
  app. The feed contains only the most recent release. This is sufficient
  for Sparkle to offer the update to all users.

### Acknowledgements

The app shows the license of each open source package in Settings › About. The
list comes from `Linen/Support/Acknowledgements.json`. A script makes this file
from `Package.resolved` and the resolved checkouts:

```bash
swift Tools/make-acknowledgements.swift
```

After you add, remove or update a package:

1. Resolve the packages one time, or build the app.
2. Run the command above.
3. Commit the file with the change to `Package.resolved`.

CI runs the same command and stops the build if the result is different. The
MIT and Apache both require their terms to travel with the binary, and a signed
build is a redistribution, so this file is not optional.

### The disk image

The disk image window comes from two files in `Tools/dmg`: `background.tiff`
and `DS_Store`. The workflow copies both into the staging folder. Only Finder
writes a `.DS_Store`, and the runner has no Finder session, so the layout is
made once on a Mac.

After you change the artwork or the icon positions:

1. Run this command on a Mac:

   ```bash
   sh Tools/make-dmg-layout.sh
   ```

2. Open the disk image from a release build. Look at the window.
3. Commit the two files in `Tools/dmg`.

The volume name must stay `Linen`. The background is an alias that names the
volume.

macOS 26 Finder ignores the window size in the file. The window opens at the
size that Finder gives to each new window. The artwork is thus 1280x800: paper
stays below the window at each size, and the composition stays at the top left.
A Finder icon position is the centre of the icon, so the positions in
`Tools/make-dmg-layout.sh` and the coordinates in `Tools/make-dmg-background.swift`
are the same numbers.

### Manual procedure

If the workflow fails, and you cannot wait, do these steps on your
Mac:

1. Make an archive and export it with the Developer ID method.
2. Notarize the app with `notarytool`.
3. Staple the ticket to the app with `staple`.
4. Make a zip file:
   `ditto -c -k --sequesterRsrc --keepParent Linen.app Linen-1.1.zip`
5. Make the appcast:

   ```bash
   "$SPARKLE_BIN/generate_appcast" \
     --download-url-prefix "https://github.com/kavoye/linen-browser/releases/download/v1.1/" \
     /path/to/folder-with-the-zip
   ```

6. Make a folder that contains the app, a link to the Applications folder and
   the window layout:

   ```bash
   mkdir -p dmg/.background && ditto Linen.app dmg/Linen.app && ln -s /Applications dmg/Applications
   ```

   ```bash
   cp Tools/dmg/background.tiff dmg/.background/ && cp Tools/dmg/DS_Store dmg/.DS_Store
   ```

7. Make the disk image:

   ```bash
   hdiutil create -volname Linen -srcfolder dmg -fs HFS+ -format UDZO -ov Linen-1.1.dmg
   ```

8. Sign the disk image:
   `codesign --force --sign "Developer ID Application" --timestamp Linen-1.1.dmg`
9. Notarize the disk image with `notarytool`.
10. Staple the ticket to the disk image with `staple`.
11. Attach the disk image, the zip file **and** `appcast.xml` to the release.

## Preview builds

Linen has two update channels. A release is the default. A preview build comes
from the newest commit on `main`, before a release.

To follow preview builds, open Settings › About and set Update channel to
Preview. Sparkle reads the other feed at the next check, with no restart.

### What the workflow does

`.github/workflows/tip.yml` runs each time CI passes on `main`. You neither
start it nor tag anything. The workflow:

1. Reads the version: the last `v` tag, then the number of commits after it,
   such as `0.1.2 (4)`.
2. Uses the tag alone when that count is zero, such as `0.1.2`. The commit is
   the release itself.
3. Builds an archive, signs the app, and sends it to Apple for notarization.
4. Builds a zip file, and no disk image.
5. Signs the app for Sparkle and writes `appcast-tip.xml`.
6. Moves the `tip` tag to that commit.
7. Updates the `tip` pre-release with the two files.
8. Deletes every zip file outside the five most recent.

The workflow takes 20 to 30 minutes. Ten commits in ten minutes produce one
build: a new run cancels the one before it, and the last commit is what
builds.

### Where each feed is

| Channel | Tag | Pre-release | Feed asset |
| --- | --- | --- | --- |
| Release | `v0.1.2`, a new tag each time | No | `appcast.xml` |
| Preview | `tip`, one tag that moves | **Yes** | `appcast-tip.xml` |

`Linen/Updates/UpdateFeed.swift` contains both URLs. The release feed is
`releases/latest/download/appcast.xml`. The preview feed is
`releases/download/tip/appcast-tip.xml`. The second URL is a permalink because
the tag name never changes.

### Rules to keep

- **The `tip` release must stay a pre-release.** GitHub makes the most recent
  release that is not a pre-release the “latest” release, and
  `releases/latest/download/` reads that release. A `tip` release that is not a
  pre-release takes the release feed URL. The workflow sets the flag on each
  run.
- **The two feed files must keep different names.** That is what makes the
  mistake above recoverable. With different names the release feed returns a
  404, update checks fail, and you can fix it. With the same name everyone moves
  to the preview channel, and since Sparkle never installs an older version, you
  cannot fix it.
- **The build number must always increase.** Both workflows use `git rev-list
  --count HEAD`. A release is always at or after the previews before it, so its
  number is never lower.
- **The `tip` tag is not a version tag.** The workflow reads the last version
  with `git describe --match 'v[0-9]*.[0-9]*'`. Without the pattern, `git
  describe` finds `tip`, and the count becomes zero at each build.
- **The commit a release tags still builds a preview.** A release writes to the
  release feed only. If the preview build stops at that commit, the preview
  channel stays on the release before it, and everything since sits in no
  preview feed until the next commit lands on `main`.
- **A preview build uses the signing keys.** The certificate, the notarization
  key and the Sparkle key are used on every green commit on `main`, not only at
  a release.

### Going back to releases

Set Update channel to Release, and Linen reads the release feed again. Sparkle
never installs an older version, so the app stays on the preview build until a
release carries a higher build number. To go back at once, download the disk
image from the releases page and replace the app.

## Update behavior

- Sparkle checks for an update at launch, and then every four hours. If a
  background check fails, the app shows nothing.
- The feed that Sparkle reads depends on the Update channel setting. A change
  to the setting starts a check immediately.
- When Sparkle finds an update, the banner appears in two places: above the
  settings page, and in the sidebar below the media player.
- Install does the whole job: it downloads the update, installs it, and opens
  Linen again, without asking a second time. Nothing downloads before someone
  chooses Install.
- Dismissing the banner defers the update rather than skipping it, and a
  downloaded update carries on at the next launch.
- Linen › Check for Updates… checks straight away, and the same banner shows the
  result.
