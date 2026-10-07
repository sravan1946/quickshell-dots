import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs

// One hover bubble per bar (see Tip.qml). It springs between modules, resizing as
// it goes, and cross-fades the text; live updates of the same tip swap in place.
// The window spans the bar's width below it and takes no input.
PanelWindow {
    id: win

    // The module to point at. Set from signals (deferred), not a binding: reading a
    // module's tip can touch popup state that changes Tip mid-evaluation (a binding loop).
    property Item t: null
    property bool snap: false     // dismissed by a click: drop the bubble without fading
    function pick() {
        const m = Tip.target
        t = m && Tip.popups === 0 && (m.tip !== "" || m.tipItem) && Tip.screen === (screen?.name ?? "") ? m : null
    }
    Connections {
        target: Tip
        function onTargetChanged() { Qt.callLater(win.pick) }
        function onPopupsChanged() { Qt.callLater(win.pick) }
        function onScreenChanged() { Qt.callLater(win.pick) }
        function onDismissed() { win.snap = true; win.t = null }
    }
    property real tx: 0
    property real tw: 0
    property string shown: ""
    property Component shownItem: null

    anchors { top: true; left: true; right: true }
    margins.top: Config.height
    implicitHeight: 480
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    // always mapped (it's transparent and takes no input): unmapping it right as a click
    // popup opens made Hyprland re-pick pointer focus and dismiss the popup's grab
    visible: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "bar-tooltip"

    // the module's x in the bar window; both windows start at the screen's left edge
    function place() { if (t) { const p = t.mapToItem(null, 0, 0); tx = p.x; tw = t.width } }
    onTChanged: {
        if (!t) return
        snap = false
        place()
        if (bubble.opacity < 0.05) take()
        else swap.restart()
    }
    function take() { shown = t.tip; shownItem = t.tipItem }
    Connections {
        target: win.t
        function onTipChanged() {
            if (win.t.tip === "" && !win.t.tipItem) Qt.callLater(win.pick)
            else if (!swap.running) win.shown = win.t.tip
        }
    }
    Timer { interval: 250; repeat: true; running: !!win.t; onTriggered: win.place() }   // neighbours resize

    SequentialAnimation {
        id: swap
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 70 }
        ScriptAction { script: if (win.t) win.take() }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 130 }
    }

    Item {
        id: bubble
        readonly property bool live: opacity > 0.05   // already on screen: glide, don't jump
        x: Math.max(8, Math.min(win.width - width - 8, win.tx + win.tw / 2 - width / 2))
        y: 7
        width: content.width + 24
        height: content.height + 14
        opacity: win.t ? 1 : 0
        scale: win.t ? 1 : 0.92
        transformOrigin: Item.Top

        // pop in eased, not sprung: a bouncing scale wobbles the text. Leaving is quicker.
        Behavior on opacity { id: fade; enabled: !win.snap; NumberAnimation { duration: fade.targetValue > 0 ? 160 : 110; easing.type: Easing.OutCubic } }
        Behavior on scale { id: pop; enabled: !win.snap; NumberAnimation { duration: pop.targetValue === 1 ? 200 : 110; easing.type: Easing.OutCubic } }
        // the glide keeps a spring (it carries velocity across quick retargets), damped
        // enough that it settles with one small overshoot instead of wobbling
        Behavior on x { enabled: bubble.live; SpringAnimation { spring: 4; damping: 0.55; epsilon: 0.3 } }
        Behavior on width { enabled: bubble.live; SpringAnimation { spring: 4.5; damping: 0.6; epsilon: 0.3 } }
        Behavior on height { enabled: bubble.live; SpringAnimation { spring: 4.5; damping: 0.6; epsilon: 0.3 } }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.mainBg
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.45; shadowBlur: 0.8; shadowVerticalOffset: 3; blurMax: 20 }
        }
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.mainBg
            border.color: Qt.alpha(Theme.mainFg, 0.35)
            border.width: 1
            clip: true
            Item {
                id: content
                x: 12
                y: 7
                width: win.shownItem ? (custom.item?.width ?? 0) : label.implicitWidth
                height: win.shownItem ? (custom.item?.implicitHeight ?? 0) : label.implicitHeight
                Label {
                    id: label
                    visible: !win.shownItem
                    text: win.shown
                    textFormat: Text.RichText
                }
                Loader { id: custom; sourceComponent: win.shownItem }
            }
        }
    }
}
