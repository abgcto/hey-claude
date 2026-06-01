# Contributing to Hey Claude

Thanks for being here! Issues and pull requests are very welcome — this is a small
community project and help is appreciated. This guide covers the few things that
aren't obvious from the code.

> **Scope:** Hey Claude is a macOS (14.4+), Apple-Silicon, **directly-distributed** app.
> It uses a `CGEventTap` (Input Monitoring) and notch UI that won't work under the Mac
> App Store sandbox, so it targets direct / notarized distribution only.

## Getting set up

See the [README](README.md) for requirements. In short:

```bash
./scripts/fetch-sherpa.sh    # assemble the sherpa-onnx static xcframework
./scripts/fetch-models.sh    # download the KWS + Parakeet models
```

Neither the models nor the framework are checked in (they're large and carry their own
upstream licenses), so run both before building.

## Running the app — use the dev loop

```bash
./scripts/dev.sh             # build → install to /Applications → relaunch (debug)
./scripts/dev.sh release     # optimized build
```

`dev.sh` exists for a reason: the binary you actually launch lives at
`/Applications/HeyClaude.app` (Spotlight / login item), so editing source and rebuilding
the repo copy does nothing if you're running the installed one. `dev.sh` rebuilds, installs,
kills the old instance, and relaunches — so the binary on screen is always the one you just
built.

> **Don't use `swift run HeyClaudeApp` to exercise the app.** It launches the bare SwiftPM
> binary with no `Info.plist`, so microphone permission, bundled fonts, and the app icon are
> all missing. It's fine for a compile check, nothing more.

**Set a stable signing identity while developing:**

```bash
export HEYCLAUDE_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

macOS keys microphone & Input-Monitoring permission grants to the **code signing identity**.
Without `HEYCLAUDE_SIGN_ID`, `bundle-app.sh` ad-hoc signs and rotates the identity every
build — which silently wipes those grants, and the wake word *and* push-to-talk both go dead
(they share the mic). A stable Developer ID identity keeps grants across rebuilds.

## Testing

```bash
swift test                         # XCTest suite (requires a full Xcode toolchain)
swift run heyclaude-selftest all   # on-machine harness (works with Command Line Tools)
```

`heyclaude-selftest` is the CLT-friendly harness (the CLT toolchain has no XCTest runner).
Useful subcommands include `decode-probe`, `mic-decode`, `boost-sweep`, `threshold-sweep`,
`enroll`, `route`, and `editor-route`.

## Debugging wake-word reliability

The KWS keyword must match the tokens the model **actually emits** for the spoken phrase —
**not** the dictionary spelling. Use `swift run heyclaude-selftest decode-probe` (synthetic
clips) or `mic-decode` (live voice) to print the real emitted tokens, then build the keyword
from those. Verify with the `boost-sweep` / `threshold-sweep` probes.

If you're filing a wake-word issue, please attach the relevant probe output.

## The one load-bearing rule

`VoiceSession`'s callbacks (`transcribe` / `execute` / `observe`) fire on the **audio serial
queue, never the main actor** — they are `@Sendable` on purpose. A main-actor-isolated
closure invoked off-main **hard-traps on macOS 26** (`_dispatch_assert_queue_fail`). Keep
these closures non-isolated; don't "fix" the `@Sendable` annotation by capturing main-actor
state.

Otherwise: match the style of the surrounding code.

## What not to commit

- **Font files** (`Resources/Fonts/*.otf`) — General Sans isn't redistributable; it's
  gitignored, and the app falls back to the system font without it.
- **Your signing identity** — keep `HEYCLAUDE_SIGN_ID` in your shell env, never in a commit.
- **Secrets** — `.env`, `*.p12`, `*.mobileprovision` are gitignored; keep it that way.

## Pull requests

- Keep small and focused; describe **what** changed and **why**.
- Please preserve the **unofficial / not affiliated with Anthropic** framing.
- By contributing, you agree your changes are licensed under the project's **GPL-3.0**
  license (see [LICENSE](LICENSE)).

Happy hacking. ✿
