# Releasing Linen

Linen uses [Sparkle 2.9.5](https://sparkle-project.org) for updates. The app
does not show the Sparkle windows. The update interface is only the banner in
`Linen/Updates/UpdateBanner.swift`.

Two files contain the hosting configuration. The values in these two files must
agree:

- `Linen/Updates/UpdateFeed.swift` — the `owner` and `repository` values
- `Linen/Info.plist` — the `SUFeedURL` value

The feed URL is
`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`.
GitHub sends this URL to the asset with that name in the most recent release.
Thus you do not need a web server or a `gh-pages` branch. Attach `appcast.xml`
to each release. The permalink then points to the new file.

## The signing tools

The SPM package does not build `generate_keys`, `sign_update` and
`generate_appcast`. But the package downloads an artifact bundle that contains
these three tools. Set a variable to their location. Then you do not have to
find the path again:

```bash
export SPARKLE_BIN=$(dirname "$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts/sparkle/Sparkle/bin/sign_update' -print -quit)")
```

This path is in the DerivedData folder. If you clean the build folder, the
system removes the path. The next build makes the path again. As an
alternative, download the release tarball from
https://github.com/sparkle-project/Sparkle/releases.

## One-time: the Sparkle signing keys

The EdDSA key pair exists. `Linen/Info.plist` contains the public key as
`SUPublicEDKey`. The login keychain of this Mac contains the private key.
`sign_update` finds the private key in the keychain. No more configuration is
necessary.

Make a backup of the private key. Keep the backup for a minimum of two years.
If you lose the private key, no installed copy of the app can update again. The
only solution is to tell each user to download the app again.

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

The app stores API keys in the data-protection keychain. That keychain refuses
an item from code that has no keychain access group, so `Linen.entitlements`
declares `keychain-access-groups`. A Developer ID signature can only carry that
entitlement when an embedded profile authorizes it. Gatekeeper refuses to launch
an app that declares the entitlement without the profile.

Do these steps one time in the Apple Developer portal:

1. Open Certificates, Identifiers & Profiles › Identifiers.
2. Select the `com.kavoye.Linen` App ID, or register it.
3. Open Profiles. Add a profile.
4. Select the Developer ID type, under Distribution.
5. Select the `com.kavoye.Linen` App ID and your Developer ID Application
   certificate.
6. Give the profile a name, for example `Linen Developer ID`. Do not use the
   characters `&`, `<` or `>`. The export step puts the name in a plist.
7. Download the profile as `Linen.provisionprofile`.
8. Run this command. The output must contain `keychain-access-groups`:

   ```bash
   security cms -D -i Linen.provisionprofile | plutil -extract Entitlements xml1 -o - -
   ```

9. Put the profile in the `DEVELOPER_ID_PROVISIONING_PROFILE` secret below.

The App ID prefix gives the access group. The portal has no Keychain Sharing
capability. That switch is in Xcode, and it only writes the entitlements file.

Make the profile again when it expires. The release then fails at the Install
provisioning profile step, and at the two checks after the export.

## One-time: who can release

A tag starts the release. Only an account with write access can push a tag, but
the workflow gives that tag a Developer ID certificate, a notarization key and
the Sparkle private key. The Sparkle key is the most important of the three: it
decides what every installed copy of Linen updates to. Set up all three
controls below before you make the repository public.

**1. The release environment.** The workflow job declares
`environment: release`, and the secrets live in that environment. A job that
waits for a reviewer cannot read the secrets until the reviewer approves it.

1. Open Settings › Environments. Add an environment. Name it `release`.
2. Select Required reviewers. Add yourself. Save the rule.
3. Select Deployment branches and tags. Select Selected branches and tags.
4. Add the tag pattern `v*`.
5. Add the seven secrets from the next section as environment secrets.

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
password also works. But you can revoke the API key independently,
and the API key does not give access to all of your Apple ID.

The team ID is not a secret. The workflow already contains it.

## Each release

```bash
git tag v1.1 && git push origin v1.1
```

The workflow starts, then waits. Approve it in the run page, or in the mail
that GitHub sends you. The workflow then does these steps:

1. It makes sure the tag is on `main`.
2. It runs the tests.
3. It makes an archive.
4. It signs the app with the Developer ID certificate and the profile.
5. It sends the app to Apple for notarization.
6. It staples the notarization ticket to the app.
7. It makes a zip file.
8. It makes a disk image. The image contains the app and a link to the
   Applications folder.
9. It signs the disk image.
10. It sends the disk image to Apple for notarization.
11. It staples the notarization ticket to the disk image.
12. It signs the app for Sparkle.
13. It makes `appcast.xml`.
14. It publishes the GitHub release with the three assets.

The workflow takes 25 to 45 minutes after you approve it. The Apple notary
service uses most of this time, and the workflow waits for it two times.

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
  the `v` character. `CURRENT_PROJECT_VERSION` comes from the number of the
  workflow run. Thus the `CFBundleVersion` value that Sparkle compares always
  increases. Do not change a version by hand in the Xcode project. The values in
  the Xcode project apply only to local builds.
- **The release body supplies the “What’s New” sheet.** The workflow makes the
  body from two parts. `CHANGELOG.md` is optional: make it only when a release
  needs notes of its own. If it contains a `## 1.1` section, that section comes
  first. GitHub then adds the list of the commits and the pull
  requests after the previous tag, and a **New Contributors** section. Thus each
  contributor gets credit, with or without a changelog. The app reads the body
  from the API each time it shows the sheet. Thus you can edit the release later
  to correct the text. A new release is not necessary.
- **Give credit to a security reporter by hand.** [SECURITY.md](SECURITY.md)
  promises the reporter credit in the release notes. The workflow cannot know
  the name. Put the name in the `CHANGELOG.md` section before you make the tag.
  Do not use the name if the reporter asked you to keep it out.
- **The format of the tag is important.** The notes sheet finds the release with
  the name `v<version>`. If it does not find that name, it uses `<version>`.
  Only the formats `vX.Y` and `vX.Y.Z` start the workflow.
- **The workflow makes `appcast.xml` from the app bundle.** Thus the version,
  the minimum system version and the architectures in the feed always agree with
  the app. The feed contains only the most recent release. This is sufficient
  for Sparkle to offer the update to all users.

### Acknowledgements

The app shows the license of each open source package in Settings › About. The
list comes from `Linen/Support/Acknowledgements.json`. A script makes this file
from `Package.resolved` and the resolved checkouts:

```bash
swift Tools/make-acknowledgements.swift
```

Do these steps after you add, remove or update a package:

1. Resolve the packages one time, or build the app.
2. Run the command above.
3. Commit the file with the change to `Package.resolved`.

CI runs the same command and stops the build if the result is different. The
MIT and the Apache license both ask for their terms to go with the binary, and
a signed build is a redistribution. Thus this file is not optional.

### The disk image

The window of the disk image comes from two files in `Tools/dmg`:
`background.tiff` and `DS_Store`. The workflow copies both into the staging
folder. Only Finder writes a `.DS_Store` file, and the runner has no Finder
session. Thus the layout is made one time on a Mac.

Do these steps after you change the artwork or the icon positions:

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

## Update behavior

- Sparkle checks for an update at launch, and then every four hours. If a
  background check fails, the app shows nothing.
- If Sparkle finds an update, the banner shows in two locations: above the
  settings page, and in the sidebar below the media player.
- **Download** starts the download. **Install and Relaunch** completes the
  installation. The app downloads nothing before the user selects **Download**.
- If the user dismisses the banner, the app defers the update. It does not skip
  the update. A downloaded update continues at the next launch.
- Linen › Check for Updates… starts a check immediately. The same banner shows
  the result.
