import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components

PanelWindow {
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: Config.height
    visible: Config.barVisible
    color: Theme.barBg
    WlrLayershell.namespace: "waybar"   // picks up HyDE's waybar blur layerrule
    // Normally keyboard-free, so clicking the bar doesn't steal focus from apps. While one of
    // its popups is open it may take focus on click: popups inherit this, and a text field
    // (calendar quick-add, Wi-Fi password) asking for focus on a no-keyboard surface made
    // Hyprland drop the popup.
    WlrLayershell.keyboardFocus: Tip.popups > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // A real fullscreen window (mode 2, not maximise) covers the bar: stop drawing it, or the
    // beat effects keep repainting it 30 times a second behind the window. The workspace only
    // says it has *a* fullscreen window, so each toplevel's mode is re-read on every change.
    readonly property var workspace: Hyprland.monitorFor(modelData)?.activeWorkspace ?? null
    readonly property bool covered: !!workspace?.hasFullscreen
        && workspace.toplevels.values.some(t => (t.lastIpcObject.fullscreen ?? 0) & 2)
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "fullscreen") Hyprland.refreshToplevels() }
    }

    // beat waves along the bottom edge (shaders/bar.frag), from the media pill, which sets
    // beatX on each kick. Spent waves stop changing the uniforms, so the bar only repaints
    // while one is running.
    property real beatX: width / 4
    ShaderEffect {
        anchors.fill: parent
        visible: Visualizer.active && !covered
        readonly property vector2d res: Qt.vector2d(width, height)
        readonly property real ox: beatX
        readonly property vector4d fronts: Visualizer.waveFronts
        readonly property vector4d fades: Visualizer.waveFades
        readonly property real reach: Visualizer.waveReach
        readonly property real dur: Visualizer.waveDur
        readonly property vector4d kr: Visualizer.beatR
        readonly property vector4d kg: Visualizer.beatG
        readonly property vector4d kb: Visualizer.beatB
        // Qt caches shaders by URL across reloads: shaders/build.sh stamps ?v= with the .qsb hash
        fragmentShader: Qt.resolvedUrl("shaders/bar.frag.qsb?v=2a01f86c")
    }

    // a click on the bar's empty space closes any open click popup (a module's own click
    // never reaches this: its MouseArea is on top)
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: Tip.barPressed(null)
    }

    // HyDE margins: .modules-left 0, .modules-right 0.2em margin + 0.2em padding
    Section { visible: !covered; side: "left"; anchors.left: parent.left }
    Section { visible: !covered; side: "center"; anchors.horizontalCenter: parent.horizontalCenter }
    Section { visible: !covered; side: "right"; anchors.right: parent.right; anchors.rightMargin: 4 }

    Tooltip { screen: modelData }
}
