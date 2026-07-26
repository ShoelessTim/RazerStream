#!/bin/zsh
# Downloads permissively licensed icon packs into dist/IconPacks for bundling.
# Run once; make_app.sh copies the result into the app's Resources.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/IconPacks"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

mkdir -p "$OUT"

# Lucide; MIT licensed, stroke style general purpose icons
if [ ! -d "$OUT/Lucide" ]; then
    echo "Fetching Lucide…"
    curl -sL "https://github.com/lucide-icons/lucide/archive/refs/heads/main.tar.gz" -o "$TMP/lucide.tgz"
    mkdir -p "$TMP/lucide"
    tar -xzf "$TMP/lucide.tgz" -C "$TMP/lucide" --strip-components=1
    mkdir -p "$OUT/Lucide"
    cp "$TMP/lucide/icons/"*.svg "$OUT/Lucide/"
    cp "$TMP/lucide/LICENSE" "$OUT/Lucide/LICENSE"
    echo "Lucide: $(ls "$OUT/Lucide" | grep -c '\.svg$') icons"
fi

# Bootstrap Icons; MIT licensed, filled and outline UI icons
if [ ! -d "$OUT/Bootstrap" ]; then
    echo "Fetching Bootstrap Icons…"
    curl -sL "https://github.com/twbs/icons/archive/refs/heads/main.tar.gz" -o "$TMP/bootstrap.tgz"
    mkdir -p "$TMP/bootstrap"
    tar -xzf "$TMP/bootstrap.tgz" -C "$TMP/bootstrap" --strip-components=1
    mkdir -p "$OUT/Bootstrap"
    cp "$TMP/bootstrap/icons/"*.svg "$OUT/Bootstrap/"
    cp "$TMP/bootstrap/LICENSE" "$OUT/Bootstrap/LICENSE"
    echo "Bootstrap: $(ls "$OUT/Bootstrap" | grep -c '\.svg$') icons"
fi

# Simple Icons; CC0, brand and service logos. The most useful addition for a
# stream deck specifically: Discord, Twitch, Spotify, OBS and friends, which
# the general purpose sets deliberately do not carry.
if [ ! -d "$OUT/Simple Icons" ]; then
    echo "Fetching Simple Icons…"
    curl -sL "https://github.com/simple-icons/simple-icons/archive/refs/heads/master.tar.gz" -o "$TMP/simple.tgz"
    mkdir -p "$TMP/simple"
    tar -xzf "$TMP/simple.tgz" -C "$TMP/simple" --strip-components=1
    mkdir -p "$OUT/Simple Icons"
    cp "$TMP/simple/icons/"*.svg "$OUT/Simple Icons/"
    cp "$TMP/simple/LICENSE.md" "$OUT/Simple Icons/LICENSE"
    echo "Simple Icons: $(ls "$OUT/Simple Icons" | grep -c '\.svg$') icons"
fi

# Tabler; MIT, a large general purpose outline set. Only the outline weight is
# taken: the filled weight reuses the same filenames, so both cannot live in
# one flat pack folder without colliding.
if [ ! -d "$OUT/Tabler" ]; then
    echo "Fetching Tabler…"
    curl -sL "https://github.com/tabler/tabler-icons/archive/refs/heads/main.tar.gz" -o "$TMP/tabler.tgz"
    mkdir -p "$TMP/tabler"
    tar -xzf "$TMP/tabler.tgz" -C "$TMP/tabler" --strip-components=1
    mkdir -p "$OUT/Tabler"
    cp "$TMP/tabler/icons/outline/"*.svg "$OUT/Tabler/"
    cp "$TMP/tabler/LICENSE" "$OUT/Tabler/LICENSE"
    echo "Tabler: $(ls "$OUT/Tabler" | grep -c '\.svg$') icons"
fi

echo "Icon packs ready in $OUT"
du -sh "$OUT" 2>/dev/null | awk '{print "Total bundled icon size: " $1}'
