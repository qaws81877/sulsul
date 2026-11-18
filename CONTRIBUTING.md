# Contributing to 술술 (Sulsul)

술술 is a personal fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) used by a small group of people. See [README.md](README.md) and [NOTICE](NOTICE) for what this fork changes.

## Pull requests

Pull requests are welcome.

- Bug fixes and small improvements can go straight to a pull request.
- For a new feature or a larger change, open an issue first so we can agree on the approach.
- Run `make` and `make test` and say in the pull request which ones you ran. A green build does not show that recording, paste or macOS permissions work, so also say what you tried in the app.
- Contributions are licensed under the [GPL-3.0](LICENSE), the license of this project.

This fork has a few rules a pull request must keep:

- It must run side by side with an installed VoiceInk: do not reuse VoiceInk's bundle ID, data folder, Keychain service or defaults domain.
- API keys stay in the Keychain and are entered by each user. Never commit a key, a Team ID (it goes in the git-ignored `Signing.local.xcconfig`) or a signing file.
- Do not add contact with upstream VoiceInk servers.
- Do not reorder the SwiftData schema or rename saved values and `UserDefaults` keys; existing users' data depends on them.
- Leave `project.pbxproj` alone when adding files; the project picks up new files automatically.
- Release files (`appcast.xml`, `scripts/release.sh`, signing settings) are changed only by the maintainer.

## Issues

Bug reports and feature ideas are welcome as [issues](https://github.com/qaws81877/sulsul/issues). Use the templates.

- Report problems with 술술 here, not in the upstream VoiceInk repository.
- Report a VoiceInk problem that also happens in an unmodified VoiceInk build to [upstream](https://github.com/Beingpax/VoiceInk/issues).
- Never paste an API key, a recording you do not want to share, or private dictated text into an issue. The repository is public.

## Building

[BUILDING.md](BUILDING.md) covers requirements (macOS 15+, Xcode, Apple silicon), `make local`, `make test`, and signing.

## Code of conduct

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
