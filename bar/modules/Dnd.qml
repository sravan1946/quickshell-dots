import QtQuick
import QtQuick.Layouts
import qs
import qs.components

// Notification centre button. Left-click: history panel. Right-click: do-not-disturb.
// (Also `qs -c bar ipc call notifications toggleDnd` for a keybind.)
// The panel folds history by app: newest entry shown, the rest behind "+N more".
Mod {
    id: dnd

    text: Theme.g(Config.dnd ? 0xF009B : 0xF009A) + (Config.dnd && Config.held > 0 ? " " + Config.held : "")
    tip: (Config.dnd
        ? `<font color="#e06c75">${Theme.g(0xF009B)} Do Not Disturb</font><br>${Config.held} held, shown when you turn it off`
        : `<font color="#98c379">${Theme.g(0xF009A)} Notifications On</font>`)
        + "<br>Click: history · Right-click: toggle DND"
    onClicked: b => {
        if (b === Qt.RightButton) Config.dnd = !Config.dnd
        else { panel.toggle() }
    }

    Connections { target: Config; function onToggleHistory() { panel.toggle() } }

    // History.entries grouped by app, groups ordered by their newest entry
    property var groups: []
    property var expanded: ({})
    function regroup() {
        const by = {}, out = []
        for (let i = 0; i < History.entries.count; i++) {
            const e = History.entries.get(i)
            if (!by[e.app]) out.push(by[e.app] = { app: e.app, items: [] })
            by[e.app].items.push({ idx: i, app: e.app, summary: e.summary, body: e.body, icon: e.icon, buttons: e.buttons, time: e.time })
        }
        groups = out
    }
    function toggleGroup(app) { const e = Object.assign({}, expanded); e[app] = !e[app]; expanded = e }
    Connections { target: History.entries; function onCountChanged() { dnd.regroup() } }
    Component.onCompleted: regroup()

    property real now: Date.now()
    Timer { interval: 30000; running: panel.visible; repeat: true; onTriggered: dnd.now = Date.now() }
    function ago(ms) {
        const s = Math.max(0, Math.floor((now - ms) / 1000))
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    Dropdown {
        id: panel
        target: dnd
        closeOnOutsideClick: true
        padX: 12
        padY: 10
        onVisibleChanged: { Config.historyOpen = visible; if (visible) dnd.now = Date.now() }

        Column {
            spacing: 8
            width: 360

            RowLayout {
                width: parent.width
                spacing: 12
                Text {
                    text: "Notifications"
                    color: Theme.mainFg
                    font { family: Theme.font; pixelSize: 14; bold: true }
                    Layout.fillWidth: true
                }
                Toggle { text: "Log"; checked: !Config.historyPaused; onToggled: Config.historyPaused = !Config.historyPaused }
                Toggle { text: "DND"; checked: Config.dnd; onToggled: Config.dnd = !Config.dnd }
                PillButton { text: "Clear"; onClicked: History.clear() }
            }

            Text {
                visible: Config.historyPaused
                text: "History paused: new notifications still pop up but aren't saved"
                color: Theme.mainFg
                opacity: 0.6
                font { family: Theme.font; pixelSize: 11 }
                width: parent.width
                wrapMode: Text.Wrap
            }

            Text {
                visible: History.entries.count === 0
                text: "No notifications"
                color: Theme.mainFg
                opacity: 0.6
                font { family: Theme.font; pixelSize: 13 }
                topPadding: 8
                bottomPadding: 8
                anchors.horizontalCenter: parent.horizontalCenter
            }

            ListView {
                width: parent.width
                height: Math.min(contentHeight, 420)
                visible: History.entries.count > 0
                clip: true
                spacing: 6
                model: dnd.groups
                boundsBehavior: Flickable.StopAtBounds

                delegate: Column {
                    id: grp
                    required property var modelData
                    readonly property bool open: !!dnd.expanded[modelData.app]
                    readonly property int more: modelData.items.length - 1
                    width: ListView.view.width
                    spacing: 4

                    Repeater {
                        model: grp.open ? grp.modelData.items : grp.modelData.items.slice(0, 1)

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property string code: History.otp(modelData.summary, modelData.body)
                            property bool copied: false

                            width: grp.width
                            height: rowContent.implicitHeight + 16
                            radius: 8
                            color: rowHover.hovered ? Qt.alpha(Theme.mainFg, 0.2) : Qt.alpha(Theme.mainFg, 0.08)
                            Behavior on color { ColorAnimation { duration: 150 } }

                            HoverHandler { id: rowHover }

                            RowLayout {
                                id: rowContent
                                anchors { fill: parent; margins: 8 }
                                spacing: 10

                                Image {
                                    visible: row.modelData.icon !== ""
                                    source: row.modelData.icon
                                    sourceSize: Qt.size(28, 28)
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignTop
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.summary !== "" ? row.modelData.summary : row.modelData.app
                                        color: Theme.mainFg
                                        font { family: Theme.font; pixelSize: 13; bold: true }
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: row.modelData.body
                                        textFormat: Text.StyledText
                                        color: Theme.actFg
                                        font { family: Theme.font; pixelSize: 12 }
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                    // the buttons the popup had; the notification is gone, so they are a record only.
                                    // the copy chip still works: it only needs the text
                                    Row {
                                        readonly property var labels: JSON.parse(row.modelData.buttons)
                                        spacing: 6
                                        topPadding: 3
                                        visible: labels.length > 0 || row.code !== ""
                                        Rectangle {
                                            visible: row.code !== ""
                                            radius: 8
                                            color: copyMouse.containsMouse ? Theme.hvrBg : Theme.actBg
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            implicitWidth: copyChip.implicitWidth + 14
                                            implicitHeight: copyChip.implicitHeight + 6
                                            Text {
                                                id: copyChip
                                                anchors.centerIn: parent
                                                text: Theme.g(0xF018F) + (row.copied ? " Copied" : " Copy " + row.code)
                                                color: copyMouse.containsMouse ? Theme.hvrFg : Theme.mainBg
                                                font { family: Theme.font; pixelSize: 11 }
                                            }
                                            MouseArea {
                                                id: copyMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: { History.copy(row.code); row.copied = true }
                                            }
                                        }
                                        Repeater {
                                            model: parent.labels
                                            delegate: Rectangle {
                                                required property string modelData
                                                radius: 8
                                                color: Qt.alpha(Theme.actBg, 0.55)
                                                implicitWidth: chip.implicitWidth + 14
                                                implicitHeight: chip.implicitHeight + 6
                                                Text {
                                                    id: chip
                                                    anchors.centerIn: parent
                                                    text: parent.modelData
                                                    color: Theme.mainBg
                                                    font { family: Theme.font; pixelSize: 11 }
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: dnd.ago(row.modelData.time)
                                    color: Theme.mainFg
                                    opacity: 0.6
                                    font { family: Theme.font; pixelSize: 11 }
                                    Layout.alignment: Qt.AlignTop
                                }
                                Text {
                                    text: Theme.g(0xF0156)
                                    color: xMouse.containsMouse ? "#f7768e" : Theme.mainFg
                                    opacity: xMouse.containsMouse ? 1 : 0.6
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    font { family: Theme.font; pixelSize: 14 }
                                    Layout.alignment: Qt.AlignTop
                                    MouseArea {
                                        id: xMouse
                                        anchors { fill: parent; margins: -4 }
                                        hoverEnabled: true
                                        onClicked: History.remove(row.modelData.idx)
                                    }
                                }
                            }
                        }
                    }

                    // fold line: expand/collapse this app's stack, or clear all of it
                    RowLayout {
                        visible: grp.more > 0
                        width: parent.width
                        Text {
                            text: (grp.open ? "Show less " + Theme.g(0xF0143) : `+${grp.more} more from ${grp.modelData.app} ` + Theme.g(0xF0140))
                            color: Theme.mainFg
                            opacity: foldMouse.containsMouse ? 1 : 0.6
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            font { family: Theme.font; pixelSize: 11 }
                            leftPadding: 8
                            Layout.fillWidth: true
                            MouseArea { id: foldMouse; anchors.fill: parent; hoverEnabled: true; onClicked: dnd.toggleGroup(grp.modelData.app) }
                        }
                        Text {
                            text: "Clear " + (grp.more + 1)
                            color: clrMouse.containsMouse ? "#f7768e" : Theme.mainFg
                            opacity: clrMouse.containsMouse ? 1 : 0.6
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            font { family: Theme.font; pixelSize: 11 }
                            rightPadding: 8
                            MouseArea { id: clrMouse; anchors.fill: parent; hoverEnabled: true; onClicked: History.removeApp(grp.modelData.app) }
                        }
                    }
                }
            }
        }
    }
}
