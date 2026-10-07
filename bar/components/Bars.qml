import QtQuick
import qs

// Wi-Fi strength as four rising bars
Row {
    property int strength: 0
    spacing: 2
    Repeater {
        model: 4
        Rectangle {
            required property int index
            anchors.bottom: parent.bottom
            width: 3
            height: 4 + index * 3
            radius: 1
            color: Theme.mainFg
            opacity: parent.strength > index * 25 ? 1 : 0.22
        }
    }
}
