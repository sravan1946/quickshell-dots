#!/usr/bin/env bash
# Screenshots for Shot.qml and the instant binds. Saves where HyDE did, named the same way.
#   shot.sh freeze                 grab the focused monitor; print the file, then that monitor
#                                  and every window as one-line JSON
#   shot.sh crop FILE GEOM ACTION  GEOM = WxH+X+Y in device pixels of FILE;
#                                  ACTION = save (save + copy) | copy | edit (satty) | ocr (text → clipboard)
#   shot.sh full | monitor         instant: every monitor / the focused one, saved and copied
set -u
dir=${XDG_RUNTIME_DIR:-/tmp}/qs-shot
mkdir -p -m 700 "$dir"
pics=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots
mkdir -p "$pics"
name=$(date +'%y%m%d_%Hh%Mm%Ss_screenshot.png')

keep() {    # keep FILE: save it, copy it, say so with a thumbnail
    cp "$1" "$pics/$name" && wl-copy -t image/png <"$pics/$name"
    notify-send -a Screenshot -i "$pics/$name" "Screenshot saved and copied" "$name"
}
focused() { hyprctl monitors -j | jq -c '.[] | select(.focused)'; }

case ${1:-} in
freeze)
    find "$dir" -name '*.png' -mmin +10 -delete 2>/dev/null
    mon=$(focused)
    f=$dir/frozen-$(date +%s%N).png
    grim -o "$(jq -r .name <<<"$mon")" "$f" || exit 1
    echo "$f"
    echo "$mon"
    hyprctl clients -j | jq -c .
    ;;
crop)
    out=$dir/crop-$(date +%s%N).png
    magick "$2" -crop "$3" +repage "$out" || exit 1
    case $4 in
    save) keep "$out" ;;
    copy)
        wl-copy -t image/png <"$out"
        notify-send -a Screenshot -i "$out" "Screenshot copied"
        ;;
    edit) satty -f "$out" -o "$pics/$name" --copy-command wl-copy ;;
    ocr)
        txt=$(tesseract "$out" - -l eng 2>/dev/null | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
        if [ -n "${txt//[[:space:]]/}" ]; then
            printf '%s' "$txt" | wl-copy
            notify-send -a Screenshot "Text copied" "$(printf '%s' "$txt" | head -c 240)"
        else
            notify-send -a Screenshot "No text found" "Nothing readable in that area"
        fi
        ;;
    esac
    ;;
full) f=$dir/full-$(date +%s%N).png && grim "$f" && keep "$f" ;;
monitor) f=$dir/mon-$(date +%s%N).png && grim -o "$(focused | jq -r .name)" "$f" && keep "$f" ;;
*) echo "usage: $0 freeze | crop FILE GEOM save|copy|edit|ocr | full | monitor" >&2; exit 2 ;;
esac
