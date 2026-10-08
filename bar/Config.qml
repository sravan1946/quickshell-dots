pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Bar layout. Each entry is one pill; `modules` are file names in modules/.
//
//   shape: "full" (default) | "right" (flat left edge) | "left" (flat right edge) | "down" (flat top)
//   padL / padR: inner horizontal padding in px (default 6)
//
// To add a module: drop modules/Foo.qml (root an Item/Row, use components/Mod for
// the look) and add "Foo" to a pill below. Saving reloads the bar live.
Singleton {
    readonly property int height: 30
    // pills sit this far off the bar's top and bottom edges; their hover/click areas reach
    // back out over it, so a pointer pinned to the screen edge still lands on them
    readonly property int pillInset: 3
    property bool dnd: false         // do-not-disturb: notification popups hidden, kept until it's turned off
    property bool historyOpen: false // notification history panel is open (popups are suppressed)
    property bool historyPaused: false // stop logging to the history; popups still work as normal
    property int held: 0             // notifications currently tracked (shown as the DND badge)
    signal toggleHistory()           // asks the Dnd module to open/close its history panel
    property bool caffeine: false    // idle inhibitor, shared by every bar's Idle module and quick settings
    property bool quickOpen: false   // a quick-settings panel is open (the OSD stays quiet meanwhile)
    signal toggleQuick()             // `qs -c bar ipc call quick toggle`: open/close it on the focused monitor
    property bool settingsOpen: false // the central settings GUI (SettingsPanel) is open
    signal openSettings()            // asks the one SettingsPanel to open on the focused monitor
    signal togglePower()             // opens/closes the power menu (PowerMenu.qml) on the focused monitor
    property bool barVisible: true   // toggled by `qs -c bar ipc call bar toggle` (SUPER+CTRL+B)

    // DND survives qs restarts
    onDndChanged: if (dndFile.loaded) dndFile.setText(JSON.stringify({ dnd }))
    FileView {
        id: dndFile
        property bool loaded: false
        path: Quickshell.env("HOME") + "/.cache/quickshell-dnd.json"
        printErrors: false
        onLoaded: {
            try { dnd = !!JSON.parse(text()).dnd } catch (e) {}
            loaded = true
        }
        onLoadFailed: loaded = true   // first run: no file yet
    }

    readonly property var left: [
        { shape: "right", padL: 4, padR: 4, modules: ["SysStats"] },
        { padL: 4, modules: ["Workspaces"] },
        { padL: 0, padR: 0, modules: ["Media"] },
    ]
    readonly property var center: [
        { shape: "down", modules: ["Idle", "Clock", "Dnd"] },
    ]
    readonly property var right: [
        { modules: ["Network", "Privacy", "Tray", "Battery"] },
        { modules: ["Taskbar"] },
        { shape: "left", modules: ["Backlight", "Volume"] },
    ]
}
