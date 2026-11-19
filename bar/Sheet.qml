import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.islands

// A card over the dimmed desktop (blurred by the "sheets" layer rule in hyprland.lua), for the
// keyboard-driven sheets: key help, clipboard, task manager. Opens on the spatial curve and
// leaves on exit. The search field at the top always has the keyboard: typing filters
// (`query`), Escape clears it and then closes, every other key comes out of key() for the
// content to handle (arrows, Enter, Delete, Tab ...). A click outside the card closes.
// Content goes inside the card, under the header.
Scope {
    id: sheet

    property bool open: false
    property string namespace: "sheet"
    property real cardW: 900
    property real cardH: 600
    property string title: ""
    property string hint: "Search"
    property string query: ""
    property string help: ""          // keys, shown faint on the right of the header
    default property alias content: body.data
    signal key(var event)

    property real p: open ? 1 : 0
    Behavior on p { Anim { type: sheet.open ? "spatial" : "exit" } }
    readonly property real fade: Math.max(0, Math.min(1, p))

    onOpenChanged: if (open) { input.text = ""; Qt.callLater(() => input.forceActiveFocus()) }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: sheet.open || sheet.p > 0.001
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: sheet.namespace
        WlrLayershell.keyboardFocus: sheet.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha("black", 0.42)
            opacity: sheet.fade
            MouseArea { anchors.fill: parent; onClicked: sheet.open = false }
        }

        Item {
            id: card
            width: Math.min(sheet.cardW, win.width - 48)
            height: Math.min(sheet.cardH, win.height - 80)
            anchors.centerIn: parent
            opacity: sheet.fade
            scale: 0.95 + 0.05 * sheet.p
            transform: Translate { y: (1 - sheet.p) * 18 }

            RectangularShadow {
                anchors.fill: bg
                radius: bg.radius
                blur: 60
                offset.y: 18
                color: Qt.alpha("black", 0.45)
                cached: true
            }
            Rectangle {
                id: bg
                anchors.fill: parent
                radius: 22
                color: Qt.rgba(Look.base.r * 0.3, Look.base.g * 0.3, Look.base.b * 0.36, 0.9)
                border.width: 1
                border.color: Look.rim
            }
            MouseArea { anchors.fill: parent }    // a click on the card isn't a click outside

            // header: title, the search field, the keys
            Item {
                id: head
                x: 22
                y: 16
                width: parent.width - 44
                height: 40

                Text {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    text: sheet.title
                    color: Look.text
                    font { family: Look.sans; pixelSize: 16; weight: Font.DemiBold }
                }
                Rectangle {
                    id: field
                    anchors { left: titleText.right; leftMargin: sheet.title ? 18 : 0; verticalCenter: parent.verticalCenter }
                    width: Math.min(360, parent.width - titleText.width - helpText.width - 48)
                    height: 34
                    radius: 11
                    color: Look.raise
                    border.width: 1
                    border.color: Qt.alpha(Look.accent, input.activeFocus ? 0.5 : 0)

                    Text {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: Look.g(0xF0349)       // magnify
                        color: Look.faint
                        font { family: Look.icons; pixelSize: 14 }
                    }
                    TextInput {
                        id: input
                        anchors { fill: parent; leftMargin: 34; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Look.text
                        selectionColor: Qt.alpha(Look.accent, 0.4)
                        clip: true
                        font { family: Look.sans; pixelSize: 13 }
                        onTextChanged: sheet.query = text
                        Keys.onPressed: e => {
                            if (e.key === Qt.Key_Escape) {
                                e.accepted = true
                                if (text) text = ""
                                else sheet.open = false
                                return
                            }
                            sheet.key(e)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !input.text
                            text: sheet.hint
                            color: Look.faint
                            font: input.font
                        }
                    }
                }
                Text {
                    id: helpText
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: sheet.help
                    color: Look.faint
                    font { family: Look.sans; pixelSize: Look.small }
                }
            }

            Item {
                id: body
                x: 0
                y: head.y + head.height + 12
                width: parent.width
                height: parent.height - y
                clip: true
            }
        }
    }
}
