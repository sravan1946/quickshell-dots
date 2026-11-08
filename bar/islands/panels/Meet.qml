import QtQuick
import Quickshell
import qs
import qs.islands

// The meeting that's about to start (or is on): when, and a way in.
Panel {
    id: p
    implicitWidth: 270
    readonly property var e: Cal.next
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property real mins: e ? Math.ceil((new Date(e.start) - clock.date) / 60000) : 0
    function hm(d) { return Qt.formatTime(d, Settings.clock24h ? "HH:mm" : "h:mm ap") }

    Head { text: p.mins <= 0 ? "On now" : p.mins < 60 ? "Next meeting, in " + p.mins + " min" : "Next meeting, " + Qt.formatDate(new Date(p.e.start), "ddd d MMM") }
    T { width: parent.width; text: p.e?.title ?? ""; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
    T {
        text: p.e ? `${p.hm(new Date(p.e.start))} – ${p.hm(new Date(p.e.end))}` : ""
        color: Look.dim
        font.pixelSize: Look.small
    }
    Row {
        spacing: 8
        topPadding: 2
        Btn { visible: !!p.e?.meet; text: "Join"; strong: true; tone: Look.warm; onClicked: { Qt.openUrlExternally(p.e.meet); p.ctl.hide() } }
        Btn { visible: !!p.e?.link; text: "Open event"; onClicked: { Qt.openUrlExternally(p.e.link); p.ctl.hide() } }
    }
}
