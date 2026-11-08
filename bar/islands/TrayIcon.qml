import QtQuick
import Quickshell
import qs.components

// A tray item's icon. Theme-named icons are looked up as files (components/IconFile): the
// icon provider hands back the 24px design at 1.5x, whose glyph is drawn a third smaller.
Image {
    id: ic
    property var item
    readonly property string themeIcon: item.icon.startsWith("image://icon/") ? item.icon.slice(13).split("?")[0] : ""
    readonly property string themePath: decodeURIComponent((item.icon.match(/[?&]path=([^&]+)/) ?? [])[1] ?? "")
    IconFile { id: finder; name: ic.themeIcon; extra: ic.themePath }
    source: finder.file || item.icon
    width: 14
    height: 14
    sourceSize: Qt.size(30, 30)
    smooth: true
    mipmap: true
    anchors.verticalCenter: parent?.verticalCenter
}
