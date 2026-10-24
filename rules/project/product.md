# Product

Open this before changing behavior users see, persisted data, identity, or anything that talks to the network.

- Repo: 술술 (Sulsul), a GPLv3 personal fork of VoiceInk for macOS 15+, public at `github.com/qaws81877/sulsul` (renamed from `VoiceInk` on 2026-10-24; the old URL redirects). The Xcode target, scheme and local folder keep the name `VoiceInk`; the product is Sulsul (`com.qaws81877.sulsul`).
- The Sparkle feed URL is written in `VoiceInk/Info.plist`, `AppIdentity.sparkleFeedURL` and `scripts/release.sh` (`EXPECTED_FEED_URL`). Change them together.
- Source of truth: `AGENTS.md` (structure, ANTI-PATTERNS), `README.md` / `NOTICE` (fork changes), `BUILDING.md` (builds, signing), `docs/PLAN.md` (current plan).
- Invariants: must coexist with an installed upstream VoiceInk; API keys only in Keychain, entered by each user; no contact with upstream servers; persisted raw values and the SwiftData schema order never change. Details: `AGENTS.md` ANTI-PATTERNS.
- Korean cleanup behavior is pinned by prompt fixtures and JSONL cases under `Tests/VoiceInkTests/`.
- Statements about where audio or text goes live in `README.md` and `README.ko.md` (Privacy) and in the captions of `Features/Modes/Views/ModeConfigFormView.swift`; change them together. Before writing or editing one, trace the real routing in code, not only the provider list: the Korean cleanup pipeline (`KoreanCleanupPolicy.usesDefaultPipeline`) has its own provider order, an Anthropic fallback and sends no context, and `KoreanCleanupAdoption` switches cleanup on when an OpenAI or Anthropic key is added.
- Non-goals: redistribution of VoiceInk Refine, upstream licensing/Polar.
