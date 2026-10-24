# Building 술술 (Sulsul)

술술 is a modified fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi (Pax). See [NOTICE](NOTICE) and [README.md](README.md).

## Requirements

- macOS 15.0 or later
- Xcode 27 (this project was last upgraded by Xcode 26.5-era tools; `LastUpgradeCheck` is 2650). Command Line Tools selected with `xcode-select`.
- Git
- Apple silicon. The current local build path is an M5 Pro.

The Xcode target and scheme stay named `VoiceInk` so the Swift module name does not change. The built app is `Sulsul.app` (Release) or `Sulsul Dev.app` (Debug).

## Team ID

Your Team ID lives in `Signing.local.xcconfig` at the repository root. The file is git-ignored, so the ID is never committed. [Signing.xcconfig](Signing.xcconfig) stays committed with an empty `DEVELOPMENT_TEAM` and includes the local file when it exists.

1. Open [Apple Developer membership](https://developer.apple.com/account) and copy the 10-character Team ID.
2. Create `Signing.local.xcconfig` with this line, with no quotes:

```
DEVELOPMENT_TEAM = ABCDE12345
```

`make local` passes an empty team and `LocalBuild.xcconfig`, so a day-to-day local build does not need this. `make release`, `make release-setup`, and Xcode archives read `Signing.local.xcconfig`, then `Signing.xcconfig`. Do not put another person's Team ID in the project, and do not put yours in `Signing.xcconfig`.

## Local build

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
cd /path/to/VoiceInk
make local
open ~/Downloads/Sulsul.app
```

`make local` prepares `whisper.xcframework` under `~/VoiceInk-Dependencies` (a build-tool checkout, not the app's data folder), builds the `VoiceInk` scheme in the Release configuration into `.local-build.noindex`, copies `Sulsul.app` to `~/Downloads`, and removes the built copy so only one app with the bundle ID remains.

It uses `LocalBuild.xcconfig`, `VoiceInk/VoiceInk.local.entitlements`, and the `LOCAL_BUILD` Swift flag. Without an override, it uses the only available Apple Development identity, or ad-hoc signing when none or several are found.

Choose an identity explicitly:

```bash
make local LOCAL_CODESIGN_IDENTITY="<SHA or name>"
```

Force ad-hoc signing:

```bash
make local LOCAL_CODESIGN_IDENTITY=-
```

Local builds keep iCloud dictionary sync off. They carry the same Sparkle key and feed URL as release builds, so they also check for updates; installing a release update over an ad-hoc local build has not been tested. Ad-hoc builds may ask for macOS permissions again after each rebuild.

## Other commands

- `make check` — verify required tools
- `make whisper` — prepare `whisper.xcframework`
- `make build` — Debug build (`Sulsul Dev.app`)
- `make dev` — build and launch `Sulsul Dev.app`
- `make run` — launch `~/Downloads/Sulsul.app`, or the first match in DerivedData
- `make release` — signed, notarized DMG and Sparkle appcast (after the steps below)
- `make release-setup` — store notarization credentials; reads the Team ID from `Signing.local.xcconfig`
- `make clean` — remove `~/VoiceInk-Dependencies`
- `make help` — list commands

## Xcode

```bash
make setup
open VoiceInk.xcodeproj
```

Select the `VoiceInk` scheme. Run builds `Sulsul Dev.app`. Archive uses Release and produces `Sulsul.app`. `LOCAL_BUILD` applies only through `make local`.

## Releasing (maintainers only)

Skip this section if you only build for yourself. Publishing needs your own Apple Developer ID certificate, notarization credentials, Sparkle signing key and a GitHub repository to host releases. `scripts/release.sh --help` lists every option; this section records what the script cannot check for you.

### Once per Mac

- Put `DEVELOPMENT_TEAM` in `Signing.local.xcconfig` and install a Developer ID Application certificate for that team in Keychain.
- Register the Mac as a macOS device (Certificates, Identifiers & Profiles → Devices). Archiving signs with a Mac development profile first, and Apple will not create one for a team without devices. `release.sh` passes `-allowProvisioningUpdates`, so Xcode creates the App ID and profiles itself; Xcode must be signed in to that account.
- Run `make release-setup` in a real terminal: the Apple ID and the app-specific password are read from the terminal and fail without one. The notarytool profile is named `Sulsul-Notarization`.
- The Sparkle signing key (account `Sulsul`) lives in the login Keychain, and its public key is `SUPublicEDKey` in `VoiceInk/Info.plist`. Never replace that key: installed apps verify every update against it, and a lost private key means installed apps can never be updated again. On a new Mac, import the backed-up private key and check that the public key still matches:

```bash
# path is under DerivedData after a package resolve
generate_keys --account Sulsul -f <private-key-file>
generate_keys --account Sulsul -p   # must equal SUPublicEDKey in Info.plist
```

### Each release

1. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (the build number is an integer greater than the last release's), add `release-notes/<version>.html`, and commit. The script refuses a dirty tree unless `--allow-dirty` is passed.
2. `make release NOTES=release-notes/<version>.html` builds, signs, notarizes and writes `Sulsul.dmg` and `appcast.xml` into one run folder. It does not commit, tag, or upload.
3. Publish the DMG and the appcast from that same run folder. The appcast carries the DMG's signature and length, so if the DMG is rebuilt take both again:

   ```bash
   gh release create v<version> --repo qaws81877/sulsul --target main --latest \
     --title "술술 <version>" --notes "<notes>" "<run folder>/Sulsul.dmg" "<run folder>/appcast.xml"
   ```

   The release must be the latest one, not a draft or pre-release, and `appcast.xml` must be one of its assets: the app reads `https://github.com/qaws81877/sulsul/releases/latest/download/appcast.xml`, which GitHub resolves to that asset. The `Check update feed` workflow verifies this from the outside after every release change.
4. Commit the generated `appcast.xml` as a copy of that asset; the app does not read the repository file.
5. Update the Homebrew tap: in a clone of [qaws81877/homebrew-sulsul](https://github.com/qaws81877/homebrew-sulsul) run `scripts/bump.sh <version>`, review the diff, then commit and push. The script downloads the published DMG to record its SHA-256, so the release has to exist first. A stale tap does not affect the in-app updater; it only delays `brew install` and `brew upgrade`.

## App icon

`scripts/generate-app-icon.swift` draws the icon and writes every file that carries it:

- `VoiceInk/Assets.xcassets/AppIcon.appiconset/` (`16-mac.png` through `1024-mac.png`)
- `VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon.png`
- `release/dmg/volume-icon.icns` (needs `iconutil`)

```bash
swift scripts/generate-app-icon.swift
```

To change the artwork, edit the script and run it again. The DMG background (`release/dmg/background.png` and `background.tiff`) is not generated; if you replace it, keep the same pixel sizes the existing images use.
