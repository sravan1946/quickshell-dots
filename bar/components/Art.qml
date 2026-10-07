import QtQuick
import qs

// The cover art (Player.artFile), crossfading to the next track's once it has decoded:
// a single Image swapping its source blanks while the new file loads. Two Images take
// turns, the newest loaded one fading in on top of the other.
Item {
    id: a
    property url source: Player.artFile
    property size sourceSize
    property int fillMode: Image.PreserveAspectCrop
    property int front: 0   // which Image is on top
    readonly property bool ready: source.toString() !== "" && (front === 0 ? i0 : i1).status === Image.Ready

    opacity: source.toString() !== "" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 300 } }

    // load behind the front one; it fades in once it's ready
    function load() { if (source.toString() !== "") (front === 0 ? i1 : i0).source = source }
    onSourceChanged: load()
    Component.onCompleted: load()
    function arrived(i, img) {
        if (img.status !== Image.Ready || img.source.toString() !== source.toString() || front === i) return
        front = i
        fadeIn.target = img
        fadeIn.restart()
    }
    NumberAnimation { id: fadeIn; property: "opacity"; from: 0; to: 1; duration: 450; easing.type: Easing.InOutQuad }

    Image {
        id: i0
        z: a.front === 0 ? 1 : 0
        anchors.fill: parent
        fillMode: a.fillMode
        sourceSize: a.sourceSize
        asynchronous: true
        onStatusChanged: a.arrived(0, this)
    }
    Image {
        id: i1
        z: a.front === 1 ? 1 : 0
        anchors.fill: parent
        fillMode: a.fillMode
        sourceSize: a.sourceSize
        asynchronous: true
        onStatusChanged: a.arrived(1, this)
    }
}
