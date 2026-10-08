import QtQuick
import qs

// quiet text link at the foot of a panel (WifiMenu, BtMenu)
Text {
    signal clicked()
    leftPadding: 9
    color: Theme.mainFg
    opacity: linkHover.hovered ? 1 : 0.6
    font { family: Theme.font; pixelSize: 11 }
    HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: parent.clicked() }
}
