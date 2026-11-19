import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.islands

// The clipboard history (cliphist), dropped out of the clock by SUPER+V: the card that says
// "Copied" opens up into everything copied before. One line each, newest first; what the chosen
// one holds (the whole text, the picture, the colour) shows in the pane under the list. Typing searches, ↑/↓
// choose, Enter copies it back (and the card closes into the usual "Copied"), Delete at the
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
                if (e.key === Qt.Key_Down) p.sel = Math.min(n - 1, p.sel + 1)
                else if (e.key === Qt.Key_Up) p.sel = Math.max(0, p.sel - 1)
                else if (e.key === Qt.Key_PageDown) p.sel = Math.min(n - 1, p.sel + 8)
                else if (e.key === Qt.Key_PageUp) p.sel = Math.max(0, p.sel - 8)
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

    // ---- the history: fixed rows, so nothing moves but the selection and the scroll ----
    ListView {
        id: list
        width: parent.width
        height: 304
        clip: true
        spacing: 2
        model: p.shown
        currentIndex: p.sel
        // the selection glides from row to row, and the view eases to keep it off the edges
        highlight: Rectangle { radius: 10; color: Qt.alpha(Look.accent, 0.14) }
        highlightMoveDuration: Look.ms("effects")
        highlightMoveVelocity: -1
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 40
        preferredHighlightEnd: height - 40
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 400

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool chosen: index === p.sel
            readonly property string kind: modelData.kind
            readonly property string one: modelData.text.replace(/\s+/g, " ").trim()
            width: list.width
            height: 36
            radius: 10
            color: hov.hovered && !chosen ? Look.hover : "transparent"
            Behavior on color { Fade {} }

            // a picture, decoded once into the cache, as soon as its row exists
            property string file: ""
            Process {
                running: row.kind === "image"
                command: ["sh", "-c", 'f="$1/$0.png"; [ -s "$f" ] || cliphist decode "$0" > "$f"; echo "$f"', row.modelData.id, p.cache]
                stdout: StdioCollector { onStreamFinished: row.file = "file://" + text.trim() }
            }

            // what it is: its kind, its colour, or the picture itself
            Rectangle {
                id: lead
                x: 6; y: 5
                width: 26; height: 26
                radius: 8
                color: row.kind === "colour" ? row.one : Look.raise
                border.width: row.kind === "colour" ? 1 : 0
                border.color: Look.line
                clip: true
                G {
                    anchors.centerIn: parent
                    visible: row.kind !== "colour" && !thumb.visible
                    glyph: p.glyphs[row.kind]
                    color: row.chosen ? Look.accent : Look.dim
                    Behavior on color { Fade {} }
                }
                Image {
                    id: thumb
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: row.file
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(64, 64)
                    asynchronous: true
                }
            }
            T {
                anchors { left: lead.right; leftMargin: 10; right: side.left; rightMargin: 10 }
                y: 5; height: 26
                elide: Text.ElideRight
                text: row.kind === "image" ? "Image" : row.kind === "link" ? row.one.replace(/^\w+:\/\/(www\.)?/, "") : row.one
                font.family: row.kind === "code" || row.kind === "path" ? Look.icons : Look.sans
                font.pixelSize: row.kind === "code" || row.kind === "path" ? Look.size - 1 : Look.size
                color: row.chosen ? Look.text : Qt.alpha(Look.text, 0.82)
            }
            T {
                id: side
                anchors.right: parent.right; anchors.rightMargin: 10
                y: 5; height: 26
                color: Look.faint
                font.pixelSize: Look.small
                text: row.kind === "image" ? (row.modelData.text.match(/(\d+)x(\d+)/)?.slice(1).join(" × ") ?? "") : ""
            }

            HoverHandler { id: hov }
            TapHandler {
                onTapped: p.sel = row.index
                onDoubleTapped: { p.sel = row.index; p.copy() }
            }
        }

        T {
            anchors.centerIn: parent
            visible: !p.shown.length
            text: p.items.length ? "Nothing matches" : "Nothing copied yet"
            color: Look.faint
        }
    }

    // ---- what the chosen one holds: one fixed pane, its content fading over ----
    // settles a moment after the selection does, so holding ↓ doesn't decode every row on the way
    property var peeked: null
    Timer { id: settle; interval: 70; onTriggered: p.peeked = p.cur }
    onCurChanged: settle.restart()

    Rectangle {
        width: parent.width
        height: 150
        radius: 12
        color: Look.raise
        clip: true
        Repeater {
            model: p.peeked ? [p.peeked] : []
            Item {
                id: peek
                required property var modelData
                readonly property string kind: modelData.kind
                anchors.fill: parent
                property string text: ""
                property string file: ""
                opacity: 0
                Anim on opacity { id: fadeIn; running: false; to: 1; type: "effects" }
                function ready() { fadeIn.start() }
                Component.onCompleted: if (kind === "colour") ready()
                Process {
                    running: peek.kind !== "colour"
                    command: peek.kind === "image"
                        ? ["sh", "-c", 'f="$1/$0.png"; [ -s "$f" ] || cliphist decode "$0" > "$f"; echo "$f"', peek.modelData.id, p.cache]
                        : ["sh", "-c", 'cliphist decode "$0" | head -c 3000', peek.modelData.id]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            if (peek.kind === "image") peek.file = "file://" + text.trim()
                            else { peek.text = text.replace(/\s+$/, ""); peek.ready() }
                        }
                    }
                }
                Image {
                    visible: peek.kind === "image"
                    anchors { fill: parent; margins: 8 }
                    source: peek.file
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(880, 268)
                    asynchronous: true
                    onStatusChanged: if (status === Image.Ready) peek.ready()
                }
                Rectangle {
                    visible: peek.kind === "colour"
                    anchors.fill: parent
                    color: peek.kind === "colour" ? peek.modelData.text.trim() : "transparent"
                    T {
                        anchors.centerIn: parent
                        text: peek.modelData.text.trim()
                        color: Qt.color(parent.color).hslLightness > 0.6 ? "black" : "white"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }
                T {
                    // a word or a short line: big, in the middle; anything longer: as it is, from the top
                    readonly property bool short: peek.text.length <= 60 && !peek.text.includes("\n")
                    visible: peek.kind !== "image" && peek.kind !== "colour"
                    anchors { fill: parent; margins: 12 }
                    horizontalAlignment: short ? Text.AlignHCenter : Text.AlignLeft
                    text: peek.text
                    textFormat: Text.PlainText
                    wrapMode: peek.kind === "code" ? Text.NoWrap : Text.WrapAnywhere
                    elide: Text.ElideRight
                    clip: true
                    verticalAlignment: short ? Text.AlignVCenter : Text.AlignTop
                    lineHeight: 1.12
                    color: short ? Look.text : Look.dim
                    font.family: peek.kind === "code" || peek.kind === "path" ? Look.icons : Look.sans
                    font.pixelSize: short ? 20 : Look.small
                    font.weight: short ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    // ---- keys ----
    T {
        width: parent.width
        horizontalAlignment: Text.AlignRight
        color: Look.faint
        font.pixelSize: Look.small
        text: "↑↓ choose    ↵ copy    del remove    esc close"
    }
}
