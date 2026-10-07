import QtQuick
import qs

// The active background for a row of Mod buttons (workspaces, taskbar) that slides and
// stretches from the old button to the new one instead of fading in place. Put it
// behind the Row; the buttons set activeBg: "transparent" and call take() when they
// become active. The slide lerps toward the button's live geometry, so it lands exactly
// while the buttons are still resizing (Mod animates its width over the same 250ms).
Rectangle {
    id: s

    property Item cur: null
    property real fromX: 0
    property real fromW: 0
    property real p: 1
    readonly property real toX: cur ? cur.x + cur.margin : 0
    readonly property real toW: cur ? cur.width - 2 * cur.margin : 0

    function take(m) {
        // only glide if there's a highlight on screen to glide from
        if (cur && opacity > 0) { fromX = x; fromW = width; slide.restart() }
        else { slide.stop(); p = 1 }
        cur = m
    }

    visible: !!cur
    x: fromX + (toX - fromX) * p
    width: fromW + (toW - fromW) * p
    y: 1
    height: parent.height - 2
    radius: height / 2
    color: Theme.actBg
    // fades when focus leaves this monitor's windows (taskbar)
    opacity: cur?.active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    NumberAnimation { id: slide; target: s; property: "p"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
}
