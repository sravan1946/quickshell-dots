pragma Singleton
import QtQuick
import Quickshell
import qs

// Everything the island bar looks and moves like: colours (from HyDE's wallbash palette, so
// theme switches recolour it), type, geometry and the motion tokens (CRAFT.md rule 5).
// No module writes a colour, a duration or a curve of its own.
Singleton {
    // ---- colour ----
    readonly property color accent: Theme.color("@wallbash_1xa8", "#AAAAF0")
    readonly property color accentInk: Theme.color("@wallbash_1xa1", "#292952")
    // (the cover's colours, Player.c1/c2, are only for the music's own light: the visualizer,
    // the glow under the media item and its progress filament)
    readonly property color rim: Qt.alpha("white", 0.06)
    readonly property color base: Theme.color("@wallbash_pry1", "#2A2A3A")
    readonly property color surface: Qt.rgba(base.r * 0.38, base.g * 0.38, base.b * 0.43, 0.88)
    readonly property color text: "#ececf6"
    readonly property color dim: Qt.alpha(text, 0.58)
    readonly property color faint: Qt.alpha(text, 0.32)
    readonly property color hover: Qt.alpha("white", 0.08)
    readonly property color raise: Qt.alpha("white", 0.06)
    readonly property color line: Qt.alpha("white", 0.08)
    readonly property color warm: "#F1D9C2"
    readonly property color urgent: "#e0af68"
    readonly property color alert: "#f7768e"
    readonly property color good: "#9ece6a"
    readonly property color down: Theme.color(Settings.netColDown, "#99ffdd")
    readonly property color up: Theme.color(Settings.netColUp, warm)
    readonly property color cpu: Theme.color(Settings.sysColCpu, accent)
    readonly property color ram: Theme.color(Settings.sysColRam, "#bb9af7")

    // ---- type ----
    readonly property string sans: "Adwaita Sans"
    readonly property string icons: "JetBrainsMono Nerd Font"
    readonly property int size: 12           // panels
    readonly property int barText: 11        // the bar itself
    readonly property int small: 11
    function g(cp) { return String.fromCodePoint(cp) }

    // ---- geometry ----
    readonly property int top: 4             // islands' distance from the screen edge
    readonly property int h: 26              // island height
    readonly property int item: 22           // an item inside an island
    readonly property int edge: 8            // left/right screen margin
    readonly property int reserve: top + h + 2   // what windows keep clear of

    // ---- motion (CRAFT.md rule 5): one table, one speed knob ----
    property real speed: 1                   // `qs -c bar ipc call islands slow 4` for checking motion
    readonly property var curves: ({
        spatial: [0.38, 1.21, 0.22, 1.00, 1, 1],
        fast: [0.42, 1.67, 0.21, 0.90, 1, 1],
        effects: [0.34, 0.80, 0.34, 1.00, 1, 1],
        enter: [0.05, 0.70, 0.10, 1.00, 1, 1],
        exit: [0.30, 0.00, 0.80, 0.15, 1, 1]
    })
    readonly property var times: ({ spatial: 500, fast: 350, effects: 200, enter: 400, exit: 200 })
    function ms(type) { return (times[type] ?? 200) * speed }
}
