import QtQuick

// A NumberAnimation on one of Look's motion tokens: spatial and fast for geometry (they may
// overshoot), effects for opacity and colour, enter/exit for arrivals and departures.
NumberAnimation {
    property string type: "spatial"
    duration: Look.ms(type)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Look.curves[type]
}
