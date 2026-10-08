import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.components

// Power menu, in place of HyDE's wlogout (logoutlaunch.sh). The focused monitor blurs and dims
// (layer rule "powermenu" in hyprland.lua), a big clock with the date and uptime fades up, and a
// pill of actions pours out under it (components/LiquidCard). One accent blob marks the
// choice and slides between actions like a drop of liquid; its name and how to run it show below.
// Lock and Suspend run on a click or Enter. Log out, Reboot and Shut down have to be held
// (mouse, Enter or their letter): a ring fills round the blob and the screen darkens, and letting
// go early cancels, so a stray key or click can't end the session.
// Arrows/Tab move, a letter picks its action, Escape or a click outside closes.
// Opened by the quick-settings power button (Config.togglePower) or
// `qs -c bar ipc call power toggle` (CTRL+ALT+DELETE in hyprland.lua).
// Hibernate is left out: there is no swap to resume from (logind CanHibernate = na).
Scope {
    id: root

    property bool open: false
    property int sel: 0
    property real hold: 0        // 0..1 while a destructive action is held
    readonly property var actions: [
        { label: "Lock",      key: "l", icon: 0xF0341, cmd: "hyde-shell lockscreen.sh" },
        { label: "Suspend",   key: "s", icon: 0xF04B2, cmd: "systemctl suspend" },   // hypridle's before_sleep_cmd locks
        { label: "Log out",   key: "e", icon: 0xF0343, cmd: "hyde-shell logout", hold: true },
        { label: "Reboot",    key: "r", icon: 0xF0709, cmd: "systemctl reboot", hold: true },
        { label: "Shut down", key: "p", icon: 0xF0425, cmd: "systemctl poweroff", hold: true },
    ]
    readonly property var cur: actions[sel]

    function run(i) { open = false; Util.run(actions[i].cmd) }
    // press: instant actions run, held ones start filling. release: an unfinished hold drains back
    function press(i) {
        sel = i
        if (!actions[i].hold) return run(i)
        unhold.stop()
        holdAnim.restart()
    }
    function release() {
        if (!holdAnim.running) return
        holdAnim.stop()
        unhold.restart()
    }
    NumberAnimation { id: holdAnim; target: root; property: "hold"; to: 1; duration: 800; onFinished: root.run(root.sel) }
    NumberAnimation { id: unhold; target: root; property: "hold"; to: 0; duration: 220; easing.type: Easing.OutCubic }

    property string uptime: ""
    Process {
        id: up
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = Math.floor(parseFloat(text) / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
                root.uptime = d ? `${d}d ${h % 24}h` : h ? `${h}h ${m % 60}m` : `${m}m`
            }
        }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    onOpenChanged: {
        holdAnim.stop()
        hold = 0
        if (open) {
            sel = 0
            up.running = true
            keys.forceActiveFocus()   // the layer surface gets the keyboard each time; the item has to take it again
            card.pour(Qt.point(card.x + card.width / 2, card.y + card.height / 2))
        } else card.drain(Qt.point(card.x + card.width / 2, card.y + card.height / 2))
    }

    IpcHandler {
        target: "power"
        function toggle(): void { root.open = !root.open }
    }
    Connections {
        target: Config
        function onTogglePower() { root.open = !root.open }
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: root.open || shade.opacity > 0 || card.visible
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "powermenu"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // dim, deeper at the top and bottom, darkening further while an action is held
        Rectangle {
            id: shade
            anchors.fill: parent
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Theme.mainBg, 0.75 + 0.2 * root.hold) }
                GradientStop { position: 0.5; color: Qt.alpha(Theme.mainBg, 0.5 + 0.35 * root.hold) }
                GradientStop { position: 1; color: Qt.alpha(Theme.mainBg, 0.75 + 0.2 * root.hold) }
            }
            MouseArea { anchors.fill: parent; onClicked: root.open = false }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => {
                e.accepted = true
                if (e.isAutoRepeat) return
                const n = root.actions.length
                if (e.key === Qt.Key_Escape) root.open = false
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_Down) { root.release(); root.sel = (root.sel + 1) % n }
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_Up) { root.release(); root.sel = (root.sel + n - 1) % n }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.press(root.sel)
                else {
                    const i = root.actions.findIndex(a => a.key === e.text.toLowerCase())
                    if (i >= 0) root.press(i)
                    else e.accepted = false
                }
            }
            Keys.onReleased: e => { if (!e.isAutoRepeat) root.release() }
        }

        Column {
            anchors.centerIn: parent
            spacing: 36

            // clock · date · uptime
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                opacity: shade.opacity
                transform: Translate { y: (1 - shade.opacity) * 16 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, Settings.clock24h ? "HH:mm" : "hh:mm")
                    color: Theme.mainFg
                    font { family: Theme.font; pixelSize: 112; bold: true; letterSpacing: -4 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(clock.date, "dddd, d MMMM") + (root.uptime ? "  ·  up " + root.uptime : "")
                    color: Theme.mainFg
                    opacity: 0.7
                    font { family: Theme.font; pixelSize: 15 }
                }
            }

            // the action pill
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: card.width
                height: card.height

                LiquidCard {
                    id: card
                    readonly property int slot: 64
                    readonly property int gap: 10
                    readonly property int pad: 14
                    width: root.actions.length * slot + (root.actions.length - 1) * gap + 2 * pad
                    height: slot + 2 * pad
                    radius: height / 2
                    color: Qt.alpha(Theme.mainBg, 0.97)
                    border.color: Qt.alpha(Theme.mainFg, 0.35)
                    border.width: 1

                    // swallow clicks on the pill's padding (the backdrop would close)
                    MouseArea { anchors.fill: parent }

                    // the blob: springs to the chosen slot, stretching with how far behind it is
                    Item {
                        id: blob
                        readonly property real tx: card.pad + root.sel * (card.slot + card.gap)
                        property real bx: tx
                        Behavior on bx { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.2 } }
                        readonly property real lag: Math.min(30, Math.abs(bx - tx) * 0.5)
                        x: bx - lag / 2
                        y: card.pad
                        width: card.slot + lag
                        height: card.slot

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * (1 - 0.08 * root.hold)
                            height: parent.height * (1 - 0.08 * root.hold)
                            radius: height / 2
                            color: Theme.actBg
                        }
                        // hold ring
                        Shape {
                            anchors.centerIn: parent
                            width: card.slot + 8
                            height: card.slot + 8
                            visible: root.hold > 0
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Theme.actFg
                                strokeWidth: 3
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: (card.slot + 8) / 2
                                    centerY: (card.slot + 8) / 2
                                    radiusX: (card.slot + 8) / 2 - 2
                                    radiusY: radiusX
                                    startAngle: -90
                                    sweepAngle: 360 * root.hold
                                }
                            }
                        }
                    }

                    Row {
                        x: card.pad
                        y: card.pad
                        spacing: card.gap
                        Repeater {
                            model: root.actions
                            Item {
                                id: btn
                                required property var modelData
                                required property int index
                                readonly property bool active: root.sel === index
                                width: card.slot
                                height: card.slot
                                scale: tap.pressed && !btn.modelData.hold ? 0.9 : 1
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                    onHoveredChanged: if (hovered && root.sel !== btn.index) { root.release(); root.sel = btn.index }
                                }
                                TapHandler {
                                    id: tap
                                    gesturePolicy: TapHandler.ReleaseWithinBounds   // exclusive grab: the backdrop never sees it
                                    onPressedChanged: pressed ? root.press(btn.index) : root.release()
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: Theme.g(btn.modelData.icon)
                                    color: btn.active ? Theme.mainBg : Theme.mainFg
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    font { family: Theme.font; pixelSize: 26 }
                                }
                            }
                        }
                    }
                }
            }

            // what the blob is on, and how to run it
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                opacity: shade.opacity
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.cur.label
                    color: Theme.mainFg
                    font { family: Theme.font; pixelSize: 18; bold: true }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.cur.hold ? "hold  " : "") + "⏎  or  " + root.cur.key.toUpperCase()
                    color: Theme.mainFg
                    opacity: 0.65
                    font { family: Theme.font; pixelSize: 13 }
                }
            }
        }
    }
}
