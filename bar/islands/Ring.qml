import QtQuick
import QtQuick.Shapes

// A small usage ring (cpu, memory), warming to amber and red as it fills.
Item {
    id: ring
    property real value: 0          // 0..100
    property color base: Look.accent
    readonly property color col: value > 85 ? Look.alert : value > 65 ? Look.urgent : base
    property real shown: value
    Behavior on shown { Anim { type: "effects" } }

    implicitWidth: 14
    implicitHeight: 14
    anchors.verticalCenter: parent?.verticalCenter

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.alpha("white", 0.12)
            strokeWidth: 2.2
            fillColor: "transparent"
            PathAngleArc { centerX: 7; centerY: 7; radiusX: 5.2; radiusY: 5.2; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: ring.col
            strokeWidth: 2.2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: 7; centerY: 7; radiusX: 5.2; radiusY: 5.2; startAngle: -90; sweepAngle: 360 * Math.max(0.01, Math.min(1, ring.shown / 100)) }
        }
    }
}
