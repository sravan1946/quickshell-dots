import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs
import qs.components

// The playing track's cover (Player.artFile), rounded; greyed out while paused.
ClippingRectangle {
    id: c
    readonly property bool settled: art.settled
    color: Qt.alpha(Look.warm, 0.18)
    anchors.verticalCenter: parent?.verticalCenter
    G {
        anchors.centerIn: parent
        visible: !art.ready
        glyph: 0xF075A
        font.pixelSize: c.height * 0.55
        color: Look.warm
    }
    Art {
        id: art
        anchors.fill: parent
        sourceSize: Qt.size(c.width * 2, c.height * 2)
        // a still effect while paused, none while playing (rule 17)
        layer.enabled: !Player.playing
        layer.effect: MultiEffect { saturation: -1; brightness: -0.3 }
    }
}
