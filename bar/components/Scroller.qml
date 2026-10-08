import QtQuick
import qs

// A column that scrolls once it grows past maxHeight, with a thin position bar, so a long
// list doesn't run the panel off the screen (WifiMenu, BtMenu).
Flickable {
    id: scroller

    property real maxHeight: 270
    default property alias content: inner.data
    readonly property bool overflow: contentHeight > height

    height: Math.min(inner.implicitHeight, maxHeight)
    contentHeight: inner.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    onOverflowChanged: if (!overflow) contentY = 0

    flickableData: [
        Column { id: inner; width: scroller.width - (scroller.overflow ? 8 : 0) },
        Rectangle {
            visible: scroller.overflow
            x: scroller.width - 3
            y: scroller.contentY + scroller.visibleArea.yPosition * scroller.height
            width: 3
            height: scroller.visibleArea.heightRatio * scroller.height
            radius: 1.5
            color: Qt.alpha(Theme.mainFg, 0.3)
        }
    ]
}
