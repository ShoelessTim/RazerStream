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

echo "Icon packs ready in $OUT"
