import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.islands

// Wallpaper picker for the current theme's wallpapers (`look walls` / `look wall`, ~/.local/bin/look
// in the dotfiles).
// A coverflow: the chosen wallpaper faces you, lit with the accent; the rest turn away and
// stack into the distance on both sides. Behind it, the chosen wallpaper fills the screen,
// blurred, and under it sits the palette matugen makes from it: the colours the desktop
// takes on if you set it. Opening fans the cards out from the middle, closing folds them back.
// ←/→ (h/l, Tab, wheel) browse, Enter or a click on the chosen card sets it (`look wall`, and
// matugen recolours everything), Esc or a click outside closes.
// `qs -c bar ipc call wallpaper toggle` (SUPER+SHIFT+W in hyprland.lua).
Scope {
    id: root

    property bool open: false
    property var walls: []            // [{ path, thumb, name, palette[8] }] for the current theme
    property string raw: ""           // last list output: an unchanged list isn't reassigned
    property string current: ""       // the wallpaper that's set now
    property int sel: 0
    property bool settled: false      // the list for this opening has arrived: moves animate from here on
    readonly property var cur: walls[sel] ?? null

    readonly property int cardW: 240
    readonly property int cardH: 380
    readonly property int reach: 228     // centre → first neighbour
    readonly property int stack: 74      // between the turned-away cards further out

    // one progress for the whole picker: opens on the spatial curve (overshoots), leaves on exit
    property real p: open ? 1 : 0
    Behavior on p { Anim { type: root.open ? "spatial" : "exit" } }
    readonly property real fade: Math.max(0, Math.min(1, p))

    // where the flow is, in cards: chases sel, so a jump of several cards sweeps through them
    property real pos: sel
    Behavior on pos { enabled: root.settled; Anim { type: "spatial" } }

    function step(d) { if (walls.length) sel = (sel + d + walls.length) % walls.length }
    function apply() {
        if (!cur) return
        current = cur.path
        open = false
        Quickshell.execDetached(["env", "LOOK_POS=" + backdrop.growFrom, "look", "wall", cur.path])
    }

    onOpenChanged: {
        if (!open) return
        settled = false
        list.running = true
        keys.forceActiveFocus()
    }

    // the list loads at startup and again whenever matugen recolours (a new wallpaper or
    // theme), so the cards are decoded before the picker opens; opening re-checks it too
    Component.onCompleted: list.running = true
    Connections {
        target: Look
        function onAccentChanged() { refresh.restart() }
    }
    Timer { id: refresh; interval: 1500; onTriggered: if (!root.open) list.running = true }

    Process {
        id: list
        command: ["sh", "-c", 'readlink -f "${XDG_STATE_HOME:-$HOME/.local/state}/look/wall"; look walls']
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n")
                root.current = text.slice(0, nl)
                const body = text.slice(nl + 1)
                if (body !== root.raw) {
                    root.raw = body
                    let arr = []
                    try { arr = JSON.parse(body) } catch (e) {}
                    root.walls = arr.map(w => ({
                        path: w.path,
                        name: w.path.replace(/^.*\//, "").replace(/\.[^.]+$/, "").replace(/[_-]+/g, " "),
                        thumb: w.thumb,
                        palette: w.palette
                    }))
                }
                root.sel = Math.max(0, root.walls.findIndex(w => w.path === root.current))
                Qt.callLater(() => root.settled = true)
            }
        }
    }

    // the chosen wallpaper's palette (surface, primary, secondary, tertiary, containers, on_surface)
    readonly property var palette: root.cur?.palette ?? []

    IpcHandler {
        target: "wallpaper"
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
        WlrLayershell.namespace: "wallpicker"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // the chosen wallpaper, full screen and blurred (decoded small, see PickerBackdrop)
        PickerBackdrop {
            id: backdrop
            anchors.fill: parent
            opacity: root.fade
            source: root.cur ? (root.cur.thumb || root.cur.path) : ""
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
                else if (e.key === Qt.Key_End) root.sel = Math.max(0, root.walls.length - 1)
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

        // ---------------- the flow ----------------
        Item {
            id: stage
            width: parent.width
            height: root.cardH + 60
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -40
            opacity: root.fade

            Repeater {
                model: root.walls
                Item {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property real d: index - root.pos          // cards from the centre, fractional mid-move
                    readonly property real ad: Math.abs(d)
                    readonly property real near: Math.min(ad, 1)          // 0 facing you … 1 turned away
                    readonly property real far: Math.max(ad - 1, 0)
                    readonly property bool chosen: index === root.sel
                    readonly property bool isSet: modelData.path === root.current

                    width: root.cardW
                    height: root.cardH
                    x: Math.round(stage.width / 2 - width / 2 + Math.sign(d) * (near * root.reach + far * root.stack) * root.p)
                    y: (stage.height - height) / 2
                    z: 100 - ad
                    scale: 1 - 0.14 * near - 0.05 * far
                    opacity: Math.max(0, Math.min(1, 4.6 - ad))
                    visible: opacity > 0
                    transform: Rotation {
                        origin.x: card.width / 2
                        origin.y: card.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: -Math.sign(card.d) * 52 * card.near
                    }

                    // the chosen card glows in the accent
                    RectangularShadow {
                        anchors.fill: frame
                        radius: frame.radius
                        blur: 46
                        spread: 2
                        color: Qt.alpha(Look.accent, 0.55)
                        opacity: 1 - card.near
                        visible: opacity > 0.01
                        cached: true
                    }
                    ClippingRectangle {
                        id: frame
                        anchors.fill: parent
                        radius: 20
                        color: Look.surface

                        Image {
                            id: img
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            // look's cached thumbnail (the original if it has none yet)
                            sourceSize: Qt.size(root.cardW * 2, root.cardH * 2)
                            source: "file://" + (card.modelData.thumb || card.modelData.path)
                        }
                        // turned-away cards fall into shade, deeper the further out they are
                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                            opacity: Math.min(0.62, 0.38 * card.near + 0.08 * card.far)
                        }
                        // a sheen across the facing card
                        Rectangle {
                            anchors.fill: parent
                            opacity: 1 - card.near
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.alpha("white", 0.10) }
                                GradientStop { position: 0.45; color: "transparent" }
                            }
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
                    // the wallpaper that's on now
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

        // ---------------- name, palette, keys ----------------
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: stage.bottom
            anchors.topMargin: 14
            spacing: 14
            opacity: root.fade
            transform: Translate { y: (1 - root.p) * 24 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.cur?.name ?? ""
                color: Look.text
                font { family: Look.sans; pixelSize: 22; weight: Font.DemiBold; capitalization: Font.Capitalize }
            }
            // the palette this wallpaper gives the desktop
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: 8
                    Rectangle {
                        required property int index
                        width: index % 2 ? 14 : 26
                        height: 14
                        radius: 7
                        color: root.palette[index] ?? "transparent"
                        border.width: 1
                        border.color: Qt.alpha("white", 0.12)
                        Behavior on color { ColorAnimation { duration: Look.ms("enter"); easing.type: Easing.BezierSpline; easing.bezierCurve: Look.curves.enter } }
                    }
                }
            }
            // position dots, then the keys
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                Repeater {
                    model: root.walls.length
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
                text: "←  →  browse     ⏎  set     esc  close"
                color: Look.faint
                font { family: Look.sans; pixelSize: Look.small }
            }
        }
    }
}
