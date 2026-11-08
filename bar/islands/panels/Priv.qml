import QtQuick
import qs.islands

// Who is using the mic or capturing the screen.
Panel {
    implicitWidth: 250
    spacing: 4
    Head { text: "Privacy" }
    Repeater {
        model: PrivState.mics
        Choice {
            required property var modelData
            clickable: false
            title: PrivState.app(modelData) + " is using the mic"
            G { anchors.centerIn: parent; glyph: 0xF036C; color: Look.alert }
        }
    }
    Repeater {
        model: PrivState.casts
        Choice {
            required property var modelData
            clickable: false
            title: PrivState.app(modelData) + " is capturing the screen"
            G { anchors.centerIn: parent; glyph: 0xF0379; color: Look.alert }
        }
    }
    Choice {
        visible: PrivState.screencast && !PrivState.casts.length
        clickable: false
        title: "The screen is being captured"
        G { anchors.centerIn: parent; glyph: 0xF0379; color: Look.alert }
    }
}
