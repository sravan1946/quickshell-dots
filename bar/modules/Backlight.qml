import QtQuick
import qs
import qs.components

// backlight: scroll to change brightness. State lives in Brightness.qml. State lives in Brightness.qml.
Mod {
    readonly property var icons: [0xE38D, 0xE3D3, 0xE3D1, 0xE3CF, 0xE3CE, 0xE3CD, 0xE3CA, 0xE3C8, 0xE39B]
    readonly property string ico: Util.pick(icons, Brightness.pct)

    minChars: 6
    text: `${ico} ${Brightness.pct}%`
    tip: `Backlight level: ${ico} ${Brightness.pct}%`
    onScrolled: s => Brightness.step(s)
}
