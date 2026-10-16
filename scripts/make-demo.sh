#!/bin/bash
# Renders the README animations from the demo clips into docs/images/demo-dark.gif and demo-light.gif.
# Needs ffmpeg and a build from scripts/build.sh. Nothing is read from or written to your clipboard.
set -euo pipefail
cd "$(dirname "$0")/.."
width="${1:-620}"
frames="$(mktemp -d)"
trap 'rm -rf "$frames"' EXIT
dist/Stowia.app/Contents/MacOS/Stowia -AppleLanguages '(en)' --capture-demo "$frames"
mkdir -p docs/images
for appearance in dark light; do
    ffmpeg -loglevel error -y -f concat -i "$frames/$appearance/frames.txt" \
        -vf "scale=$width:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a" \
        -fps_mode vfr -loop 0 "docs/images/demo-$appearance.gif"
done
ls -lh docs/images/demo-*.gif
