import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.islands

// The clipboard history (cliphist), dropped out of the clock by SUPER+V: the card that says
// "Copied" opens up into everything copied before, as a board of small tiles, newest first,
// each showing what it holds: a few lines of the text, code in monospace, a link's site, the
// picture itself, the colour itself. Typing searches, arrows move, Enter copies it back (and the card closes into the usual "Copied"), Delete at the
// end of the search drops it from the history, Esc clears the search, then closes.
// Pictures are decoded into $XDG_RUNTIME_DIR/qs-clip (tmpfs, private).
Panel {
    id: p
    implicitWidth: 460
    spacing: 10

    readonly property string cache: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-clip"
    property var items: []              // [{ id, text, kind }]
    property int sel: 0
    readonly property var shown: {
        const q = search.text.trim().toLowerCase()
        return q ? items.filter(i => i.text.toLowerCase().includes(q)) : items
    }
    readonly property var cur: shown[sel] ?? null
    readonly property int cols: 3
    onShownChanged: sel = Math.min(sel, Math.max(0, shown.length - 1))

    readonly property var glyphs: ({ text: 0xF0284, code: 0xF0174, link: 0xF0337, path: 0xF024B, image: 0xF02E9, colour: 0xF03D8 })
    function kindOf(t) {
        if (t.startsWith("[[ binary data")) return "image"
        const s = t.trim()
        if (/^(#[0-9a-f]{3,8}|rgba?\([\d\s.,%]+\)|hsla?\([\d\s.,%deg]+\))$/i.test(s) && Qt.color(s).valid) return "colour"
        if (/^(https?|ftp):\/\/\S+$/i.test(s)) return "link"
        if (/^~?\/[^\s]+$/.test(s) && s.length > 2) return "path"
        if (/[{};](\s|$)|=>|^\s*(\$ |sudo |git |kubectl |cd |ls |cat |grep |docker |npm |uv |python3? |curl |ssh |aws |gcloud |hyprctl |qs |systemctl |journalctl |helm |rg |sed |awk |jq |import |from |def |function |const |let |class |export |return |select |SELECT )/.test(s)) return "code"
        return "text"
    }

    function copy() {
        if (!cur) return
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$0" | wl-copy', cur.id])
        p.ctl.hide()
    }
    function remove() {
        if (!cur) return
        const id = cur.id
        Quickshell.execDetached(["sh", "-c", 'cliphist list | awk -F "\t" -v id="$0" \'$1 == id\' | head -1 | cliphist delete; rm -f "$1/$0.png"', id, cache])
        items = items.filter(i => i.id !== id)
    }

    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p -m 700 "$0"; cliphist list', p.cache]
        stdout: StdioCollector {
            onStreamFinished: p.items = text.split("\n").filter(l => l).map(l => {
                const tab = l.indexOf("\t"), t = l.slice(tab + 1)
                return { id: l.slice(0, tab), text: t, kind: p.kindOf(t) }
            })
        }
    }

    // ---- search ----
    Rectangle {
        width: parent.width
        height: 34
        radius: 12
        color: Look.raise
        G { x: 11; anchors.verticalCenter: parent.verticalCenter; glyph: 0xF0349; color: Look.faint }
        TextInput {
            id: search
            anchors { fill: parent; leftMargin: 34; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            color: Look.text
            selectionColor: Qt.alpha(Look.accent, 0.4)
            clip: true
            font { family: Look.sans; pixelSize: Look.size }
            Component.onCompleted: forceActiveFocus()
            onTextChanged: p.sel = 0
            onAccepted: p.copy()
            Keys.onPressed: e => {
                const n = p.shown.length
                const step = { [Qt.Key_Right]: 1, [Qt.Key_Left]: -1, [Qt.Key_Down]: p.cols, [Qt.Key_Up]: -p.cols,
                    [Qt.Key_PageDown]: 4 * p.cols, [Qt.Key_PageUp]: -4 * p.cols }[e.key]
                if (step) p.sel = Math.max(0, Math.min(n - 1, p.sel + step))
                else if (e.key === Qt.Key_Delete && cursorPosition === text.length) p.remove()
                else if (e.key === Qt.Key_Escape) text ? text = "" : p.ctl.hide()
                else return
                e.accepted = true
            }
            T {
                anchors.verticalCenter: parent.verticalCenter
                visible: !search.text
                text: p.items.length ? `Search ${p.items.length} copies` : "Search"
                color: Look.faint
            }
        }
    }

    // ---- the board ----
    GridView {
        id: grid
        width: parent.width
        height: 3 * cellHeight + 40       // three rows and the top of a fourth: there's more below
        clip: true
        cellWidth: width / p.cols
        cellHeight: 92
        model: p.shown
        currentIndex: p.sel
        // the ring glides from tile to tile, and the board eases to keep it off the edges
        highlight: Item {
            Rectangle {
                anchors { fill: parent; margins: 3 }
                radius: 12
                color: "transparent"
                border.width: 2
                border.color: Look.accent
            }
        }
        highlightMoveDuration: Look.ms("effects")
        highlightRangeMode: GridView.ApplyRange
        preferredHighlightBegin: 20
        preferredHighlightEnd: height - 20
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 300

        delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property string kind: modelData.kind
            readonly property string one: modelData.text.replace(/\s+/g, " ").trim()
            readonly property bool chosen: index === p.sel
            readonly property bool mono: kind === "code" || kind === "path"
            width: grid.cellWidth
            height: grid.cellHeight

            // the preview line cliphist keeps loses the line breaks and stops at 100 characters:
            // longer text and code read their start back; pictures decode once into the cache
            property string body: ""
            property string file: ""
            Process {
                running: tile.kind === "image" || ((tile.kind === "code" || tile.kind === "text") && tile.one.length > 30)
                command: tile.kind === "image"
                    ? ["sh", "-c", 'f="$1/$0.png"; [ -s "$f" ] || cliphist decode "$0" > "$f"; echo "$f"', tile.modelData.id, p.cache]
                    : ["sh", "-c", 'cliphist decode "$0" | head -c 600', tile.modelData.id]
                stdout: StdioCollector {
                    onStreamFinished: tile.kind === "image" ? tile.file = "file://" + text.trim()
                        : tile.body = text.replace(/^\s*\n/, "").replace(/\s+$/, "")
                }
            }

            ClippingRectangle {
                id: face
                anchors { fill: parent; margins: 5 }
                radius: 10
                color: tile.kind === "colour" ? tile.one
                    : hov.hovered || tile.chosen ? Qt.alpha("white", 0.09) : Look.raise
                Behavior on color { Fade {} }

                // a picture fills its tile
                Image {
                    anchors.fill: parent
                    visible: tile.kind === "image"
                    source: tile.file
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(320, 200)
                    asynchronous: true
                }
                // a link: its site, then where on it
                Column {
                    visible: tile.kind === "link"
                    x: 10; y: 9
                    width: parent.width - 20
                    spacing: 3
                    readonly property var url: tile.one.match(/^\w+:\/\/(www\.)?([^/?#]+)(.*)$/)
                    T {
                        width: parent.width
                        text: parent.url?.[2] ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    T {
                        width: parent.width
                        text: (parent.url?.[3] ?? "").replace(/^\/$/, "")
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Look.dim
                        font.pixelSize: Look.small
                    }
                }
                // a path: the file's name, then the folder it's in
                Column {
                    visible: tile.kind === "path"
                    x: 10; y: 9
                    width: parent.width - 20
                    spacing: 3
                    T {
                        width: parent.width
                        text: tile.one.replace(/\/$/, "").split("/").pop()
                        elide: Text.ElideMiddle
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    T {
                        width: parent.width
                        text: tile.one.replace(/\/?[^/]+\/?$/, "") || "/"
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideLeft
                        color: Look.dim
                        font.family: Look.icons
                        font.pixelSize: Look.small - 1
                    }
                }
                // a colour: its value on it
                T {
                    visible: tile.kind === "colour"
                    anchors.centerIn: parent
                    text: tile.one
                    color: Qt.color(face.color).hslLightness > 0.6 ? "black" : "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                // text and code: a word or two big, anything longer as its first lines
                T {
                    readonly property bool short: tile.one.length <= 24 && !tile.mono
                    visible: tile.kind === "text" || tile.kind === "code"
                    x: 10; y: 8
                    width: parent.width - 20
                    height: parent.height - 16
                    text: tile.body || tile.one
                    textFormat: Text.PlainText
                    wrapMode: tile.mono ? Text.NoWrap : Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: short ? 2 : tile.mono ? 5 : 4
                    clip: true
                    verticalAlignment: short ? Text.AlignVCenter : Text.AlignTop
                    lineHeight: tile.mono ? 1.0 : 1.08
                    color: short || tile.chosen ? Look.text : Qt.alpha(Look.text, 0.8)
                    font.family: tile.mono ? Look.icons : Look.sans
                    font.pixelSize: short ? 15 : tile.mono ? 10 : 11
                    font.weight: short ? Font.DemiBold : Font.Normal
                }
                // what kind, small in the corner (a picture's size instead)
                Rectangle {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
                    visible: tile.kind !== "colour"
                    width: tag.implicitWidth + 10
                    height: 18
                    radius: 9
                    color: tile.kind === "image" ? Qt.alpha("black", 0.55) : "transparent"
                    T {
                        id: tag
                        anchors.centerIn: parent
                        visible: tile.kind === "image"
                        text: tile.modelData.text.match(/(\d+)x(\d+)/)?.slice(1).join("×") ?? ""
                        color: "white"
                        font.pixelSize: 10
                    }
                    G {
                        anchors.centerIn: parent
                        visible: tile.kind !== "image"
                        height: 18
                        glyph: p.glyphs[tile.kind]
                        color: tile.chosen ? Look.accent : Look.faint
                        font.pixelSize: 11
                    }
                }
            }

            HoverHandler { id: hov }
            TapHandler {
                onTapped: p.sel = tile.index
                onDoubleTapped: { p.sel = tile.index; p.copy() }
            }
        }

        T {
            anchors.centerIn: parent
            visible: !p.shown.length
            text: p.items.length ? "Nothing matches" : "Nothing copied yet"
            color: Look.faint
        }
    }

    // ---- keys ----
    T {
        width: parent.width
        horizontalAlignment: Text.AlignRight
        color: Look.faint
        font.pixelSize: Look.small
        text: "arrows move    ↵ copy    del remove    esc close"
    }
}
