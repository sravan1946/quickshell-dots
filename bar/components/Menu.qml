import QtQuick
import Quickshell
import Quickshell.Widgets
import qs

// GTK-style menu matching waybar's HyDE menus: rounded frame, pill hover,
// check/radio column, ▶ submenus that open beside the row on hover.
//
// Feed it either `handle` (a tray app's D-Bus menu, e.g. SystemTrayItem.menu)
// or `items`, a list of static entries:
//   { icon: 0xF0341, text: "Lock", cmd: "shell command" }   icon = Nerd Font codepoint
//   { separator: true }
//   { icon: 0xF06A6, text: "Shutdown", items: [ ...entries ] }   submenu
Dropdown {
    id: menu

    property var items: []
    property var handle: null
    property Item row: null              // set on submenus: the parent row to open beside
    property var rootMenu: menu
    property int openIndex: -1           // row whose submenu is open
    property int minWidth: 170
    property real widest: 0

    readonly property bool isSub: row !== null
    readonly property var entries: handle ? opener.children.values : items

    closeOnOutsideClick: true
    padX: 0
    padY: 8
    target: row
    // top-level: drop down from the module's left edge; submenu: beside the row,
    // overlapping the parent by ~22px like GTK does
    // (shifted by shadowPad: the card sits that far inside the popup window)
    anchor.rect: isSub ? Qt.rect(22, -padY - shadowPad, row.width - 44 - shadowPad, row.height)
        : Qt.rect(-shadowPad, target.height + 4 - shadowPad, 1, 1)
    anchor.edges: isSub ? Edges.Right | Edges.Top : Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.FlipX | PopupAdjustment.Slide

    onVisibleChanged: if (!visible) openIndex = -1
    onOpenIndexChanged: { sub.active = false; sub.active = openIndex >= 0 }

    function activate(e) {
        rootMenu.close()
        if (handle) e.triggered()
        else if (e.cmd) Util.run(e.cmd)
    }

    QsMenuOpener { id: opener; menu: menu.handle }

    Column {
        id: col
        width: Math.max(menu.minWidth, menu.widest)

        Repeater {
            id: rep
            model: menu.entries

            Item {
                id: r
                required property var modelData
                required property int index
                readonly property var e: modelData ?? ({})   // null for a beat when the app drops the entry under an open menu
                readonly property bool sep: !!(e.isSeparator ?? e.separator)
                readonly property bool sub: !!(e.hasChildren ?? e.items)
                readonly property bool on: e.enabled ?? true
                readonly property bool lit: !sep && on && (mouse.containsMouse || menu.openIndex === index)
                readonly property int kind: e.buttonType ?? 0          // QsMenuButtonType: None / CheckBox / RadioButton
                readonly property bool checked: e.checkState === Qt.Checked
                readonly property color fg: lit ? Theme.actFg : Theme.menuFg

                width: col.width
                height: sep ? 9 : 24
                Component.onCompleted: menu.widest = Math.max(menu.widest, 35 + line.implicitWidth + (sub ? 52 : 26))

                Rectangle {   // hover pill
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    radius: height / 2
                    color: Theme.actBg
                    opacity: r.lit ? 1 : 0
                    // short: a long fade left a trail of lit rows behind the pointer
                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
                Rectangle {   // separator
                    visible: r.sep
                    anchors.verticalCenter: parent.verticalCenter
                    x: 10
                    width: parent.width - 20
                    height: 1
                    color: Theme.mainFg
                    opacity: 0.25
                }
                Rectangle {   // check / radio column: GTK theme draws both as circles, hollow when off
                    visible: r.kind !== 0
                    x: 14
                    width: 11
                    height: 11
                    radius: 5.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: r.checked && r.kind !== QsMenuButtonType.RadioButton ? r.fg : "transparent"
                    border.color: r.fg
                    border.width: 1.3
                    Text {    // checkbox tick
                        visible: r.checked && r.kind !== QsMenuButtonType.RadioButton
                        anchors.centerIn: parent
                        text: "\u2713"
                        color: Theme.mainBg
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Rectangle {   // radio dot
                        visible: r.checked && r.kind === QsMenuButtonType.RadioButton
                        anchors.centerIn: parent
                        width: 5; height: 5; radius: 2.5
                        color: r.fg
                    }
                }
                Row {
                    id: line
                    visible: !r.sep
                    x: 35
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: r.on ? 1 : 0.5
                    IconImage {
                        visible: typeof r.e.icon === "string" && r.e.icon !== ""
                        source: typeof r.e.icon === "string" ? r.e.icon : ""
                        implicitSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                        // load at device pixels, not logical (see Mod.qml)
                        backer.sourceSize: Qt.size(Math.ceil(actualSize * (QsWindow.window?.devicePixelRatio ?? 1)), Math.ceil(actualSize * (QsWindow.window?.devicePixelRatio ?? 1)))
                        mipmap: true
                    }
                    Label {
                        visible: typeof r.e.icon === "number"
                        text: typeof r.e.icon === "number" ? Theme.g(r.e.icon) + " " : ""
                        color: r.fg
                    }
                    Label { text: r.e.text ?? ""; color: r.fg }   // quickshell already strips D-Bus mnemonics
                }
                Label {       // submenu arrow
                    visible: r.sub
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▶"
                    font.pixelSize: 10
                    color: r.fg
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !r.sep && r.on
                    onContainsMouseChanged: if (containsMouse) hoverDelay.restart()
                    onClicked: r.sub ? menu.openIndex = r.index : menu.activate(r.e)
                }
                Timer {       // GTK opens/closes submenus after a short hover
                    id: hoverDelay
                    interval: 120
                    onTriggered: if (mouse.containsMouse) menu.openIndex = r.sub ? r.index : -1
                }
            }
        }
    }

    LazyLoader {
        id: sub
        active: false
        source: Qt.resolvedUrl("Menu.qml")
        onItemChanged: {
            if (!item) return
            const r = rep.itemAt(menu.openIndex)
            item.rootMenu = menu.rootMenu
            if (menu.handle) item.handle = r.e
            else item.items = r.e.items
            item.row = r
            item.visible = true
        }
    }
}
