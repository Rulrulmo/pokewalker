#!/bin/sh
# server/guide.sh [<git ref>] — the guide's pictures (GET /guide, server/README.md) on the server, run on the server. Default ref: origin/main.
#   docs/guide/ of that commit — img/ (the Mac's app renders; PNG → lossless WebP, python3-pil) and README.md (their captions) — into GUIDE_DIR at once,
#   as the pokewalker user (sudo). No restart: the guide reads the folder on each request. A picture's section is its name's first two digits.
set -eu
cd "$(dirname "$0")/.."
DIR=${GUIDE_DIR:-/var/lib/pokewalker/guide}
SUDO="sudo -u pokewalker"

git fetch -q origin
REF=${1:-origin/main}
COMMIT=$(git rev-parse --short "$REF^{commit}")
IN=$(mktemp -d); trap 'rm -rf "$IN"' EXIT
chmod 755 "$IN"                                                        # the pokewalker user copies from it
git archive "$COMMIT" docs/guide | tar -x -C "$IN" 2>/dev/null || { echo "$COMMIT: no docs/guide"; exit 1; }
mkdir -p "$IN/out/img" "$IN/docs/guide/img"
[ ! -f "$IN/docs/guide/README.md" ] || cp "$IN/docs/guide/README.md" "$IN/out/"
python3 - "$IN/docs/guide/img" "$IN/out/img" <<'EOF'
import sys, pathlib, shutil
from PIL import Image
src, dst = map(pathlib.Path, sys.argv[1:])
for p in sorted(src.iterdir()):
    ext = p.suffix.lower()
    if ext == ".png": Image.open(p).save(dst / (p.stem + ".webp"), lossless=True, method=6)
    elif ext in (".webp", ".jpg", ".jpeg"): shutil.copyfile(p, dst / p.name)
EOF
echo "$COMMIT" > "$IN/out/commit"
find "$IN/out" -type d -exec chmod 755 {} +; find "$IN/out" -type f -exec chmod 644 {} +

# in place at once: a new folder renamed over the old one
$SUDO sh -c "rm -rf '$DIR.new' '$DIR.old' && mkdir -p '$DIR.new' && cp -R '$IN/out'/. '$DIR.new/' && { [ ! -d '$DIR' ] || mv '$DIR' '$DIR.old'; } && mv '$DIR.new' '$DIR' && rm -rf '$DIR.old'"
echo "guide: $(ls "$IN/out/img" | wc -l) pictures ($(du -sh "$IN/out/img" | cut -f1)) from $COMMIT → https://pokewalker.rulrulmo.work/guide"
