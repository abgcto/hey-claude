<div align="center">

# Hey Claude

**An on-device, voice-activated launcher for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) on macOS.**

Stop typing `claude` ten times a day — just say it instead.

![Version](https://img.shields.io/badge/version-v0.1.0-9cf)
![Platform](https://img.shields.io/badge/platform-macOS%2014.4%2B-black)
![Apple Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![Processing](https://img.shields.io/badge/processing-100%25%20on--device-2ea44f)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

> **Unofficial / community project.** Not affiliated with or endorsed by Anthropic.
> "Claude" is Anthropic's mark; this tool reuses the wake phrase only.

</div>

## What it is

A lightweight macOS menu-bar app that listens **on-device** for the wake word *"Hey Claude"*
and launches or focuses a Claude Code session for you — hands-free. A persistent ambient
**notch island** shows the app is alive and reflects its voice state (idle, listening,
thinking). Say the bare wake word to just open or focus Claude Code, or follow it with a
question to start a session seeded with your prompt.

### Highlights

- 🎙️ **Hands-free** — wake-word activation, no hotkey, no clicking.
- 🔒 **Private by default** — wake-word detection and speech-to-text run entirely on your
  machine. In the default configuration, nothing leaves your device.
- 🪄 **Ambient notch island** — a live status indicator that lives in the menu-bar notch.
- 🧩 **Opens where you work** — VS Code, Cursor, Antigravity, or your terminal (Terminal.app / iTerm2 / Ghostty).
- 🗣️ **Per-user wake calibration** — onboarding tunes the wake word to your voice and accent.
- ⚡ **Spoken prompts** — *"Hey Claude, &lt;question&gt;"* sends the question into Claude Code.
- 🎨 **Make it yours** — pick the notch mascot and its color in Preferences.

## Privacy

All wake-word and speech recognition happens **locally**, using on-device models
(a streaming KWS zipformer for the wake word, Parakeet for speech-to-text). Your microphone
audio is processed on your machine and is not uploaded anywhere by this app. The only thing
that leaves your machine is whatever **you** subsequently send through Claude Code itself.

No telemetry. No cloud wake word. No audio logged or sent anywhere.

> **Caveat:** macOS itself may still surface a microphone-in-use indicator, and Claude Code
> (once launched) communicates with Anthropic as it normally would. "On-device" refers to
> *this app's* wake-word and transcription pipeline.

## How it works

```
mic → wake word (KWS zipformer) → voice-activity detection → speech-to-text (Parakeet) → route
```

| You say | What happens |
| --- | --- |
| **"Hey Claude"** (bare) | Launches or focuses Claude Code in your chosen editor or terminal |
| **"Hey Claude, &lt;question&gt;"** | Starts Claude Code seeded with your spoken question |
| **"Hey Claude code &lt;task&gt;"** | Claude Code, explicit |

### Opens where you work

Claude Code launches into the surface you actually use:

- **Editors** — **VS Code**, **Cursor**, or **Antigravity** (via the editor's Claude Code
  extension).
- **Terminals** — **Terminal.app**, **iTerm2**, or **Ghostty**.

On first run it detects the editor you're actively using and defaults to it (falling back to
a terminal when the signal is ambiguous). You can change the target anytime in **Preferences**.

## Requirements

- **macOS 14.4+** on **Apple Silicon** (built and tested on macOS 26)
- **Xcode Command Line Tools** — `xcode-select --install`
- **Swift 6** toolchain
- The [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) on your `PATH`

## Build & run

The ML model files and the prebuilt sherpa-onnx framework are **not** checked in
(they're large and carry their own upstream licenses). Two scripts fetch them from
pinned upstream releases:

```bash
# 1. Assemble the sherpa-onnx static xcframework (downloads + merges onnxruntime)
./scripts/fetch-sherpa.sh

# 2. Download the wake-word (KWS) and speech-to-text (Parakeet) models
./scripts/fetch-models.sh

# 3. Build and run the menu-bar app
swift run HeyClaudeApp
```

To produce a distributable `HeyClaude.app` bundle:

```bash
./scripts/bundle-app.sh
```

By default the bundle is **ad-hoc signed** (works anywhere, but macOS won't persist
microphone/automation permission grants across rebuilds). For a stable signature, set your
Developer ID identity first:

```bash
export HEYCLAUDE_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
./scripts/bundle-app.sh
```

On first launch, grant **Microphone** access when prompted; onboarding then walks you
through calibrating the wake word to your voice.

### Developer tools

```bash
swift run heyclaude-selftest    # on-machine test harness (decode probes, wake sweeps)
swift test                      # XCTest suite (requires a full Xcode toolchain)
```

## Contributing

Issues and pull requests are welcome. This is a community project — please keep the
[unaffiliated-with-Anthropic](#hey-claude) framing intact, and note that contributions are
accepted under the project's GPL-3.0 license. If you're filing a wake-word reliability
issue, the `heyclaude-selftest` probes (above) produce the diagnostics worth attaching.

## Third-party assets & licenses

This project's own source is licensed under **GPL-3.0** (see [`LICENSE`](LICENSE)) — if you
distribute a modified version, you must release your changes under the same license. Bundled
and downloaded components keep their respective upstream licenses; see [`NOTICE`](NOTICE) for
full attributions.

- **sherpa-onnx** ([k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)) — Apache-2.0,
  © Xiaomi Corporation. The Swift binding is adapted from upstream; the framework is fetched
  at build time. **ONNX Runtime** (Microsoft) — MIT.
- **Models** (KWS zipformer, Parakeet TDT) are fetched from the sherpa-onnx model releases
  under their respective upstream licenses.
- **Fonts:** the UI is designed in *General Sans* (© Indian Type Foundry, free via
  [Fontshare](https://www.fontshare.com/fonts/general-sans)). Its license does not permit
  redistributing the font files, so they are **not included** here. The app falls back to
  the system font automatically; for the branded look, download General Sans from Fontshare
  and drop the `.otf` files into `Resources/Fonts/`.

## License

[GPL-3.0](LICENSE) © 2026 lilmelon77
