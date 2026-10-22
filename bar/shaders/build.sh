#!/bin/sh
# Qt 6 only loads precompiled shaders; recompile after editing a .frag. Qt also caches shaders
# by URL across reloads, so each QML `foo.frag.qsb?v=…` is stamped with the new .qsb's hash.
cd "$(dirname "$0")" || exit 1
for f in *.frag; do
    /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$f.qsb" "$f" || exit 1
    h=$(sha1sum "$f.qsb" | cut -c1-8)
    grep -rl --include='*.qml' "$f.qsb?v=" .. | while read -r q; do
        grep -q "$f.qsb?v=$h\"" "$q" || sed -i "s/$f\.qsb?v=[0-9a-z]*/$f.qsb?v=$h/" "$q"
    done
done
