pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colours: every one is a Settings value that is either "@name", a colour matugen makes from the
// wallpaper (~/.local/state/look/colors.css, from the dotfiles' matugen/templates/bar.css, so a new
// wallpaper or theme recolours the bar), or a fixed "#hex". The literals below are the fallbacks for
// a name it doesn't define (yet: the file loads async).
Singleton {
    id: root

    // every @define-color in colors.css, resolved: name -> color. "gtk-fg" is the GTK theme's
    // text colour.
    property var defs: ({})
    property color gtkText: "#c0caf5"
    function color(spec, fallback) {
        if (typeof spec !== "string" || spec === "") return fallback
        if (!spec.startsWith("@")) return spec
        const k = spec.slice(1)
        return k === "gtk-fg" ? gtkText : (defs[k] ?? fallback)
    }
    function has(name) { return name === "gtk-fg" || defs[name] !== undefined }

    property color barBg: color("@bar-bg", Qt.rgba(0, 0, 0, 0.1))
    property color mainBg: color(Settings.themeMainBg, "#24283b")
    property color mainFg: color(Settings.themeMainFg, "#7aa2f7")
    property color actBg: color(Settings.themeActBg, "#bb9af7")
    property color actFg: color(Settings.themeActFg, "#b4f9f8")
    property color hvrBg: color(Settings.themeHvrBg, "#7aa2f7")
    property color hvrFg: color(Settings.themeHvrFg, "#cfc9c2")
    property color menuFg: color("@gtk-fg", "#c0caf5")

    // global.css: JetBrainsMono Nerd Font 10px; border-radius.css: 10pt
    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 10
    readonly property real radius: 13.33

    function g(cp) { return String.fromCodePoint(cp) }

    FileView {
        id: colors
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/look/colors.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.apply(); gtkFg.running = true }
        onLoadFailed: retry.start()   // not made yet (before the first `look wall`)
    }
    Timer { id: retry; interval: 3000; onTriggered: colors.reload() }
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
        for (const css of [colors.text()]) {
            let m
            while ((m = re.exec(css)) !== null) defs[m[1]] = m[2].trim()
        }
        // matugen rewrites the file in place: a read mid-write sees it empty or cut short. Keep
        // the colours we have until a complete one arrives (no flash of the fallbacks).
        if (Object.keys(defs).length < Object.keys(root.defs).length || !Object.keys(defs).length) return
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
