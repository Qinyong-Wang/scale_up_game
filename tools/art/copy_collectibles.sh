#!/usr/bin/env bash
# Copy processed collectible icons from tools/art/runs/ into the game assets dir.
#
# generate.py writes each processed sprite to runs/collectible-<id>/<sanitized>.png
# where <sanitized> has underscores turned into dashes (process_asset.sanitize_slug).
# IconRegistry.collectible_icon(id) reads assets/sprites/ui/collectible/<id>.png, so we
# recover the real id (underscores) from the *run-dir* name (which keeps underscores).
#
# Per design/办公室与收藏系统设计.md §8. Run from repo root or anywhere:
#     tools/art/copy_collectibles.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
RUNS="$HERE/runs"
DEST="$REPO/assets/sprites/ui/collectible"

mkdir -p "$DEST"
copied=0
missing=()
for dir in "$RUNS"/collectible-*/; do
  [ -d "$dir" ] || continue
  base="$(basename "$dir")"        # collectible-genesis_coin_7
  id="${base#collectible-}"        # genesis_coin_7
  # The accepted sprite is the only PNG that isn't an intermediate.
  png="$(ls "$dir"*.png 2>/dev/null | grep -vE '/(raw|clean|flooded)\.png$' | head -1 || true)"
  if [ -z "$png" ]; then
    missing+=("$id")
    continue
  fi
  cp "$png" "$DEST/$id.png"
  copied=$((copied + 1))
done

echo "copied $copied collectible icons -> $DEST"
if [ "${#missing[@]}" -gt 0 ]; then
  echo "WARNING: no processed PNG for: ${missing[*]}" >&2
fi
