pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colours: every one is a Settings value that is either "@name", one of HyDE's colour
// variables (read from the same files waybar's style.css imports, so theme switches still
// recolour the bar), or a fixed "#hex". The literals below are the fallbacks for a variable
// HyDE doesn't define (yet: the files load async).
Singleton {
    id: root

    // every HyDE @define-color, resolved: name -> color. "gtk-fg" is the GTK theme's text
    // colour (waybar's tray/power menus take theirs from it).
    property var defs: ({})
    property color gtkText: "#c0caf5"
    function color(spec, fallback) {
        if (typeof spec !== "string" || spec === "") return fallback
        if (!spec.startsWith("@")) return spec
        const k = spec.slice(1)
        return k === "gtk-fg" ? gtkText : (defs[k] ?? fallback)
    }
    function has(name) { return name === "gtk-fg" || defs[name] !== undefined }
    // the variables offered in the settings colour picker, in palette order
    readonly property var themeVars: ["bar-bg", "main-bg", "main-fg", "wb-act-bg", "wb-act-fg", "wb-hvr-bg", "wb-hvr-fg", "gtk-fg"]
    readonly property var paletteVars: [1, 2, 3, 4].map(n =>
        [`wallbash_pry${n}`, `wallbash_txt${n}`].concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(i => `wallbash_${n}xa${i}`)))

    property color barBg: color(Settings.themeBarBg, Qt.rgba(0, 0, 0, 0.1))
    property color mainBg: color(Settings.themeMainBg, "#24283b")
    property color mainFg: color(Settings.themeMainFg, "#7aa2f7")
    property color actBg: color(Settings.themeActBg, "#bb9af7")
    property color actFg: color(Settings.themeActFg, "#b4f9f8")
    property color hvrBg: color(Settings.themeHvrBg, "#7aa2f7")
    property color hvrFg: color(Settings.themeHvrFg, "#cfc9c2")
    property color menuFg: color(Settings.themeMenuFg, "#c0caf5")

    // global.css: JetBrainsMono Nerd Font 10px; border-radius.css: 10pt
    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 10
    readonly property real radius: 13.33

    function g(cp) { return String.fromCodePoint(cp) }

    FileView {
        id: wallbash
        path: Quickshell.env("HOME") + "/.cache/hyde/wallbash/gtk.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply()
    }
    // HyDE's wallbash renders the bar colours into ~/.config/waybar/theme.css from its
    // own templates (waybar.dcol / <theme>/waybar.theme), with or without waybar
    // installed, but skips the write if that directory is missing. Keep it around.
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/waybar"] }
    FileView {
        id: theme
        path: Quickshell.env("HOME") + "/.config/waybar/theme.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.apply(); gtkFg.running = true }
    }

    Process {
        id: gtkFg
        command: ["sh", "-c", `
            n=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
            for d in ~/.themes ~/.local/share/themes /usr/share/themes; do
                f="$d/$n/gtk-3.0/gtk.css"
                [ -f "$f" ] && grep -ohE '@define-color theme_fg_color [^;]+' "$f" | head -1 | cut -d' ' -f3 && break
            done`]
        stdout: StdioCollector { onStreamFinished: { const c = text.trim(); if (c) root.gtkText = c } }
    }

    function apply() {
        const defs = {}
        const re = /@define-color\s+([\w-]+)\s+([^;]+);/g
        for (const css of [wallbash.text(), theme.text()]) {
            let m
            while ((m = re.exec(css)) !== null) defs[m[1]] = m[2].trim()
        }
        const resolve = (v, depth) => {
            if (v === undefined || depth > 8) return undefined
            if (v.startsWith("@")) return resolve(defs[v.slice(1)], depth + 1)
            const rgba = v.match(/rgba?\(([^)]+)\)/)
            if (!rgba) return v
            const p = rgba[1].split(",").map(Number)
            return Qt.rgba(p[0] / 255, p[1] / 255, p[2] / 255, p.length > 3 ? p[3] : 1)
        }
        const out = {}
        for (const k in defs) { const c = resolve(defs[k], 0); if (c !== undefined) out[k] = c }
        root.defs = out
    }
}
