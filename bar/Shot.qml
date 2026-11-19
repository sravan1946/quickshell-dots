import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.islands

// Screenshots, in place of HyDE's screenshot.sh binds.
// The focused monitor is frozen first (scripts/shot.sh freeze) and the overlay shows that frame,
// so nothing moves while you choose. Region: drag (a crosshair and a 4× loupe help aim; drag
// inside the selection to move it). Window: hover to light one up, click to take it. Screen:
// the whole monitor. Then: Enter saves and copies (as HyDE did), C copies, E opens it in satty,
// O reads its text into the clipboard (tesseract); a double-click saves. R/W/S switch mode,
// Esc cancels. The toolbar at the bottom does the same with the mouse.
// `qs -c bar ipc call shot region|window|screen|ocr` (overlay) and `full|monitor` (instant)
Scope {
    id: root

    property bool open: false
    property string mode: "region"        // region | window | screen
    property string after: ""             // run as soon as something is chosen (the OCR bind)
    property string frozen: ""
    property var mon: null                // hyprctl's monitor
    property var wins: []                 // its visible windows, in overlay coordinates, topmost first
    property rect sel: Qt.rect(0, 0, 0, 0)
    readonly property bool has: sel.width > 2 && sel.height > 2
    readonly property real dpr: mon?.scale ?? 1
    readonly property string script: Quickshell.shellDir + "/scripts/shot.sh"

    property real fade: open ? 1 : 0
    Behavior on fade { Anim { type: "effects" } }

    function start(m, act) {
        if (open || freeze.running) return
        mode = m
        after = act ?? ""
        sel = Qt.rect(0, 0, 0, 0)
        freeze.running = true
    }
    function setMode(m) {
        mode = m
        // the monitor's own size: the window may not be laid out yet when this runs on opening
        const w = win.screen?.width ?? win.width, h = win.screen?.height ?? win.height
        sel = m === "screen" ? Qt.rect(0, 0, w, h) : Qt.rect(0, 0, 0, 0)
    }
    function run(action) {
        if (!has) return
        const r = sel, s = dpr
        const x = Math.round(r.x * s), y = Math.round(r.y * s)
        const geom = `${Math.round((r.x + r.width) * s) - x}x${Math.round((r.y + r.height) * s) - y}+${x}+${y}`
        Quickshell.execDetached([script, "crop", frozen, geom, action])
        open = false
    }

    Process {
        id: freeze
        command: [root.script, "freeze"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                let m, cl = []
                try { m = JSON.parse(lines[1]) } catch (e) { return }
                try { cl = JSON.parse(lines[2]) } catch (e) {}
                const ws = [m.activeWorkspace?.id, m.specialWorkspace?.id].filter(id => id)
                root.wins = cl.filter(c => c.mapped && !c.hidden && ws.includes(c.workspace.id))
                    .sort((a, b) => (b.workspace.id < 0) - (a.workspace.id < 0) || b.floating - a.floating || a.focusHistoryID - b.focusHistoryID)
                    .map(c => ({ x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1], title: c.title }))
                root.mon = m
                root.frozen = lines[0]
                root.open = true
                root.setMode(root.mode)
            }
        }
    }

    IpcHandler {
        target: "shot"
        function region(): void { root.start("region") }
        function window(): void { root.start("window") }
        function screen(): void { root.start("screen") }
        function ocr(): void { root.start("region", "ocr") }
        function full(): void { Quickshell.execDetached([root.script, "full"]) }
        function monitor(): void { Quickshell.execDetached([root.script, "monitor"]) }
        function cancel(): void { root.open = false }
    }

    // a button of the toolbar: label + its key
    component Tool: Rectangle {
        id: tool
        property string label
        property string cap
        property bool on: false
        property bool enabled_: true
        signal hit()
        width: row.implicitWidth + 20
        height: 34
        radius: 17
        color: on ? Look.accent : (hov.hovered && enabled_ ? Look.hover : "transparent")
        opacity: enabled_ ? 1 : 0.4
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tool.label
                color: tool.on ? Look.accentInk : Look.text
                font { family: Look.sans; pixelSize: 12; weight: Font.DemiBold }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(18, capT.implicitWidth + 8)
                height: 18
                radius: 5
                color: tool.on ? Qt.alpha(Look.accentInk, 0.18) : Look.raise
                Text { id: capT; anchors.centerIn: parent; text: tool.cap; color: tool.on ? Look.accentInk : Look.dim; font { family: Look.sans; pixelSize: 10; weight: Font.Bold } }
            }
        }
        HoverHandler { id: hov; cursorShape: tool.enabled_ ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: if (tool.enabled_) tool.hit() }
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === root.mon?.name) ?? Quickshell.screens[0]
        visible: root.open
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shot"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        onVisibleChanged: if (visible) keys.forceActiveFocus()

        property real mx: width / 2           // the pointer
        property real my: height / 2
        property bool dragging: false
        property bool moving: false
        property point grab                   // drag start, or the pointer's offset inside a moved selection
        readonly property var hovered: {
            if (root.mode !== "window") return null
            for (const w of root.wins) if (mx >= w.x && mx < w.x + w.w && my >= w.y && my < w.y + w.h) return w
            return null
        }

        // the frozen frame: the screen as it was, pixel for pixel
        Image {
            anchors.fill: parent
            source: root.frozen ? "file://" + root.frozen : ""
            asynchronous: false
            cache: false
            smooth: false
        }

        // dim everything but the selection
        Item {
            anchors.fill: parent
            opacity: root.fade
            readonly property color shade: Qt.alpha("black", 0.5)
            readonly property rect r: root.has ? root.sel : Qt.rect(0, 0, 0, 0)
            Rectangle { x: 0; y: 0; width: parent.width; height: parent.r.y; color: parent.shade }
            Rectangle { x: 0; y: parent.r.y + parent.r.height; width: parent.width; height: parent.height - y; color: parent.shade }
            Rectangle { x: 0; y: parent.r.y; width: parent.r.x; height: parent.r.height; color: parent.shade }
            Rectangle { x: parent.r.x + parent.r.width; y: parent.r.y; width: parent.width - x; height: parent.r.height; color: parent.shade }
        }

        // the window under the pointer (window mode)
        Rectangle {
            visible: !!win.hovered && !root.has
            x: win.hovered?.x ?? 0
            y: win.hovered?.y ?? 0
            width: win.hovered?.w ?? 0
            height: win.hovered?.h ?? 0
            radius: 10
            color: Qt.alpha(Look.accent, 0.12)
            border.width: 2
            border.color: Look.accent
            Text {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 24)
                elide: Text.ElideRight
                text: win.hovered?.title ?? ""
                color: "white"
                style: Text.Raised
                styleColor: Qt.alpha("black", 0.6)
                font { family: Look.sans; pixelSize: 14; weight: Font.DemiBold }
            }
        }

        // the selection
        Rectangle {
            visible: root.has
            x: root.sel.x - 1
            y: root.sel.y - 1
            width: root.sel.width + 2
            height: root.sel.height + 2
            color: "transparent"
            border.width: 1.5
            border.color: Look.accent
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    x: (index % 2 ? parent.width : 0) - 4
                    y: (index > 1 ? parent.height : 0) - 4
                    width: 8; height: 8; radius: 4
                    color: Look.accent
                }
            }
        }
        // its size, in real pixels
        Rectangle {
            visible: root.has && root.mode !== "screen"
            x: Math.max(6, Math.min(win.width - width - 6, root.sel.x))
            y: root.sel.y > 34 ? root.sel.y - 30 : root.sel.y + root.sel.height + 8
            width: sizeText.implicitWidth + 16
            height: 22
            radius: 11
            color: Qt.alpha("black", 0.7)
            Text {
                id: sizeText
                anchors.centerIn: parent
                text: `${Math.round(root.sel.width * root.dpr)} × ${Math.round(root.sel.height * root.dpr)}`
                color: "white"
                font { family: Look.sans; pixelSize: 11; weight: Font.DemiBold; features: { "tnum": 1 } }
            }
        }

        // crosshair and loupe while aiming a region
        readonly property bool aiming: root.mode === "region" && (!root.has || dragging) && !moving
        Rectangle { visible: win.aiming; x: 0; y: win.my; width: win.width; height: 1; color: Qt.alpha(Look.accent, 0.55) }
        Rectangle { visible: win.aiming; x: win.mx; y: 0; width: 1; height: win.height; color: Qt.alpha(Look.accent, 0.55) }
        ClippingRectangle {
            id: loupe
            visible: win.aiming && root.open
            readonly property int zoom: 4
            width: 128
            height: 128
            radius: 64
            x: win.mx + 26 + width > win.width ? win.mx - 26 - width : win.mx + 26
            y: win.my + 26 + height > win.height ? win.my - 26 - height : win.my + 26
            color: "black"
            border.width: 2
            border.color: Look.accent
            Image {
                source: root.frozen ? "file://" + root.frozen : ""
                cache: false
                smooth: false
                width: win.width * loupe.zoom
                height: win.height * loupe.zoom
                x: loupe.width / 2 - win.mx * loupe.zoom
                y: loupe.height / 2 - win.my * loupe.zoom
            }
            Rectangle {
                anchors.centerIn: parent
                width: loupe.zoom + 2
                height: loupe.zoom + 2
                color: "transparent"
                border.width: 1
                border.color: "white"
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.mode === "region" ? Qt.CrossCursor : Qt.PointingHandCursor
            onPositionChanged: m => {
                win.mx = m.x
                win.my = m.y
                if (win.dragging) {
                    const x0 = Math.max(0, Math.min(win.grab.x, m.x)), y0 = Math.max(0, Math.min(win.grab.y, m.y))
                    const x1 = Math.min(win.width, Math.max(win.grab.x, m.x)), y1 = Math.min(win.height, Math.max(win.grab.y, m.y))
                    root.sel = Qt.rect(x0, y0, x1 - x0, y1 - y0)
                } else if (win.moving) {
                    root.sel = Qt.rect(Math.max(0, Math.min(win.width - root.sel.width, m.x - win.grab.x)),
                                       Math.max(0, Math.min(win.height - root.sel.height, m.y - win.grab.y)),
                                       root.sel.width, root.sel.height)
                }
            }
            onPressed: m => {
                if (root.mode === "window") {
                    const w = win.hovered
                    root.sel = w ? Qt.rect(Math.max(0, w.x), Math.max(0, w.y), Math.min(w.w, win.width - Math.max(0, w.x)), Math.min(w.h, win.height - Math.max(0, w.y))) : Qt.rect(0, 0, 0, 0)
                    if (root.has && root.after) root.run(root.after)
                    return
                }
                if (root.mode !== "region") return
                if (root.has && m.x >= root.sel.x && m.x <= root.sel.x + root.sel.width && m.y >= root.sel.y && m.y <= root.sel.y + root.sel.height) {
                    win.moving = true
                    win.grab = Qt.point(m.x - root.sel.x, m.y - root.sel.y)
                } else {
                    win.dragging = true
                    win.grab = Qt.point(m.x, m.y)
                    root.sel = Qt.rect(m.x, m.y, 0, 0)
                }
            }
            onReleased: {
                const drew = win.dragging
                win.dragging = false
                win.moving = false
                if (drew && root.has && root.after) root.run(root.after)
            }
            onDoubleClicked: if (root.has) root.run("save")
        }

        Item {
            id: keys
            focus: true
            Keys.onPressed: e => {
                e.accepted = true
                const k = e.key
                if (k === Qt.Key_Escape) root.open = false
                else if (k === Qt.Key_R) root.setMode("region")
                else if (k === Qt.Key_W) root.setMode("window")
                else if (k === Qt.Key_S && !(e.modifiers & Qt.ControlModifier)) root.setMode("screen")
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_S && e.modifiers & Qt.ControlModifier)) root.run("save")
                else if (k === Qt.Key_C) root.run("copy")
                else if (k === Qt.Key_E) root.run("edit")
                else if (k === Qt.Key_O || k === Qt.Key_T) root.run("ocr")
                else e.accepted = false
            }
        }

        // ---------------- the toolbar ----------------
        Rectangle {
            id: bar
            readonly property bool low: !root.has || root.sel.y + root.sel.height < win.height - 90
            anchors.horizontalCenter: parent.horizontalCenter
            y: low ? win.height - height - 28 : 28 + Look.reserve
            width: tools.implicitWidth + 16
            height: 46
            radius: 23
            color: Qt.rgba(Look.base.r * 0.3, Look.base.g * 0.3, Look.base.b * 0.36, 0.94)
            border.width: 1
            border.color: Look.rim
            opacity: root.fade
            MouseArea { anchors.fill: parent }

            Row {
                id: tools
                anchors.centerIn: parent
                spacing: 2
                Tool { label: "Region"; cap: "R"; on: root.mode === "region"; onHit: root.setMode("region") }
                Tool { label: "Window"; cap: "W"; on: root.mode === "window"; onHit: root.setMode("window") }
                Tool { label: "Screen"; cap: "S"; on: root.mode === "screen"; onHit: root.setMode("screen") }
                Rectangle { width: 1; height: 22; color: Look.line; anchors.verticalCenter: parent.verticalCenter }
                Tool { label: "Save"; cap: "⏎"; enabled_: root.has; onHit: root.run("save") }
                Tool { label: "Copy"; cap: "C"; enabled_: root.has; onHit: root.run("copy") }
                Tool { label: "Edit"; cap: "E"; enabled_: root.has; onHit: root.run("edit") }
                Tool { label: "Text"; cap: "O"; enabled_: root.has; onHit: root.run("ocr") }
                Rectangle { width: 1; height: 22; color: Look.line; anchors.verticalCenter: parent.verticalCenter }
                Tool { label: "Cancel"; cap: "Esc"; onHit: root.open = false }
            }
        }
    }
}
