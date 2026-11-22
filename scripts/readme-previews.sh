#!/usr/bin/env bash
# Builds lightweight README previews (JPEG) from the full-resolution App Store screenshots.
set -euo pipefail
cd "$(dirname "$0")/.."
for lang in en fr es; do
  for device in iPhone iPad; do
    src="Screenshots/$lang/$device"; [[ -d "$src" ]] || continue
    dst="docs/screenshots/$lang/$device"; mkdir -p "$dst"
    for f in "$src"/*.png; do
      size=$([[ $device == iPad ]] && echo 1400 || echo 900)
      sips -s format jpeg -s formatOptions 78 -Z "$size" "$f" --out "$dst/$(basename "${f%.png}").jpg" >/dev/null
    done
  done
done
du -sh docs/screenshots
