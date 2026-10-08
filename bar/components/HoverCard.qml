import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Hover card for a bar module, poured out of the point where the pointer rested and eaten
// away from where it left (components/LiquidCard). Declare it inside the
// module: it opens after a short dwell there and stays while the pointer is on the module
// or the card. `content` is built only while the card is up.
Item {
    id: hc

    property Component content
    property color glow: Theme.mainFg
    property bool blocked: false     // keep it shut, e.g. while the module's click panel is open
    property bool open: false
    property point from              // screen point it pours out of / drains into
    property real centerX: 0         // module centre on screen, taken on open

    function close() { dwell.stop(); open = false }

    anchors.fill: parent
    onBlockedChanged: if (blocked) close()

    // passive: sees the pointer over the whole module without taking it from Mod's MouseArea
    HoverHandler {
        id: modHover
        property point last   // kept for where the pointer leaves
        onPointChanged: if (hovered) last = hc.mapToItem(null, point.position.x, point.position.y)
        onHoveredChanged: {
            if (hovered) { closer.stop(); if (!hc.open && !hc.blocked) dwell.restart() }
            else {
                dwell.stop()
                hc.from = last
                closer.interval = 300   // time to cross the gap down onto the card
                closer.restart()
            }
        }
    }
    // a short dwell, as on the media pill, so sweeping across the bar doesn't pop it open
    Timer {
        id: dwell
        interval: Settings.hoverDelay
        onTriggered: {
            hc.from = modHover.last
            hc.centerX = hc.mapToItem(null, hc.width / 2, 0).x
            hc.open = true
        }
    }
    Timer { id: closer; onTriggered: if (!modHover.hovered && !cardHover.hovered) hc.open = false }

    // `from` is on screen; the window starts at the screen's left edge, margins.top down
    onOpenChanged: {
        const p = Qt.point(from.x, from.y - win.margins.top)
        if (open) card.pour(p); else card.drain(p)
    }

    // full width, input only on the card: the card can sit anywhere under the bar with room for its shadow
    PanelWindow {
        id: win
        screen: hc.QsWindow.window?.screen ?? null
        visible: card.progress > 0
        anchors { top: true; left: true; right: true }
        margins.top: Config.height + 4
        implicitHeight: card.height + 48
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region { item: card }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bar-hovercard"

        LiquidCard {
            id: card
            x: Math.max(8, Math.min(win.width - width - 8, hc.centerX - width / 2))
            y: 4
            width: body.implicitWidth + 28
            height: body.implicitHeight + 24
            radius: Theme.radius + 4
            color: Theme.mainBg
            border.color: Qt.alpha(hc.glow, 0.3)
            border.width: 1
            glow: hc.glow

            HoverHandler {
                id: cardHover
                property point last
                onPointChanged: if (hovered) last = Qt.point(card.x + point.position.x, win.margins.top + card.y + point.position.y)
                onHoveredChanged: {
                    if (hovered) closer.stop()
                    else if (hc.open) {
                        hc.from = last
                        closer.interval = 150   // just enough to cross back to the module
                        closer.restart()
                    }
                }
            }

            Loader {
                id: body
                x: 14
                y: 12
                active: hc.open || card.progress > 0
                sourceComponent: hc.content
            }
        }
    }
}
