#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FX="$ROOT/Tests/HeyClaudeKitTests/Fixtures"
mkdir -p "$FX"

gen() {  # gen <name> <text>
  say -v Samantha -o "$FX/$1.aiff" "$2"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$FX/$1.aiff" "$FX/$1.wav"
  rm "$FX/$1.aiff"
}

gen hey_claude_only      "hey claude"
gen hey_claude_code      "hey claude code"
gen hey_claude_prompt    "hey claude refactor the auth module"
gen negative_speech      "the quick brown fox jumps over the lazy dog"
echo "Fixtures ready in $FX"
