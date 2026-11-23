import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// What a symbol picker (Picker.qml) shows and does: its list, recents, search and paste.
// EmojiState and GlyphState each hold one. The list is a TSV from scripts/:
//   group <TAB> symbol <TAB> name <TAB> keywords [<TAB> footer text]
Scope {
    id: root
    required property string name    // IPC target (`qs -c bar ipc call <name> toggle`) and recents file
    required property string tsv     // under scripts/
    required property var groups     // [{ key, glyph, label }] in list order; the first is "Recent"
    property string noun: name
    property string font: "Noto Color Emoji"
    property bool tinted: false      // draw in the text colour (font glyphs) instead of their own
    property int size: 24
    property int cols: 9
    signal summoned()

    property var all: []        // [{ ch, name, group, words, sub }] in file order
    property var recent: []     // symbols, newest first

    IpcHandler {
        target: root.name
        function toggle(): void { root.summoned() }
    }

    FileView {
        path: Qt.resolvedUrl("../scripts/" + root.tsv).toString().replace("file://", "")
        onLoaded: root.all = text().split("\n").filter(l => l).map(l => {
            const [group, ch, name, kw, sub] = l.split("\t")
            return { ch, name, group, words: (name + " " + kw).toLowerCase(), sub: sub || kw || "" }
        })
    }

    FileView {
        id: recentFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + `/quickshell-${root.name}-recent.json`
        printErrors: false
        onLoaded: { try { root.recent = JSON.parse(text()) } catch (e) {} }
    }

    // Every word of the query has to start a word of the name or keywords. Order: the exact
    // name, then names holding the query as whole words, then names matching at all (both
    // shortest first, so "heart" gives ❤️ before 💘), then keyword-only hits in file order.
    function search(q) {
        const terms = q.toLowerCase().split(/\s+/).filter(t => t)
        if (!terms.length) return []
        const phrase = terms.join(" ")
        const rank = e => {
            const n = e.name.toLowerCase()
            if (n === phrase) return 0
            if ((" " + n + " ").includes(" " + phrase + " ")) return 1
            return terms.every(t => (" " + n).includes(" " + t)) ? 2 : 3
        }
        return all.filter(e => terms.every(t => (" " + e.words).includes(" " + t)))
            .map((e, i) => ({ e, i, r: rank(e) }))
            .sort((a, b) => a.r - b.r || (a.r < 3 ? a.e.name.length - b.e.name.length : 0) || a.i - b.i)
            .map(x => x.e)
    }

    // Copy it, and unless `copyOnly`, paste it into the focused window once the card has let go
    // of the keyboard (Hyprland's send_shortcut, so no wtype). Terminals paste with Ctrl+Shift+V.
    readonly property var terminals: ["kitty", "Alacritty", "foot", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "org.kde.konsole", "XTerm"]
    property string pasteMods: "CTRL"
    function pick(ch, copyOnly) {
        recent = [ch].concat(recent.filter(c => c !== ch)).slice(0, cols * 3)
        recentFile.setText(JSON.stringify(recent))
        Quickshell.execDetached(["wl-copy", "--", ch])
        if (copyOnly) return
        pasteMods = terminals.includes(Hyprland.activeToplevel?.lastIpcObject?.class ?? "") ? "CTRL SHIFT" : "CTRL"
        pasteT.restart()
    }
    Timer {
        id: pasteT
        interval: 150
        onTriggered: Quickshell.execDetached(["hyprctl", "dispatch",
            `hl.dsp.send_shortcut({ mods = "${root.pasteMods}", key = "V" })`])
    }
}
