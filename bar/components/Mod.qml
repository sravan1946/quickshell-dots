import QtQuick
import Quickshell
import Quickshell.Widgets
import qs

// One waybar-style module: a label and/or icon with click, scroll and a tooltip.
// button: true gives the workspace/taskbar look (pill bg, active/hover colours).
Item {
    id: m

    property string text: ""
    property bool richText: false
    property string icon: ""
    property int iconSize: 16
    property string tip: ""            // Qt rich text; <br> for new lines
    property Component tipItem: null  // or a custom tooltip body (wins over `tip`)
    property bool button: false
    property bool active: false
    property color fg: Theme.mainFg    // label colour when not a hovered/active button
    property color activeBg: Theme.actBg   // transparent when the row draws a sliding one (ActiveSlide)
    property int minChars: 0           // waybar min-length
    property real extraPad: 0          // GTK label buttons (workspaces) render ~4.5px wider per side
    property bool growIn: false        // grow in when created or shown; rows turn it on after startup so a reload stays still
    readonly property bool hovered: mouse.containsMouse
    readonly property string screenName: QsWindow.window?.screen?.name ?? ""   // which bar's tooltip shows it

    signal clicked(int button)
    signal scrolled(int steps)         // +1 = up, -1 = down, one per wheel notch

    readonly property real pad: (button ? (active ? 9 : 3) : 3) + extraPad
    readonly property real margin: button ? 1.1 : 0

    height: parent ? parent.height : 24
    implicitWidth: Math.max(content.implicitWidth, minChars * metrics.averageCharacterWidth) + 2 * pad + 2 * margin
    // same 250ms as ActiveSlide, so the highlight lands as the button finishes growing
    Behavior on implicitWidth {
        enabled: m.button
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    FontMetrics { id: metrics; font.family: Theme.font; font.pixelSize: Theme.fontSize }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: m.margin
        anchors.rightMargin: m.margin
        anchors.topMargin: m.button ? 1 : 0
        anchors.bottomMargin: m.button ? 1 : 0
        radius: height / 2
        // plain modules get a faint wash on hover (deeper while pressed) so every
        // clickable thing in the bar answers the pointer, not just the buttons
        color: m.button ? (m.hovered ? Theme.hvrBg : m.active ? m.activeBg : "transparent")
            : m.hovered ? Qt.alpha(Theme.mainFg, mouse.pressed ? 0.2 : 0.1) : "transparent"
        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    Row {
        id: content
        anchors.centerIn: parent
        scale: mouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        IconImage {
            visible: m.icon !== ""
            source: m.icon
            implicitSize: m.iconSize
            anchors.verticalCenter: parent.verticalCenter
            // IconImage loads at its logical size, so at 1.5x a 16px icon was a 16px raster
            // stretched to 24: load at the window's device pixels instead (Screen's ratio is
            // the rounded-up 2), mipmapped for raster icons that still need shrinking
            readonly property real dpr: m.QsWindow.window?.devicePixelRatio ?? 1
            backer.sourceSize: Qt.size(Math.ceil(actualSize * dpr), Math.ceil(actualSize * dpr))
            mipmap: true
        }
        Label {
            visible: m.text !== ""
            text: m.text
            textFormat: m.richText ? Text.StyledText : Text.PlainText
            color: m.button && m.hovered ? Theme.hvrFg : m.button && m.active ? Theme.actFg : m.fg
            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    property real wheelAcc: 0
    MouseArea {
        id: mouse
        anchors { fill: parent; topMargin: -Config.pillInset; bottomMargin: -Config.pillInset }
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: Tip.hide()
        onClicked: e => m.clicked(e.button)
        // Touchpads send many small deltas; accumulate to whole notches (120).
        onWheel: e => {
            m.wheelAcc += e.angleDelta.y
            while (Math.abs(m.wheelAcc) >= 120) {
                const s = Math.sign(m.wheelAcc)
                m.wheelAcc -= s * 120
                m.scrolled(s)
            }
        }
    }

    // On the module itself, not a Row add transition: those get cut short (and stick
    // half-faded) when a neighbour's width animation relayouts the row mid-way.
    onVisibleChanged: if (visible && growIn) grow.restart()
    Component.onCompleted: if (growIn) grow.restart()
    ParallelAnimation {
        id: grow
        NumberAnimation { target: m; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: m; property: "scale"; from: 0.6; to: 1; duration: 200; easing.type: Easing.OutCubic }
    }

    // hover tooltip: one shared bubble per bar (Tip.qml, components/Tooltip.qml)
    onHoveredChanged: {
        if (hovered) Tip.hover(m, screenName)
        else { Tip.leave(m); wheelAcc = 0 }
    }
    Component.onDestruction: Tip.leave(m)
}
