#!/usr/bin/env bash
# One line per HyDE theme for ThemePicker.qml, in HyDE's own order (.sort, then name):
#   name <TAB> wallpaper <TAB> thumbnail <TAB> bg,color1..color6,fg from the theme's kitty.theme
# The thumbnail is HyDE's cached one for the theme's current wallpaper (sha1 of the file).
themes=${XDG_CONFIG_HOME:-$HOME/.config}/hyde/themes
thumbs=${XDG_CACHE_HOME:-$HOME/.cache}/hyde/thumbs

for t in "$themes"/*/; do
    t=${t%/}
    printf '%s\t%s\n' "$(cat "$t/.sort" 2>/dev/null || echo 99)" "${t##*/}"
done | sort -t$'\t' -k1,1n -k2,2 | while IFS=$'\t' read -r _ name; do
    t=$themes/$name
    wall=$(readlink -f "$t/wall.set" 2>/dev/null)
    [ -f "$wall" ] || wall=$(find "$t/wallpapers" -maxdepth 1 -type f 2>/dev/null | sort | head -1)
    thumb=""
    [ -n "$wall" ] && thumb=$thumbs/$(sha1sum "$wall" | cut -d' ' -f1).thmb
    cols=$(awk '$1 ~ /^(background|foreground|color[1-6])$/ { c[$1] = $2 }
        END { printf "%s,%s,%s,%s,%s,%s,%s,%s", c["background"], c["color1"], c["color2"], c["color3"],
              c["color4"], c["color5"], c["color6"], c["foreground"] }' "$t/kitty.theme" 2>/dev/null)
    printf '%s\t%s\t%s\t%s\n' "$name" "$wall" "$thumb" "$cols"
done
