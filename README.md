<div align="center">

# ✿ Hey Claude ✿

**a voice-activated launcher for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) on macOS**

*say the words, and a little guy in your notch gets to work* ⊹ ࣪ ˖

made by one girl who got really, really tired of typing `claude` a hundred times a day ♡

![Version](https://img.shields.io/badge/version-v0.1.0-9cf)
![Platform](https://img.shields.io/badge/platform-macOS%2014.4%2B-black)
![Apple Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![Processing](https://img.shields.io/badge/processing-100%25%20on--device-2ea44f)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

> **Unofficial / community project.** Not affiliated with or endorsed by Anthropic.
> "Claude" is Anthropic's mark — this tool just borrows the wake phrase. ꒱

</div>

---

## ⊹ what is this ⊹

okay so — I was typing `claude` into my terminal approximately one million times a day, and one afternoon I thought, *what if I could just… ask?*

so I taught my Mac to listen. ꒰ ˶• ᵕ •˶ ꒱

say **"Hey Claude"** and it opens (or focuses) a Claude Code session for you — completely hands-free. follow the wake word with a question and it carries that straight in. and there's a tiny **mascot living in your notch** that blinks while it listens, thinks, and works, so you always know it's awake.

everything runs **on-device**. your voice never leaves your Mac. ♡

### the good bits

- 🎙️ **hands-free** — wake-word activation. no hotkey, no clicking.
- 🔒 **private by default** — wake-word detection *and* speech-to-text run entirely on your machine; nothing leaves your device.
- 🪄 **a little guy in your notch** — an ambient mascot that reflects the voice state (idle · listening · thinking).
- 🧩 **opens where you work** — VS Code, Cursor, Antigravity, or your terminal (Terminal.app / iTerm2 / Ghostty).
- 🗣️ **learns your voice** — onboarding tunes the wake word to your own voice & accent.
- ⚡ **spoken prompts** — *"Hey Claude, &lt;question&gt;"* sends it straight into Claude Code.
- 🎨 **make it yours** — pick the notch mascot and its color in Preferences.

---

## ♡ privacy

This is the part I care about most. All wake-word and speech recognition happens **locally**, using on-device models (a streaming KWS zipformer for the wake word, Parakeet for speech-to-text). Your microphone audio is processed on your machine and is **not uploaded anywhere** by this app. The only thing that leaves your Mac is whatever **you** then send through Claude Code itself.

No telemetry. No cloud wake word. No audio logged or sent anywhere.

> **Caveat (the honest fine print):** macOS itself may still show a microphone-in-use indicator, and Claude Code — once launched — talks to Anthropic as it normally would. "On-device" refers to *this app's* wake-word and transcription pipeline.

---

## how it works

```
mic → wake word (KWS zipformer) → voice-activity detection → speech-to-text (Parakeet) → route
```

| You say | What happens |
| --- | --- |
| **"Hey Claude"** (bare) | Launches or focuses Claude Code in your chosen editor or terminal |
| **"Hey Claude, &lt;question&gt;"** | Starts Claude Code seeded with your spoken question |
| **"Hey Claude code &lt;task&gt;"** | Claude Code, explicit |

### opens where you work

Claude Code launches into the surface you actually use:

- **Editors** — **VS Code**, **Cursor**, or **Antigravity** (via the editor's Claude Code extension).
- **Terminals** — **Terminal.app**, **iTerm2**, or **Ghostty**.

On first run it detects the editor you're actively using and defaults to it (falling back to a terminal when the signal is ambiguous). You can change the target anytime in **Preferences**.

---

## requirements

- **macOS 14.4+** on **Apple Silicon** (built and tested on macOS 26)
- **Xcode Command Line Tools** — `xcode-select --install`
- **Swift 6** toolchain
- The [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) on your `PATH`

## build & run

The ML model files and the prebuilt sherpa-onnx framework are **not** checked in (they're large and carry their own upstream licenses). Two scripts fetch them from pinned upstream releases:

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

By default the bundle is **ad-hoc signed** (works anywhere, but macOS won't persist microphone/automation permission grants across rebuilds). For a stable signature, set your Developer ID identity first:

```bash
export HEYCLAUDE_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
./scripts/bundle-app.sh
```

On first launch, grant **Microphone** access when prompted; onboarding then walks you through calibrating the wake word to your voice.

### developer tools

```bash
swift run heyclaude-selftest    # on-machine test harness (decode probes, wake sweeps)
swift test                      # XCTest suite (requires a full Xcode toolchain)
```

---

## contributing

Issues and pull requests are very welcome — this is a community project and I'd love the help. ꒰ ˶ˆ ᵕ ˆ˶ ꒱ Please keep the unaffiliated-with-Anthropic framing intact, and note that contributions are accepted under the project's GPL-3.0 license. If you're filing a wake-word reliability issue, the `heyclaude-selftest` probes (above) produce the diagnostics worth attaching.

## third-party & licenses

This project's own source is licensed under **GPL-3.0** (see [`LICENSE`](LICENSE)) — if you distribute a modified version, you must release your changes under the same license. Bundled and downloaded components keep their respective upstream licenses; see [`NOTICE`](NOTICE) for full attributions.

- **sherpa-onnx** ([k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)) — Apache-2.0, © Xiaomi Corporation. The Swift binding is adapted from upstream; the framework is fetched at build time. **ONNX Runtime** (Microsoft) — MIT.
- **Models** (KWS zipformer, Parakeet TDT) are fetched from the sherpa-onnx model releases under their respective upstream licenses.
- **Fonts:** the UI is designed in *General Sans* (© Indian Type Foundry, free via [Fontshare](https://www.fontshare.com/fonts/general-sans)). Its license doesn't permit redistributing the font files, so they're **not included** here — the app falls back to the system font automatically. For the branded look, download General Sans from Fontshare and drop the `.otf` files into `Resources/Fonts/`.

---

<div align="center">

made with 🩷 by **lilmelon77** · [GPL-3.0](LICENSE) © 2026

*now go yell at your computer (nicely)* ✿

</div>
