#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="$ROOT/Models"
mkdir -p "$MODELS"
cd "$MODELS"

# --- Wake stage: English streaming zipformer KWS model ---
# Asset verified on release tag `kws-models` (k2-fsa/sherpa-onnx).
KWS="sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"
if [ ! -d "$KWS" ]; then
  curl -fL -O "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/${KWS}.tar.bz2"
  tar xjf "${KWS}.tar.bz2" && rm "${KWS}.tar.bz2"
fi

# --- STT stage: offline Parakeet TDT (English, int8) ---
# Asset verified on release tag `asr-models` (k2-fsa/sherpa-onnx).
ASR="sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
if [ ! -d "$ASR" ]; then
  curl -fL -O "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${ASR}.tar.bz2"
  tar xjf "${ASR}.tar.bz2" && rm "${ASR}.tar.bz2"
fi

echo "Models ready in $MODELS"
ls -d "$MODELS"/*/
