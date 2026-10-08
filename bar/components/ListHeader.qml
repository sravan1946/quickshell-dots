import QtQuick
import qs

// A list's heading ("Networks", "Devices", "Nearby"; WifiList, BtList). With `refreshable`,
// a refresh button on the right that spins while `busy`.
Text {
    id: head

    property bool busy: false
    property bool refreshable: false
    signal refresh()

    color: Qt.alpha(Theme.mainFg, 0.55)
    font { family: Theme.font; pixelSize: 11; bold: true }

    Text {
        visible: head.refreshable
        anchors { right: parent.right; bottom: parent.bottom }
        text: Theme.g(0xF0450)
        color: Theme.mainFg
        opacity: head.busy ? 1 : 0.55
        font { family: Theme.font; pixelSize: 12 }
        RotationAnimator on rotation { running: head.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
        TapHandler { onTapped: head.refresh() }
    }
}
