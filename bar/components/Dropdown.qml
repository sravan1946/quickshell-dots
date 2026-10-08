import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs

// Themed click popup under `target` (detail panels, menus): the liquid card every other
// panel uses (components/LiquidCard), poured out under the module and drained back into it.
// closeOnOutsideClick: closes on a click outside it and the bar (HyprlandFocusGrab), and when
// another popup opens or the bar's empty space is clicked (Tip). The card sits shadowPad inside the
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
    readonly property real shadowPad: 28   // LiquidCard's shadow: blur 32, 5 down

    anchor.item: target
    anchor.rect: Qt.rect(0, 0, target?.width ?? 0, (target?.height ?? 0) + 6 - shadowPad)
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    color: "transparent"
    implicitWidth: body.childrenRect.width + 2 * padX + 2 * shadowPad
    implicitHeight: body.childrenRect.height + 2 * padY + 2 * shadowPad
    // input only on the card's area, not the shadow room around it
    mask: Region { item: hit }

    // Not an xdg popup grab (grabFocus): when one of those ended, Hyprland left pointer focus
    // nowhere until the pointer moved, so the next click in the same spot did nothing. This
    // one lets the popup and the bar take input normally: a click on the module goes to the
    // module (toggle), anywhere else clears the grab and closes us.
    HyprlandFocusGrab {
        id: grab
        windows: [pop, pop.target?.QsWindow.window ?? pop]
        onCleared: pop.close()
    }
    Connections {
        target: Tip
        function onPopupOpened(p) { if (p !== pop) pop.close() }
        function onBarPressed(m) { if (m !== pop.target) pop.close() }
    }

    // Clicking the module that opened us first dismisses the grab (closing us),
    // then toggles; don't reopen in that case.
    property real closedAt: 0
    property bool leaving: false
    readonly property bool opened: card.progress >= 1   // fully poured: content can start changing size
    // pours out of / drains into the top middle of the card, under the module that opened it
    readonly property point spout: Qt.point(card.x + card.width / 2, card.y)
    onVisibleChanged: {
        if (visible) {
            Tip.hide(); Tip.popups++; leaving = false; settleWait.restart(); settle()
            Tip.popupOpened(pop)
            grab.active = closeOnOutsideClick
        } else { Tip.popups--; closedAt = Date.now(); leaving = false; card.reset(); settleWait.stop(); grab.active = false }
    }
    // A fresh popup maps at the wrong scale: on the 1.5x screen its dpr goes 2 -> 1 -> 1.5
    // over ~100ms, and those frames draw the card zoomed (a flicker). Stay invisible until
    // it matches the bar's dpr; give up waiting after 250ms.
    onDevicePixelRatioChanged: settle()
    function settle() { if (settleWait.running && devicePixelRatio === target?.QsWindow.window?.devicePixelRatio) appear() }
    Timer { id: settleWait; interval: 250; onTriggered: pop.appear() }
    function appear() { settleWait.stop(); card.pour(spout) }
    Component.onDestruction: if (visible) Tip.popups--
    function toggle() {
        if (visible && !leaving) close()
        else if (visible) { leaving = false; card.pour(spout) }   // reopened mid-drain
        else if (Date.now() - closedAt > 250) visible = true
    }
    function close() { if (visible && !leaving) { leaving = true; settleWait.stop(); grab.active = false; card.drain(spout) } }

    Item { id: hit; anchors.fill: parent; anchors.margins: pop.shadowPad }

    // the liquid card the other panels use (components/LiquidCard): poured out on open,
    // drained on close; its shadow sits in the shadowPad around it
    LiquidCard {
        id: card
        x: pop.shadowPad
        y: pop.shadowPad
        width: parent.width - 2 * pop.shadowPad
        height: parent.height - 2 * pop.shadowPad
        radius: Theme.radius
        color: Qt.alpha(Theme.mainBg, pop.bgAlpha)
        border.color: Qt.alpha(Theme.mainFg, 0.35)
        border.width: 1
        // quick, and still moving at the end (end slope ~0.6): the tall panels don't crawl
        formCurve: [0.25, 0.6, 0.6, 0.76, 1, 1]
        formTime: 450
        onClosed: if (pop.leaving) pop.visible = false
        // on the card itself, so hovering anything inside it counts
        HoverHandler { id: cardHover }

        Item {
            id: body
            x: pop.padX
            y: pop.padY
            width: childrenRect.width
            height: childrenRect.height
        }
    }
}
