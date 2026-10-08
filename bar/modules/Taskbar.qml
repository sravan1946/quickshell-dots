import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components

// wlr/taskbar: click to focus, middle-click to close. Only windows on this bar's monitor.
// The monitor comes from Hyprland, not Toplevel.screens: when a monitor is unplugged its
// windows leave that output but never "enter" the one they move to, so screens stays empty.
Item {
    id: root
    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    implicitWidth: row.implicitWidth

    // past startup: buttons that show up after this grow in
    property bool settled: false
    Timer { running: true; interval: 1000; onTriggered: root.settled = true }

    ActiveSlide { id: slide }

    Row {
        id: row
        height: parent.height
        Repeater {
            model: Hyprland.toplevels
            Mod {
                id: win
                required property HyprlandToplevel modelData
                readonly property Toplevel w: modelData.wayland
                readonly property bool here: !!w && modelData.workspace?.monitor?.name === root.screenName
                visible: here
                button: true
                growIn: root.settled
                active: here && (w?.activated ?? false)   // a focused window on another monitor isn't ours to highlight
                activeBg: "transparent"
                onActiveChanged: if (active) slide.take(win)
                readonly property string iconName: w ? DesktopEntries.heuristicLookup(w.appId)?.icon ?? w.appId : ""
                // the app's own icon file (Util.findIcon: crisp at any scale), the provider until then
                Component.onCompleted: if (active) slide.take(win)
                IconFile { id: finder; name: iconName; sizes: "scalable 256x256 128x128 96x96 64x64 48x48 32x32" }
                icon: finder.file || (iconName ? Quickshell.iconPath(iconName, "application-x-executable") : "")
                tip: w?.title ?? ""
                onClicked: b => b === Qt.MiddleButton ? w?.close() : w?.activate()
            }
        }
    }
}
