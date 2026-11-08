import QtQuick
import qs
import qs.islands

// Caffeine: keep the screen and the laptop awake.
Panel {
    implicitWidth: 250
    Head { text: "Caffeine"; Switch { on: Config.caffeine; onToggled: Config.caffeine = !Config.caffeine } }
    T {
        width: parent.width
        text: Config.caffeine ? "On: the screen won't dim or lock, and the laptop won't sleep."
            : "Off: the screen dims and locks as usual. Click the cup to stay awake."
        color: Look.dim
        font.pixelSize: Look.small
        wrapMode: Text.Wrap
        lineHeight: 1.2
    }
}
