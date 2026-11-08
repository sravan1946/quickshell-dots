pragma Singleton
import QtQuick
import Quickshell

// Names and ids for Hyprland windows: the desktop entry's name ("Brave", not
// "brave-browser"), else the app id.
Singleton {
    function id(t) { return t?.wayland?.appId || t?.lastIpcObject?.class || "" }
    function entry(appId) { return appId ? DesktopEntries.heuristicLookup(appId) ?? DesktopEntries.heuristicLookup(appId.toLowerCase()) : null }
    function name(t) {
        const a = id(t)
        const n = entry(a)?.name ?? a
        return n.length > 18 ? n.split(" ")[0] : n
    }
    // icon themes name files in lower case ("Termius" -> termius.svg)
    function icon(appId) { return entry(appId)?.icon || appId.toLowerCase() }
}
