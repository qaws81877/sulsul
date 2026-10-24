# Verification

Open this before reporting a code change as done, or before testing the app at runtime.

- Gate: `make` (check + Debug build of scheme `VoiceInk`).
- Tests: the `VoiceInkTests` target when touching `Features/Enhancement/`, `Features/Dictionary/`, `Core/Enhancement/AIPrompts.swift`, or test fixtures.
- Korean cleanup changes: update the JSONL fixture cases with the prompt.
- A green build or test run is not evidence that mic capture, paste, TCC permissions, or a live provider response work; say which runtime behavior was not exercised.

## Build and test quirks
- "Multiple commands produce …/Resources/AGENTS.md" (untracked subfolder `AGENTS.md` files bundled by the synchronized group) is handled by `EXCLUDED_SOURCE_FILE_NAMES = "AGENTS.md CLAUDE.md"` in both build configurations of `project.pbxproj` (commit `1b2912a6`). If it returns, check that setting first; adding another file name needs the user's approval.
- Run tests with `make test`. A plain `xcodebuild test` fails on signing ("requires a development team"). The target signs ad-hoc with `LocalBuild.xcconfig` and builds into `.test-build.noindex`; pointing a test build at `.build.noindex` replaces `Sulsul Dev.app` with a `LOCAL_BUILD` binary.
- "The test runner hung before establishing connection." has come from the environment, not the change: it reproduced on a clean HEAD worktree and passed on a later rerun. Check HEAD and look for a pending macOS dialog (SecurityAgent) before changing code.

## Runtime checks
- `make` builds only `Sulsul Dev.app`. A change is not in the app the user runs until `make local` replaces `~/Downloads/Sulsul.app`. Quit it first (`pkill -x Sulsul`), keep a copy of the old one, then confirm the new binary (`strings` for a new literal, `codesign --verify --deep --strict`) and reopen it. Ask before replacing unless the user already approved.
- Several copies with the same bundle ID make macOS launch whichever it picks. Before a runtime test, confirm the running path with `pgrep -lf Sulsul` is `~/Downloads/Sulsul.app`; keep build output in `*.noindex` folders and do not leave extra `.app` copies.
- To diagnose a dictation or cleanup result, read the transcript store first (`~/Library/Application Support/com.qaws81877.sulsul/*.store`, table `ZTRANSCRIPTION`: `ZAIENHANCEMENTMODELNAME`, `ZENHANCEMENTDURATION`, `ZENHANCEDTEXT`, `ZPROMPTNAME`). `log show` returns nothing for this app from an agent shell (subsystem and process predicates alike), so empty output is not evidence of no errors. The installed app may be built from a different branch than HEAD.
