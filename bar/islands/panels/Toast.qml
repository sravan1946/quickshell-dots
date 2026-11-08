import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.islands

// New notifications dropping out of the bell (NoteState.drops, Settings.notifDrop), newest on
// top: the app, what it says, its buttons and a copy chip for a one-time code. Click what one
// says for the app's default action; ✕ dismisses just that one. Critical ones have a red edge. A long run scrolls. When the
// card moves on they're done with: dismissed, and kept in the history.
Panel {
    id: p
    implicitWidth: 320
    spacing: 6
    Component.onDestruction: NoteState.dismissAll()

    ListView {
        id: list
        width: parent.width
        height: Math.min(contentHeight, 360)
        clip: contentHeight > height
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        spacing: 6
        model: ScriptModel { values: NoteState.drops }
        // a new one arrives at the top: it fades in, the rest make room
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260 * Look.speed; easing.type: Easing.OutCubic }
        }
        // (a burst moves earlier ones mid-fade: finish their fade too, or they stay faint)
        displaced: Transition {
            Anim { property: "y"; type: "fast" }
            NumberAnimation { property: "opacity"; to: 1; duration: 200 * Look.speed }
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            // a replaced notification is destroyed a moment before its row leaves: every read is
            // null-safe (the reference goes null without telling the bindings)
            readonly property var n: modelData
            readonly property string code: History.otp(n?.summary ?? "", n?.body ?? "")
            width: ListView.view.width
            height: col.implicitHeight + 16
            radius: 10
            color: NoteState.drops.length > 1 ? (rh.hovered ? Qt.alpha("white", 0.09) : Look.raise) : "transparent"
            // critical: a red edge, and it stays until dismissed
            border.width: NoteState.critical(n) ? 1 : 0
            border.color: Look.alert
            Behavior on color { Fade {} }
            HoverHandler { id: rh }
            // right-click anywhere on it: dismiss just this one
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: NoteState.dismiss(row.n) }

            Column {
                id: col
                x: 8; y: 8
                width: parent.width - 16
                spacing: 6
                RowLayout {
                    width: parent.width
                    spacing: 10
                    // clicking what it says: the app's default action (focus the chat, open the mail...)
                    TapHandler {
                        onTapped: {
                            (row.n?.actions ?? []).find(a => a.identifier === "default")?.invoke()
                            NoteState.dismiss(row.n)
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Image {
                        readonly property string src: row.n?.image || (row.n?.appIcon ? Quickshell.iconPath(row.n.appIcon, true) : "")
                        visible: src !== ""
                        source: src
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignTop
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        T {
                            Layout.fillWidth: true
                            text: row.n?.appName ?? ""
                            visible: text !== ""
                            color: Look.faint
                            font.pixelSize: Look.small
                            elide: Text.ElideRight
                        }
                        T { Layout.fillWidth: true; text: row.n?.summary ?? ""; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        T {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: row.n?.body ?? ""
                            textFormat: Text.StyledText
                            color: Look.dim
                            font.pixelSize: Look.small
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }
                    G {
                        Layout.alignment: Qt.AlignTop
                        glyph: 0xF0156
                        font.pixelSize: 13
                        color: xh.hovered ? Look.alert : Look.faint
                        HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: NoteState.dismiss(row.n) }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    visible: buttons.count > 0 || row.code !== ""
                    Btn { visible: row.code !== ""; text: "Copy " + row.code; strong: true; onClicked: { History.copy(row.code); NoteState.dismiss(row.n) } }
                    Repeater {
                        id: buttons
                        model: History.buttons(row.n?.actions ?? [])
                        Btn {
                            required property var modelData
                            text: modelData.text
                            onClicked: { modelData.invoke(); NoteState.dismiss(row.n) }
                        }
                    }
                }
            }
        }
    }
    T {
        visible: NoteState.drops.length > 1
        anchors.right: parent.right
        text: "Clear all"
        color: ch.hovered ? Look.alert : Look.faint
        font.pixelSize: Look.small
        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { NoteState.markRead(); p.ctl.hide() } }
    }
}
