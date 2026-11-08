import QtQuick

// ColorAnimation on the effects token: colours never overshoot.
ColorAnimation {
    duration: Look.ms("effects")
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Look.curves.effects
}
