import QtQuick

// A place in an island that comes and goes (music, the mic warning, the meeting chip): its
// width springs between 0 and its content's, its content fades. `target` is where the width
// is heading, so the island can size itself for the end state in the same frame (rule 7).
Item {
    id: slot

    property bool shown: false
    default property alias content: row.data
    readonly property real target: shown ? row.implicitWidth : 0

    implicitWidth: target
    implicitHeight: parent?.height ?? 30
    clip: true
    Behavior on implicitWidth { enabled: slot.ready; Anim {} }
    // nothing springs at startup
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => ready = true)

    Row {
        id: row
        // anchored to the side the island grows from; set by the island
        height: parent.height
        opacity: slot.shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim { type: "effects" } }
    }
}
