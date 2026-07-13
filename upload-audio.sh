#!/bin/bash
# Upload audio files from ./audio/ to R2 bucket via Wrangler.
# Usage: bash upload-audio.sh [--dry-run]

set -euo pipefail
cd "$(dirname "$0")"

DRY_RUN="${1:-}"
AUDIO_DIR="./audio"
R2_PREFIX="music"

if [ ! -d "$AUDIO_DIR" ]; then
    echo "No audio directory at $AUDIO_DIR"
    echo "Expected structure:"
    echo "  audio/"
    echo "    rufus-du-sol-mayan-warrior-burning-man-2024.opus"
    exit 1
fi

for file in "$AUDIO_DIR"/*.opus; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    key="$R2_PREFIX/$name"
    size=$(du -h "$file" | cut -f1)

    if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "[dry-run] $name → r2://vaked-audio/$key ($size)"
    else
        echo "Uploading $name ($size) → r2://vaked-audio/$key ..."
        (cd audio-edge && npx wrangler r2 object put "vaked-audio/$key" \
            --file "../$file" \
            --content-type "audio/ogg; codecs=opus" \
            --cache-control "public, max-age=31536000, immutable" \
            --remote)
    fi
done

echo ""
echo "Done. Verify: https://audio.vaked.dev/tracks"
