import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.islands

// Notifications: do-not-disturb, then the history by app (newest shown, the rest behind
// "+N more"). One-time codes get a copy chip. While it's open, new notifications land here
// instead of popping up (Config.historyOpen), and everything counts as read.
Panel {
    id: p
    implicitWidth: 340
    Component.onCompleted: { Config.historyOpen = true; NoteState.markRead(); regroup() }
    Component.onDestruction: { Config.historyOpen = false; NoteState.markRead() }

    property var groups: []
    property var expanded: ({})
    function regroup() {
        const by = {}, out = []
        for (let i = 0; i < History.entries.count; i++) {
            const e = History.entries.get(i)
            if (!by[e.app]) out.push(by[e.app] = { app: e.app, items: [] })
            by[e.app].items.push({ idx: i, app: e.app, summary: e.summary, body: e.body, icon: e.icon, time: e.time })
        }
        groups = out
    }
    Connections { target: History.entries; function onCountChanged() { p.regroup(); NoteState.markRead() } }
    property real now: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: p.now = Date.now() }
    function ago(ms) {
        const s = Math.max(0, Math.floor((now - ms) / 1000))
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d"
    }

    Head {
        text: "Notifications"
        T { text: "Do not disturb"; color: Look.faint; font.pixelSize: Look.small; anchors.verticalCenter: parent.verticalCenter }
        Switch { on: Config.dnd; onToggled: Config.dnd = !Config.dnd }
    }
    T {
        visible: p.groups.length === 0
        leftPadding: 4
        topPadding: 6
        bottomPadding: 6
        text: "Nothing new."
        color: Look.dim
    }
    ListView {
        width: parent.width
        height: Math.min(contentHeight, 380)
        visible: p.groups.length > 0
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: p.groups
        delegate: Column {
            id: grp
            required property var modelData
            readonly property bool open: !!p.expanded[modelData.app]
            readonly property int more: modelData.items.length - 1
            width: ListView.view.width
            spacing: 4
            Repeater {
                model: grp.open ? grp.modelData.items : grp.modelData.items.slice(0, 1)
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property string code: History.otp(modelData.summary, modelData.body)
                    property bool copied: false
                    width: grp.width
                    height: body.implicitHeight + 16
                    radius: 10
                    color: rh.hovered ? Qt.alpha("white", 0.09) : Look.raise
                    Behavior on color { Fade {} }
                    HoverHandler { id: rh }
                    RowLayout {
                        id: body
                        anchors { fill: parent; margins: 8 }
                        spacing: 10
                        Image {
                            visible: row.modelData.icon !== ""
                            source: row.modelData.icon
                            sourceSize: Qt.size(48, 48)
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignTop
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            T { Layout.fillWidth: true; text: row.modelData.summary || row.modelData.app; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            T {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.modelData.body
                                textFormat: Text.StyledText
                                color: Look.dim
                                font.pixelSize: Look.small
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                            Btn {
                                visible: row.code !== ""
                                Layout.topMargin: 3
                                text: row.copied ? "Copied" : "Copy " + row.code
                                strong: true
                                onClicked: { History.copy(row.code); row.copied = true }
                            }
                        }
                        Column {
                            Layout.alignment: Qt.AlignTop
                            spacing: 4
                            T { anchors.right: parent.right; text: p.ago(row.modelData.time); color: Look.faint; font.pixelSize: Look.small }
                            G {
                                anchors.right: parent.right
                                glyph: 0xF0156
                                font.pixelSize: 13
                                color: xh.hovered ? Look.alert : Look.faint
                                opacity: rh.hovered ? 1 : 0
                                Behavior on opacity { Anim { type: "effects" } }
                                HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: History.remove(row.modelData.idx) }
                            }
                        }
                    }
                }
            }
            Item {
                visible: grp.more > 0
                width: parent.width
                height: 18
                T {
                    x: 8
                    text: grp.open ? "Show less" : `+${grp.more} more from ${grp.modelData.app}`
                    color: fh.hovered ? Look.text : Look.dim
                    font.pixelSize: Look.small
                    HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { const e = Object.assign({}, p.expanded); e[grp.modelData.app] = !grp.open; p.expanded = e } }
                }
                T {
                    anchors.right: parent.right
                    rightPadding: 8
                    text: "Clear " + (grp.more + 1)
                    color: ch.hovered ? Look.alert : Look.faint
                    font.pixelSize: Look.small
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: History.removeApp(grp.modelData.app) }
                }
            }
        }
    }
    Item {
        visible: p.groups.length > 0
        width: parent.width
        height: 24
        T {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 4
            text: Config.historyPaused ? "History is paused" : "History is on"
            color: Look.faint
            font.pixelSize: Look.small
            TapHandler { onTapped: Config.historyPaused = !Config.historyPaused }
        }
        Btn { anchors.right: parent.right; text: "Clear all"; onClicked: History.clear() }
    }
}
