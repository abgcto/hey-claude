# Changelog

All notable changes to Hey Claude are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Re-opening the app while it's already running now opens **Settings** (instead of doing nothing).
- Closing the onboarding window before finishing now **quits** the app — it can't run until setup is complete — rather than skipping and staying open.
- Notch control-panel copy: "click mascot" → "click clawd."

## [0.1.0] — 2026-06-01

First public release. Say **"Hey Claude"** and a Claude Code session opens for you — hands-free and fully on-device.

### Added

- **Wake-word launcher** — on-device "Hey Claude" detection (KWS zipformer) → speech-to-text (Parakeet) → opens or focuses Claude Code.
- **Push-to-talk** — hold a hotkey (default Right ⌥), speak, release; **Esc** cancels.
- **Ambient notch island** — a live voice-state indicator that doubles as the control center (mute, switch target, recent launches).
- **Opens where you work** — VS Code, Cursor, Antigravity, or a terminal (Terminal.app / iTerm2 / Ghostty), auto-detected on first run.
- **Per-user wake calibration** during onboarding.
- **Customizable mascot** — pick the notch mascot, its color, and idle animations in Settings.
- Notarized `.dmg` for Apple Silicon, macOS 14.4+.

[unreleased]: https://github.com/lilmelon77/hey-claude/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lilmelon77/hey-claude/releases/tag/v0.1.0
