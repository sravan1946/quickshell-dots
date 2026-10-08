import QtQuick
import QtQuick.Layouts
import qs

// One-of-n chips (SettingsPanel): `value` is the picked index, picked(i) on a click.
Flow {
    id: sc
    property var names: []
    property int value: 0
    signal picked(int i)
    Layout.fillWidth: true
    spacing: 6
    Repeater {
        model: sc.names
        PillButton {
            required property string modelData
            required property int index
            implicitHeight: 24
            checked: sc.value === index
            text: (checked ? Theme.g(0xF012C) + " " : "") + modelData
            onClicked: sc.picked(index)
        }
    }
}
