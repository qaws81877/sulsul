# Engineering

Open this before editing code, build files, or user data.

- Fine to change without asking: Swift sources and tests under `VoiceInk/` and `Tests/`, prompt fixtures together with their JSONL cases, docs.
- Ask first (show the diff): the list in `CLAUDE.md` "Ask before changing" - signing/xcconfig/entitlements/Info.plist keys, schema list, persisted raw values, UserDefaults keys, `AppIdentity.swift`, `scripts/`, `appcast.xml`, anything that publishes.
- Never hand-edit `project.pbxproj` to add files; synchronized groups pick them up.
- A new `ModeConfig` field needs encode plus tolerant decode (see `Features/Modes/AGENTS.md`).
- When code changes a fact stated in an `AGENTS.md`, tell the user; local `AGENTS.md` files are untracked here.
- The personal Apple Team ID goes only in the git-ignored `Signing.local.xcconfig`. `Signing.xcconfig` stays committed with an empty `DEVELOPMENT_TEAM` and ends with `#include? "Signing.local.xcconfig"`; `release.sh` and `setup-release-notarization.sh` read the local file first. `LocalBuild.xcconfig` is shared and tracked (`make local` and `make test` pass it with `-xcconfig`), so do not gitignore it.
- This repo is public. Never commit `docs/`, `CLAUDE.md`, `AGENTS.md`, `.cursor/` or `eval/results/` (`docs/perf/harness/` holds a settings snapshot with device IDs, app logs and recordings). Stage files by name, not `git add -A`, so unrelated working-tree changes stay out of a commit.
- Generated files, do not hand-edit. `VoiceInk/Resources/THIRD_PARTY_NOTICES.txt`: after a `Package.resolved` change, or when an asset stops being identical to upstream VoiceInk, run `python3 scripts/generate-third-party-notices.py` (needs the SwiftPM checkouts from a prior `make`) and `--check` must pass. Icon files (`AppIcon.appiconset/*-mac.png`, `menuBarIcon.png`, `release/dmg/volume-icon.icns`): change `scripts/generate-app-icon.swift` and run it; it reproduces the committed files byte for byte.
- Edit `VoiceInk/Localizable.xcstrings` with a script, not by hand. `json.dumps(data, indent=2, ensure_ascii=False, separators=(',', ' : ')) + "\n"` reproduces the file byte for byte, so only added keys show in the diff. Keys are not sorted: append new ones, with `en` as source plus `de`, `fr`, `zh-Hans`, `ko`.
