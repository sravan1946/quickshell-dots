import QtQuick
import Quickshell.Hyprland
import qs.islands

// The window you're in: its app, its whole title, where it is, and fullscreen / close.
Panel {
    id: p
    implicitWidth: 300
    readonly property var w: hit?.focused ?? null
    readonly property var o: w?.lastIpcObject ?? ({})

    Row {
        width: parent.width
        spacing: 12
        AppIcon { appId: Apps.id(p.w); size: 34 }
        Column {
            width: parent.width - 46
            anchors.verticalCenter: parent.verticalCenter
            T { text: p.w ? Apps.name(p.w) : ""; font.pixelSize: 14; font.weight: Font.DemiBold }
            T {
                text: [p.w?.workspace ? "Workspace " + p.w.workspace.name : "", p.o.floating ? "floating" : "tiled",
                    p.o.xwayland ? "XWayland" : ""].filter(s => s).join(" · ")
                color: Look.dim
                font.pixelSize: Look.small
            }
        }
    }
    T {
        width: parent.width
        text: p.w?.title ?? ""
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        color: Look.dim
        lineHeight: 1.15
    }
    Row {
        spacing: 8
        Btn { text: p.w?.wayland?.fullscreen ? "Leave fullscreen" : "Fullscreen"; onClicked: { if (p.w?.wayland) p.w.wayland.fullscreen = !p.w.wayland.fullscreen; p.ctl.hide() } }
        Btn { text: "Close"; onClicked: { p.w?.wayland?.close(); p.ctl.hide() } }
    }
}
