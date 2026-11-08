import QtQuick

// Text in the bar's face, with tabular figures so numbers never change width.
Text {
    color: Look.text
    font.family: Look.sans
    font.pixelSize: Look.size
    font.features: ({ tnum: 1 })
    verticalAlignment: Text.AlignVCenter
}
