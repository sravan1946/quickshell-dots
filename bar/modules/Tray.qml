import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs
import qs.components

// tray: left = activate, middle = secondary, right = app menu, scroll = app scroll.
// Like waybar, left-click opens the menu for items that can't be activated.
Row {
    id: tray

    // Ids of items with no Activate method (libayatana-appindicator apps such as
    // nm-applet, plus Slack). Quickshell's activate() can't report the failure
    // waybar falls back on, so ask D-Bus directly.
    property var menuOnly: []

    Process {
        id: probe
        command: ["sh", "-c", `
            busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher \\
                org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems | grep -o '"[^"]*"' | tr -d '"' |
            while read -r s; do
                case $s in */*) b=\${s%%/*}; p=/\${s#*/};; *) b=$s; p=/StatusNotifierItem;; esac
                busctl --user introspect "$b" "$p" org.kde.StatusNotifierItem 2>/dev/null | grep -q '^\\.Activate ' ||
                    busctl --user get-property "$b" "$p" org.kde.StatusNotifierItem Id | cut -d'"' -f2
            done`]
        stdout: StdioCollector { onStreamFinished: tray.menuOnly = text.split("\n").filter(s => s) }
    }
    // Items register one by one (all at once when we become the tray watcher), and
    // setting running on a busy Process is a no-op, so debounce and retry until idle.
    Timer {
        id: reprobe
        interval: 500
        onTriggered: probe.running ? restart() : probe.running = true
    }
    Component.onCompleted: reprobe.start()
    // past startup: icons that show up after this grow in
    property bool settled: false
    Timer { running: true; interval: 1000; onTriggered: tray.settled = true }

    // Theme-named tray icons: GTK/waybar draw the 16px design (via 16@2x) at fractional
    // scale, but Quickshell asks the theme for 16*1.5 = 24px and gets the 24px design,
    // whose glyph is drawn ~1/3 smaller. Find the 16px file ourselves (Util.findIcon); the
    // icon then renders the SVG crisp at device size.
    Repeater {
        model: SystemTray.items
        onCountChanged: reprobe.restart()

        Mod {
            id: item
            required property SystemTrayItem modelData
            readonly property bool leftOpensMenu: modelData.onlyMenu || tray.menuOnly.includes(modelData.id)
            visible: modelData.status !== Status.Passive   // waybar show-passive-items: false
            growIn: tray.settled
            // "image://icon/<name>?path=<IconThemePath>" for theme icons, pixmaps otherwise
            readonly property string themeIcon: modelData.icon.startsWith("image://icon/") ? modelData.icon.slice(13).split("?")[0] : ""
            readonly property string themePath: decodeURIComponent((modelData.icon.match(/[?&]path=([^&]+)/) ?? [])[1] ?? "")
            property string resolved: ""
            onThemeIconChanged: { resolved = ""; finder.running = false; finder.running = themeIcon !== "" }
            Component.onCompleted: finder.running = themeIcon !== ""
            Process {
                id: finder
                command: ["sh", "-c", Util.findIcon, "sh", item.themeIcon, item.themePath]
                stdout: StdioCollector { onStreamFinished: item.resolved = text.trim() ? "file://" + text.trim() : "" }
            }
            icon: resolved || modelData.icon
            // waybar: bold title, then the description (SNI allows basic markup there)
            tip: modelData.tooltipTitle
                ? `<b>${modelData.tooltipTitle}</b>` + (modelData.tooltipDescription ? "<br>" + modelData.tooltipDescription : "")
                : modelData.title
            onClicked: b => {
                if (b === Qt.RightButton || (b === Qt.LeftButton && leftOpensMenu)) {
                    if (modelData.hasMenu) menu.toggle()
                } else if (b === Qt.LeftButton) modelData.activate()
                else if (b === Qt.MiddleButton) modelData.secondaryActivate()
            }
            onScrolled: s => modelData.scroll(s, false)

            Menu { id: menu; target: item; handle: item.modelData.menu }
        }
    }
}
