import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.components

// idle_inhibitor ("caffeine"): click to keep the system awake.
Mod {
    IdleInhibitor { id: inhibitor; window: QsWindow.window; enabled: Config.caffeine }

    text: Theme.g(inhibitor.enabled ? 0xF0176 : 0xF06CA)
    tip: inhibitor.enabled
        ? `<font color="#98c379">${Theme.g(0xF0176)} Caffeine Mode Active</font><br>Prevents system from going to sleep`
        : `<font color="#e06c75">${Theme.g(0xF06CA)} Caffeine Mode Inactive</font><br>System will follow normal power settings`
    onClicked: Config.caffeine = !Config.caffeine
}
