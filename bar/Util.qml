pragma Singleton
import QtQuick
import Quickshell

Singleton {
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }

    // Bluetooth sinks carry no form factor; ponytail: a BT speaker gets the headphone icon too
    function headphones(sink) { return /head(phone|set)/i.test(sink?.description ?? "") || (sink?.name ?? "").startsWith("bluez_output") }

    // waybar getIcon(): index = value / (100 / n), clamped; icons are codepoints
    function pick(icons, pct) {
        const i = Math.floor(pct / Math.max(1, Math.floor(100 / icons.length)))
        return String.fromCodePoint(icons[Math.max(0, Math.min(icons.length - 1, i))])
    }
    // battery-outline, battery-10 … battery-90, battery: for pick()
    readonly property var batteryIcons: [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]

    // one `nmcli -t` line split into fields; nmcli escapes ":" inside values as "\\:"
    // (no regex lookbehind in Qt's JS)
    function nmFields(line) { return line.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":")) }

    // Icon-theme file lookup for `sh -c findIcon sh <name> <extra dir> <size dirs>`: the extra
    // dir first, then the theme, its Inherits chain and hicolor, trying the size dirs in order
    // (e.g. "16 16x16" for panel glyphs, "scalable 256x256 128x128 64x64 48x48" for apps).
    // Prints a path, or nothing. Loading the file ourselves lets the Image rasterise it at the
    // bar's real device size; Quickshell's image://icon provider renders at Qt's app-wide
    // scale (2 here, rounded up from 1.5) and the result gets shrunk, blurry at 1.5x and 1x.
    readonly property string findIcon: `
        name="$1"; extra="$2"; sizes="\${3:-16 16x16}"
        case $name in /*) [ -f "$name" ] && echo "$name"; exit;; esac
        for e in svg png; do [ -n "$extra" ] && [ -f "$extra/$name.$e" ] && { echo "$extra/$name.$e"; exit; }; done
        theme=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
        bases="$HOME/.local/share/icons $HOME/.icons /usr/share/icons"
        themes="$theme"
        for b in $bases; do
            [ -f "$b/$theme/index.theme" ] && themes="$theme $(sed -n 's/^Inherits=//p' "$b/$theme/index.theme" | tr ',' ' ')" && break
        done
        for t in $themes hicolor; do for d in $sizes; do for b in $bases; do
            for f in "$b/$t/$d"/*/"$name".svg "$b/$t/$d"/*/"$name".png; do [ -f "$f" ] && { echo "$f"; exit; }; done
        done; done; done
        [ -f "/usr/share/pixmaps/$name.svg" ] && echo "/usr/share/pixmaps/$name.svg" || { [ -f "/usr/share/pixmaps/$name.png" ] && echo "/usr/share/pixmaps/$name.png"; }`
}
