---
name: verify
description: Build, launch and drive the Sulsul Dev app to observe a UI change (dashboard, settings panels) with window-only screenshots.
---

## Scope
- Loading this skill is not verification. Launch and drive the app only when the diff changes what the app shows or does at runtime; otherwise say that nothing visible changed.
- Info.plist keys or build settings: run `make`, then read the built value (`plutil -extract <key> raw "<built app>/Contents/Info.plist"`). Scripts: `bash -n`, then the script's own dry path. Docs only: nothing to run.
- State in the report which runtime behavior was not exercised: a green build does not show that capture, paste, permissions or an update install work.

## Build and launch
- `make` builds `.build.noindex/Build/Products/Debug/Sulsul Dev.app`. Start it with `.claude/skills/verify/dev-app.sh start` and finish with `.claude/skills/verify/dev-app.sh stop`. `start` launches by absolute path (`open -a` reads a relative path as an app name and fails), gives the app a scratch data folder, skips onboarding and prints the PID; `stop` kills only that PID and deletes the scratch folder and the onboarding key. Do not launch by hand, and do not drive or stop a Sulsul Dev the script did not start: `start` refuses when one is already running.
- Do not use `make local` to verify: it replaces the user's `~/Downloads/Sulsul.app`.
- Debug keeps its own data (`~/Library/Application Support/com.qaws81877.sulsul.dev`, defaults domain `com.qaws81877.sulsul.dev`), so it starts in onboarding; the script sets `hasCompletedOnboardingV2` and puts it back on `stop`. The scratch folder (`SULSUL_SUPPORT_DIR_NAME`) isolates Application Support only; the defaults domain stays shared with `make dev`. An app that relaunches itself (Sparkle's Install & Relaunch) does not inherit the env var, so it opens the default Dev folder and has a PID the script does not know. A "새로운 소식" sheet appears first; Escape does not close it, click its X.

## Capture
- Capture only the app window: find its id with CoreGraphics `CGWindowListCopyWindowInfo` filtered by the app PID (the main window is the 950x782 one named 술술), then `screencapture -x -o -l <id> out.png`. Never use `screencapture -R` or full-screen capture: other apps' windows overlap and end up in the image.
- `log show` returns nothing for this app from an agent shell.

## Drive
- In the SwiftUI main window the AX tree is empty and System Events `click at` lands on a group, not on a button. There, post real mouse events with CGEvent (`leftMouseDown`/`leftMouseUp` at a screen point).
- AppKit UI is different: the menu bar and Sparkle's update windows take System Events clicks by name (`click menu item "<title>" of menu 1 of menu bar item 2 of menu bar 1`, `click button "<title>" of window "<title>"`). Their button titles change with each stage (for example the install window shows a progress bar before its action button), so poll `every button of window` until the one you need exists, then click it.
- Before every click, `activate` the app, check System Events' frontmost process is "Sulsul Dev", and read `position of window 1` (it moves between displays); click at window position + offset. Without that check the click lands in whatever app is on top.
- Typing: `keystroke` guarded by `if frontmost`.
- For connection tests in custom provider panels, use an unreachable local endpoint (`http://127.0.0.1:9/...`) so nothing leaves the machine; do not press "모델 추가" (writes Keychain and settings).

## Update flow
Proves the feed, the EdDSA signature and the install/relaunch mechanics of the in-app updater without publishing. It does not prove Developer ID continuity, DMG extraction or Gatekeeper: test those by installing the previous notarized release and updating it from the real feed.
1. After `make`, copy `Sulsul Dev.app` twice (old, new).
2. old: lower `CFBundleShortVersionString` and `CFBundleVersion` (`plutil -replace`) and point `SUFeedURL` at `http://127.0.0.1:<free port>/appcast.xml`. Then `codesign --force --deep -s -` both copies: the build's linker-signed signature does not seal the bundle.
3. new: `ditto -c -k --keepParent` into a serve dir, then `generate_appcast --account Sulsul --download-url-prefix http://127.0.0.1:<port>/ --versions <build> <serve dir>`. The tool is under `.local-build.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin/` and signs with the keychain key.
4. Serve with `python3 -I -m http.server <port> --bind 127.0.0.1 --directory <serve dir>`. Check the port is free first (`lsof -nP -iTCP:<port> -sTCP:LISTEN`).
5. `dev-app.sh` starts only the built app, not these copies: launch old by hand with `open -n -a "<absolute path to old>" --env SULSUL_SUPPORT_DIR_NAME=<scratch name>`, keep its PID, and make sure no other Sulsul Dev is running. Click the update menu item and then the install button, wait until the install-ready window shows its action button, and click "Install & Relaunch".
6. Pass: the old copy's `Info.plist` on disk shows the new version and the real `SUFeedURL`, and `codesign --verify --deep --strict` passes. Sitting at "install ready" is not a failure: the install starts only after the click.
7. Clean up your own PIDs, the server and the scratch folders. The relaunched app does not inherit your env var, so it opens the default Dev data folder.
