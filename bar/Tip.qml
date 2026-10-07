pragma Singleton
import QtQuick
import Quickshell

// Which bar module the hover tooltip points at; components/Tooltip.qml draws it.
// The first hover waits `delay`; once a tooltip is up, moving to another module
// retargets it straight away, so the bubble glides along the bar instead of blinking.
Singleton {
    id: root

    property Item target: null     // module shown (null = hidden)
    property Item pending: null    // module under the pointer, waiting out the delay
    property string screen: ""     // monitor of the hovered module: only that bar draws it
    property int popups: 0         // click popups open: tooltips stay away meanwhile
    readonly property int delay: 400

    function hover(m, screenName) {
        grace.stop()
        screen = screenName
        pending = m
        if (target) target = m
        else wait.restart()
    }
    function leave(m) {
        if (pending === m) { pending = null; wait.stop() }
        if (target === m) grace.restart()   // short grace: the gap between two modules isn't a leave
    }
    // clicks and popups: the bubble goes at once instead of fading over the popup
    signal dismissed()
    function hide() { wait.stop(); grace.stop(); target = null; pending = null; dismissed() }

    Timer { id: wait; interval: root.delay; onTriggered: if (root.popups === 0) root.target = root.pending }
    Timer { id: grace; interval: 140; onTriggered: root.target = null }
}
