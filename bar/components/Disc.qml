import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs

// A record: dark vinyl with faint grooves and the cover art as its label, under a light
// sheen that stays put while the record turns. Spins up while the player plays and winds
// down on pause, like a turntable. `label: 1` makes it all cover (the tiny one in the bar).
Item {
    id: d
    property real label: 0.45      // label diameter as a fraction of the record
    property int rpm: 12           // slower than a real 33 1/3: easier to watch
    property bool spinning: true   // false parks the animation (hidden panel)
    readonly property bool grooved: label < 1
    // rpm right now: eases up on play and winds down on pause (slower, as a platter coasts)
    property real speed: Player.playing ? rpm : 0
    Behavior on speed { NumberAnimation { duration: Player.playing ? 700 : 1400; easing.type: Easing.OutCubic } }

    Item {
        id: spinner
        anchors.fill: parent
        FrameAnimation {
            running: d.spinning && d.speed > 0
            onTriggered: spinner.rotation = (spinner.rotation + d.speed * 6 * frameTime) % 360
        }

        Rectangle {
            visible: d.grooved
            anchors.fill: parent
            radius: width / 2
            color: "#0e0f14"
            border.color: Qt.alpha(Player.c1, 0.25)
            border.width: 1
        }
        Repeater {
            model: d.grooved ? 14 : 0
            Rectangle {
                required property int index
                anchors.centerIn: parent
                width: d.width * (d.label + 0.04 + index * (0.92 - d.label) / 14)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha("white", index % 4 === 0 ? 0.07 : 0.03)
            }
        }
        ClippingRectangle {
            id: lbl
            anchors.centerIn: parent
            width: d.width * d.label
            height: width
            radius: width / 2
            color: Qt.alpha(Player.c2, 0.35)
            Text {
                anchors.centerIn: parent
                visible: !art.ready
                text: Theme.g(0xF075A)
                color: Player.c1
                font { family: Theme.font; pixelSize: lbl.width * 0.5 }
            }
            Art {
                id: art
                anchors.fill: parent
                sourceSize: Qt.size(lbl.width * 2, lbl.width * 2)
            }
        }
        Rectangle {   // spindle hole
            anchors.centerIn: parent
            width: Math.max(3, d.width * 0.035)
            height: width
            radius: width / 2
            color: "#0e0f14"
            border.color: Qt.alpha("white", 0.2)
            border.width: d.grooved ? 1 : 0
        }
    }

    // fixed sheen: two soft light wedges across the vinyl, as from a lamp overhead
    Shape {
        visible: d.grooved
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: ConicalGradient {
                centerX: d.width / 2; centerY: d.height / 2
                angle: 60
                GradientStop { position: 0.00; color: "transparent" }
                GradientStop { position: 0.08; color: Qt.alpha("white", 0.10) }
                GradientStop { position: 0.16; color: "transparent" }
                GradientStop { position: 0.50; color: "transparent" }
                GradientStop { position: 0.58; color: Qt.alpha("white", 0.07) }
                GradientStop { position: 0.66; color: "transparent" }
                GradientStop { position: 1.00; color: "transparent" }
            }
            PathAngleArc {
                centerX: d.width / 2; centerY: d.height / 2
                radiusX: d.width / 2; radiusY: d.height / 2
                startAngle: 0; sweepAngle: 360
                moveToStart: true
            }
        }
    }
}
