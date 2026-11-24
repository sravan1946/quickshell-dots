import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.islands

// Theme picker (`look themes` / `look theme`, ~/.local/bin/look in the dotfiles).
// The themes are a hand of cards fanned along an arc: the chosen one rises out of the fan,
// straightens and glows; the rest tilt away along the curve. Each card is the theme's own
// wallpaper with its name and the palette matugen makes from it. Behind, the chosen theme's
// wallpaper fills the screen, blurred. Opening deals the fan out of a stacked deck, closing
// gathers it back.
// ←/→ (h/l, Tab, wheel) browse, Enter or a click on the chosen card switches theme
// (`look theme <name>`), Esc or a click outside closes.
// `qs -c bar ipc call theme toggle|open|close|next|prev|set` (SUPER+SHIFT+T in hyprland.lua).
Scope {
    id: root

    property bool open: false
    property var themes: []           // [{ name, wall, thumb, colors[8] }] from `look themes`
    property string raw: ""
    property string current: ""
    property int sel: 0
    property bool settled: false
    readonly property var cur: themes[sel] ?? null

    readonly property int cardW: 196
    readonly property int cardH: 300
    readonly property real spread: 8.5     // degrees between neighbouring cards
    readonly property int radius: 1150     // of the arc the cards sit on
    readonly property int lift: 54         // how far the chosen card rises out of the fan

    property real p: open ? 1 : 0
    Behavior on p { Anim { type: root.open ? "spatial" : "exit" } }
    readonly property real fade: Math.max(0, Math.min(1, p))

    property real pos: sel
    Behavior on pos { enabled: root.settled; Anim { type: "spatial" } }

    function step(d) { if (themes.length) sel = (sel + d + themes.length) % themes.length }
    function apply() {
        if (!cur) return
        open = false
        if (cur.name === current) return
        current = cur.name
        Quickshell.execDetached(["env", "LOOK_POS=" + backdrop.growFrom, "look", "theme", cur.name])
    }

    onOpenChanged: {
        if (!open) return
        settled = false
        list.running = true
        keys.forceActiveFocus()
    }
    Component.onCompleted: list.running = true
    Connections {
        target: Look
        function onAccentChanged() { refresh.restart() }
    }
    Timer { id: refresh; interval: 1500; onTriggered: if (!root.open) list.running = true }

    Process {
        id: list
        command: ["sh", "-c", 'cat "${XDG_STATE_HOME:-$HOME/.local/state}/look/theme"; look themes']
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n")
                root.current = text.slice(0, nl)
                const body = text.slice(nl + 1)
                if (body !== root.raw) {
                    root.raw = body
                    root.themes = body.split("\n").filter(l => l).map(l => {
                        const f = l.split("\t")
                        return { name: f[0], wall: f[1], thumb: f[3] ?? "", colors: (f[2] ?? "").split(",") }
                    })
                }
                root.sel = Math.max(0, root.themes.findIndex(t => t.name === root.current))
                Qt.callLater(() => root.settled = true)
            }
        }
    }

    IpcHandler {
        target: "theme"
        function toggle(): void { root.open = !root.open }
        function open(): void { root.open = true }
        function close(): void { root.open = false }
        function next(): void { root.step(1) }
        function prev(): void { root.step(-1) }
        function set(): void { if (root.open) root.apply() }
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: root.open || root.p > 0.001
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "themepicker"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        PickerBackdrop {
            id: backdrop
            anchors.fill: parent
            opacity: root.fade
            source: root.cur ? (root.cur.thumb || root.cur.wall) : ""
            onDismissed: root.open = false
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                e.accepted = true
                if (e.key === Qt.Key_Escape) root.open = false
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_L || e.key === Qt.Key_Tab) root.step(1)
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_H || e.key === Qt.Key_Backtab) root.step(-1)
                else if (e.key === Qt.Key_Home) root.sel = 0
                else if (e.key === Qt.Key_End) root.sel = Math.max(0, root.themes.length - 1)
                else if (!e.isAutoRepeat && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)) root.apply()
                else e.accepted = false
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real acc: 0
            onWheel: e => {
                acc += (e.angleDelta.y || -e.angleDelta.x)
                while (Math.abs(acc) >= 120) { root.step(acc > 0 ? -1 : 1); acc -= 120 * Math.sign(acc) }
            }
        }

        // ---------------- the fan ----------------
        Item {
            id: hand
            anchors.fill: parent
            opacity: root.fade
            // the chosen card's resting centre; the arc's pivot sits `radius` below it
            readonly property real cx: width / 2
            readonly property real cy: height * 0.44

            Repeater {
                model: root.themes
                Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property real d: index - root.pos
                    readonly property real ad: Math.abs(d)
                    readonly property real near: Math.min(ad, 1)
                    readonly property bool chosen: index === root.sel
                    readonly property bool isSet: modelData.name === root.current
                    // dealt from the deck: the fan's angles grow with the open progress
                    readonly property real deg: d * root.spread * root.p
                    readonly property real rad: deg * Math.PI / 180

                    width: root.cardW
                    height: root.cardH
                    x: Math.round(hand.cx + root.radius * Math.sin(rad) - width / 2)
                    y: Math.round(hand.cy + root.radius * (1 - Math.cos(rad)) - height / 2
                                  - root.lift * (1 - near) + (1 - root.p) * 90)
                    rotation: deg
                    z: 100 - ad
                    scale: 1 - 0.1 * near
                    opacity: Math.max(0, Math.min(1, 6.5 - ad))
                    visible: opacity > 0

                    RectangularShadow {
                        anchors.fill: frame
                        radius: frame.radius
                        blur: 26 + 24 * (1 - card.near)
                        spread: 0
                        offset.y: 10
                        color: Qt.alpha(card.chosen ? Look.accent : "black", card.chosen ? 0.55 : 0.5)
                        cached: true
                    }
                    ClippingRectangle {
                        id: frame
                        anchors.fill: parent
                        radius: 18
                        color: card.modelData.colors[0] || Look.surface

                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            // look's cached thumbnail (the original if it has none yet)
                            sourceSize: Qt.size(root.cardW * 2, root.cardH * 2)
                            source: (card.modelData.thumb || card.modelData.wall) ? "file://" + (card.modelData.thumb || card.modelData.wall) : ""
                        }
                        // the card's foot: the theme's background colour rising into the picture
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.45; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.alpha(card.modelData.colors[0] || "black", 0.96) }
                            }
                        }
                        Column {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                            spacing: 8
                            Text {
                                width: parent.width
                                text: card.modelData.name
                                elide: Text.ElideRight
                                color: card.modelData.colors[7] || Look.text
                                font { family: Look.sans; pixelSize: 15; weight: Font.DemiBold }
                            }
                            Row {
                                spacing: 4
                                Repeater {
                                    model: 6
                                    Rectangle {
                                        required property int index
                                        width: 14
                                        height: 6
                                        radius: 3
                                        color: card.modelData.colors[index + 1] || "transparent"
                                    }
                                }
                            }
                        }
                        // the fanned-out cards sink into shade
                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: 0.3 * card.near
                        }
                    }
                    Rectangle {
                        anchors.fill: frame
                        radius: frame.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.alpha(Look.accent, 0.9)
                        opacity: 1 - card.near
                    }
                    Rectangle {
                        visible: card.isSet
                        x: 12
                        y: 12
                        width: setRow.implicitWidth + 18
                        height: 22
                        radius: 11
                        color: Qt.alpha(Look.accent, 0.92)
                        Row {
                            id: setRow
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle { width: 6; height: 6; radius: 3; color: Look.accentInk; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: "current"
                                color: Look.accentInk
                                font { family: Look.sans; pixelSize: Look.small; weight: Font.DemiBold }
                            }
                        }
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: card.chosen ? root.apply() : root.sel = card.index
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
        }

        // ---------------- name, dots, keys ----------------
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(hand.cy + root.cardH / 2 + 46)
            spacing: 12
            opacity: root.fade
            transform: Translate { y: (1 - root.p) * 24 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.cur?.name ?? ""
                color: Look.text
                font { family: Look.sans; pixelSize: 24; weight: Font.DemiBold }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                Repeater {
                    model: root.themes.length
                    Rectangle {
                        required property int index
                        readonly property bool on: index === root.sel
                        width: on ? 18 : 6
                        height: 6
                        radius: 3
                        color: on ? Look.accent : Look.faint
                        Behavior on width { Anim { type: "fast" } }
                        Behavior on color { ColorAnimation { duration: Look.ms("effects") } }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "←  →  browse     ⏎  switch     esc  close"
                color: Look.faint
                font { family: Look.sans; pixelSize: Look.small }
            }
        }
    }
}
