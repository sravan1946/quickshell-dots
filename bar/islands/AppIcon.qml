import QtQuick
import Quickshell
import qs.components

// An app's icon from its theme file (crisp at 1.5x; components/IconFile), the icon provider
// until that's found.
Image {
    id: ic
    property string appId: ""
    property int size: 16
    readonly property string iconName: Apps.icon(appId)
    IconFile { id: finder; name: ic.iconName; sizes: "scalable 256x256 128x128 96x96 64x64 48x48 32x32" }
    source: finder.file || (iconName ? Quickshell.iconPath(iconName, "application-x-executable") : "")
    width: size
    height: size
    sourceSize: Qt.size(size * 2, size * 2)
    smooth: true
    mipmap: true
    anchors.verticalCenter: parent?.verticalCenter
}
