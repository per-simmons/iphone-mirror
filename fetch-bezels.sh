#!/bin/bash
# Downloads Apple's official iPhone 17 bezels (Apple Design Resources) into Resources/
# and builds the screen mask from them. Apple's license doesn't allow redistributing
# the images, so they aren't in this repo. Needs python3 with Pillow (pip3 install pillow).
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d); trap 'hdiutil detach "$TMP/mnt" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT
mkdir -p Resources
echo "Downloading Apple's iPhone 17 bezels (~265 MB)..."
curl -fL --progress-bar -o "$TMP/b.dmg" "https://devimages-cdn.apple.com/design/resources/download/Bezel-iPhone-17.dmg"
# The disk image shows a license prompt; answering it lets it mount.
{ yes || true; } | PAGER=cat hdiutil attach -nobrowse -readonly -mountpoint "$TMP/mnt" "$TMP/b.dmg" >/dev/null
for f in "iPhone 17 Pro/iPhone 17 Pro - Silver" "iPhone 17 Pro/iPhone 17 Pro - Deep Blue" \
         "iPhone 17 Pro/iPhone 17 Pro - Cosmic Orange" "iPhone 17/iPhone 17 - Black" "iPhone 17/iPhone 17 - White"; do
  n=$(basename "$f" | tr 'A-Z ' 'a-z-' | sed 's/---/-/g')
  cp "$TMP/mnt/PNG/$f - Portrait.png" "Resources/$n.png"
done
python3 - <<'PY'
import collections
from PIL import Image, ImageFilter
im = Image.open("Resources/iphone-17-black.png").convert("RGBA"); w, h = im.size; a = im.split()[3].load()
m = Image.new("L", (w, h), 0); mp = m.load(); q = collections.deque([(w // 2, h // 2)]); seen = set()
while q:  # flood-fill the transparent screen area from the center
    x, y = q.popleft()
    if (x, y) in seen or not (0 <= x < w and 0 <= y < h) or a[x, y] >= 250: continue
    seen.add((x, y)); mp[x, y] = 255; q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
# Grow a few px under the bezel so no hairline shows at the screen edge.
m = m.crop((72, 69, 72 + 1206, 69 + 2622)).filter(ImageFilter.MaxFilter(13))
out = Image.new("RGBA", m.size, (0, 0, 0, 0)); out.putalpha(m); out.save("Resources/screen-mask.png")
PY
echo "Bezels ready in Resources/"
