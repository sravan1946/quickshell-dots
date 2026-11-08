import QtQuick
import qs
import qs.islands

// A copy, dropping out of the clock for a moment: what was copied, in one line.
Panel {
    implicitWidth: 260
    Row {
        width: parent.width
        spacing: 10
        G { id: icon; width: 18; glyph: ClipState.kind === "i" ? 0xF02E9 : ClipState.kind === "s" ? 0xF033E : 0xF014C; color: Look.accent }
        T { id: what; text: "Copied"; anchors.verticalCenter: parent.verticalCenter }
        T {
            width: parent.width - icon.width - what.width - 2 * parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: ClipState.kind === "t" ? ClipState.text : ClipState.kind === "i" ? "image" : ClipState.kind === "s" ? "hidden" : ""
            elide: Text.ElideRight
            color: Look.dim
        }
    }
}
