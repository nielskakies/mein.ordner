#!/usr/bin/env bash
# Festgelegte Einstellungen fuer dieses Reel (abgestimmt am 2026-09-06):
#   9:16 hochkant 1080x1920, mittiger Crop
#   jeder Clip auf max. 4 Sekunden
#   0,5 s Crossfade zwischen den Clips
#   0,5 s Ein-/Ausblenden aus und nach Schwarz
#   Originalton
# Weitere Optionen werden durchgereicht, z.B.:  tools/reel.sh --music song.m4a
set -euo pipefail
cd "$(dirname "$0")/.."
exec tools/make-reel.sh \
  --aspect 9:16 \
  --fit cover \
  --max-dur 4 \
  --xfade 0.5 \
  --fade 0.5 \
  "$@"
