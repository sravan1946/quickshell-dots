import QtQuick
import QtQuick.Effects
import Quickshell
import qs

// Themed click popup under `target` (detail panels, menus): a soft-bordered card
// with a shadow that eases open from the module and closes quicker than it opens.
// closeOnOutsideClick: xdg popup grab, dismissed by any click outside (that path
// closes instantly: the compositor unmaps it). The card sits shadowPad inside the
// window to leave the shadow room; input only lands on the card.
PopupWindow {
    id: pop

    property Item target
    property real padX: 8
    property real padY: 8
    property real bgAlpha: 0.97
    property bool closeOnOutsideClick: false
    default property alias content: body.data
    readonly property alias hovered: cardHover.hovered   // pointer over the card
    readonly property real shadowPad: 16

    anchor.item: target
    anchor.rect: Qt.rect(0, 0, target?.width ?? 0, (target?.height ?? 0) + 6 - shadowPad)
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    color: "transparent"
    implicitWidth: body.childrenRect.width + 2 * padX + 2 * shadowPad
    implicitHeight: body.childrenRect.height + 2 * padY + 2 * shadowPad
    // Region only re-reads x/y/size, not scale/transform: masking the animated card froze
    // its hit area at the shrunken opening frame and left the bottom rows (Quit) dead.
    mask: Region { item: hit }

    grabFocus: closeOnOutsideClick

    // Clicking the module that opened us first dismisses the grab (closing us),
    // then toggles; don't reopen in that case.
    property real closedAt: 0
    onVisibleChanged: {
        if (visible) { Tip.hide(); Tip.popups++; shut.stop(); settleWait.restart(); settle() }
        else { Tip.popups--; closedAt = Date.now(); wrap.progress = 0; settleWait.stop() }
    }
    // A fresh popup maps at the wrong scale: on the 1.5x screen its dpr goes 2 -> 1 -> 1.5
    // over ~100ms, and those frames draw the card zoomed (a flicker). Stay invisible until
    // it matches the bar's dpr; give up waiting after 250ms.
    onDevicePixelRatioChanged: settle()
    function settle() { if (settleWait.running && devicePixelRatio === target?.QsWindow.window?.devicePixelRatio) appear() }
    Timer { id: settleWait; interval: 250; onTriggered: pop.appear() }
    function appear() { settleWait.stop(); grow.restart() }
    Component.onDestruction: if (visible) Tip.popups--
    function toggle() {
        if (visible) close()
        else if (Date.now() - closedAt > 250) visible = true
    }
    function close() { if (visible && !shut.running) { settleWait.stop(); shut.restart() } }

    NumberAnimation { id: grow; target: wrap; property: "progress"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: shut
        // OutCubic, not InCubic: with opacity at 1.8x progress, InCubic held the card
        // fully opaque for ~100ms and then popped it out
        NumberAnimation { target: wrap; property: "progress"; to: 0; duration: 150; easing.type: Easing.OutCubic }
        ScriptAction { script: pop.visible = false }
    }

    Item { id: hit; anchors.fill: parent; anchors.margins: pop.shadowPad }

    Item {
        id: wrap
        property real progress: 0
        anchors.fill: parent
        anchors.margins: pop.shadowPad
        opacity: Math.min(1, progress * 1.8)
        scale: 0.94 + 0.06 * progress
        transformOrigin: Item.Top
        transform: Translate { y: (1 - wrap.progress) * -10 }
        // on the card's ancestor, so hovering anything inside it counts
        HoverHandler { id: cardHover }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.mainBg
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.5; shadowBlur: 1; shadowVerticalOffset: 4; blurMax: 24 }
        }
        Rectangle {
            id: card
            anchors.fill: parent
            radius: Theme.radius
            color: Qt.alpha(Theme.mainBg, pop.bgAlpha)
            border.color: Qt.alpha(Theme.mainFg, 0.35)
            border.width: 1

            Item {
                id: body
                x: pop.padX
                y: pop.padY
                width: childrenRect.width
                height: childrenRect.height
            }
        }
    }
}
