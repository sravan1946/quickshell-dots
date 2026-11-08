import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.islands

// A tray app's own menu, inside the card. A submenu opens in place, with a way back.
Panel {
    id: p
    implicitWidth: Math.max(200, widest + 24)
    spacing: 2
    property real widest: 0
    property var stack: []            // submenus opened, innermost last
    readonly property var handle: stack.length ? stack[stack.length - 1] : arg?.menu ?? null
    QsMenuOpener { id: opener; menu: p.handle }

    Head { text: p.arg?.tooltipTitle || p.arg?.title || p.arg?.id || "" }
    Choice {
        visible: p.stack.length > 0
        title: "Back"
        onClicked: p.stack = p.stack.slice(0, -1)
        G { anchors.centerIn: parent; glyph: 0xF0141 }
    }
    Repeater {
        model: opener.children
        Item {
            id: r
            required property var modelData
            readonly property var e: modelData
            width: p.width
            implicitHeight: e?.isSeparator ? 9 : 30
            Rectangle {
                visible: !!r.e?.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                width: parent.width - 16
                height: 1
                color: Look.line
            }
            Choice {
                visible: !r.e?.isSeparator
                width: parent.width
                title: r.e?.text ?? ""
                opacity: r.e?.enabled ?? true ? 1 : 0.45
                clickable: r.e?.enabled ?? true
                note: r.e?.hasChildren ? "›" : ""
                selected: r.e?.checkState === Qt.Checked
                icon: typeof r.e?.icon === "string" && r.e.icon !== ""
                Component.onCompleted: p.widest = Math.max(p.widest, metrics.advanceWidth(r.e?.text ?? "") + 60)
                onClicked: {
                    if (r.e.hasChildren) p.stack = p.stack.concat([r.e])
                    else { r.e.triggered(); p.ctl.hide() }
                }
                IconImage {
                    anchors.centerIn: parent
                    visible: typeof r.e?.icon === "string" && r.e.icon !== ""
                    source: typeof r.e?.icon === "string" ? r.e.icon : ""
                    implicitSize: 16
                }
            }
        }
    }
    FontMetrics { id: metrics; font.family: Look.sans; font.pixelSize: Look.size }
}
