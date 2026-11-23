import QtQuick
import Quickshell
import qs
import qs.islands

// A symbol picker card, dropped out of the clock: emoji (panels/Emoji.qml, SUPER+.) and Nerd
// Font glyphs (panels/Glyphs.qml, SUPER+,), with `src` (PickerData) holding the list and the
// copy. A search field, a strip of the list's groups and one grid of everything, recent first;
// the strip follows the selection and a group's icon jumps to it. The symbol under the
// selection is shown big at the bottom with its name and keywords.
// Typing searches (every word has to start a word of the name or keywords), arrows move,
// Tab/Shift+Tab jump group, Enter (or a click) copies it and closes, Esc clears the search,
// then closes.
Panel {
    id: p
    required property var src
    implicitWidth: cols * 44 + 8
    spacing: 8

    readonly property int cols: src.cols
    readonly property string query: search.text.trim().toLowerCase()
    // the grid: search hits, or recent + all; `g` is the strip index of each item's group
    readonly property var shown: {
        if (query) return src.search(query)
        const idx = {}
        src.groups.forEach((g, i) => idx[g.key] = i)
        const byCh = {}
        for (const e of src.all) byCh[e.ch] = e
        const rec = src.recent.filter(c => byCh[c]).map(c => Object.assign({}, byCh[c], { g: 0 }))
        return rec.concat(src.all.map(e => Object.assign({}, e, { g: idx[e.group] })))
    }
    // where each group starts in the grid (browsing only)
    readonly property var starts: {
        const s = src.groups.map(() => -1)
        if (!query) shown.forEach((e, i) => { if (s[e.g] < 0) s[e.g] = i })
        return s
    }
    property int sel: 0
    readonly property var cur: shown[sel] ?? null
    onQueryChanged: sel = 0

    function move(d) { if (shown.length) sel = Math.max(0, Math.min(shown.length - 1, sel + d)) }
    function jump(dir) {
        if (query || !cur) return
        const order = starts.map((s, i) => ({ s, i })).filter(o => o.s >= 0)
        const at = order.findIndex(o => o.i === cur.g)
        const to = order[Math.max(0, Math.min(order.length - 1, at + dir))]
        if (to) sel = to.s
    }
    function pick() {
        if (!cur) return
        const ch = cur.ch
        p.ctl.hide()
        src.pick(ch)
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
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Right) p.move(1)
                else if (e.key === Qt.Key_Left) p.move(-1)
                else if (e.key === Qt.Key_Down) p.move(p.cols)
                else if (e.key === Qt.Key_Up) p.move(-p.cols)
                else if (e.key === Qt.Key_PageDown) p.move(p.cols * 5)
                else if (e.key === Qt.Key_PageUp) p.move(-p.cols * 5)
                else if (e.key === Qt.Key_Tab) p.jump(1)
                else if (e.key === Qt.Key_Backtab) p.jump(-1)
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) p.pick()
                else if (e.key === Qt.Key_Escape) text ? text = "" : p.ctl.hide()
                else return
                e.accepted = true
            }
            T {
                anchors.verticalCenter: parent.verticalCenter
                visible: !search.text
                text: `Search ${src.all.length} ${src.noun}`
                color: Look.faint
            }
        }
    }

    // ---- groups ----
    Item {
        id: strip
        width: parent.width
        height: 30
        readonly property real w: width / p.src.groups.length
        opacity: p.query ? 0.3 : 1
        Behavior on opacity { NumberAnimation { duration: Look.ms("effects") } }
        // under the group the selection is in
        Rectangle {
            visible: !p.query && !!p.cur
            x: (p.cur?.g ?? 0) * strip.w + (strip.w - width) / 2
            y: parent.height - 3
            width: 16
            height: 3
            radius: 2
            color: Look.accent
            Behavior on x { NumberAnimation { duration: Look.ms("effects"); easing.type: Easing.OutCubic } }
        }
        Repeater {
            model: p.src.groups
            Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool here: !p.query && p.cur?.g === index
                readonly property bool empty: p.starts[index] < 0
                x: index * strip.w
                width: strip.w
                height: parent.height - 4
                Rectangle {
                    anchors.centerIn: parent
                    width: 28; height: 24; radius: 8
                    color: tabHov.hovered && !tab.empty && !p.query ? Look.hover : "transparent"
                    Behavior on color { Fade {} }
                }
                G {
                    anchors.centerIn: parent
                    glyph: tab.modelData.glyph
                    font.pixelSize: 15
                    color: tab.here ? Look.accent : tab.empty ? Look.faint : Look.dim
                    Behavior on color { Fade {} }
                }
                HoverHandler { id: tabHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: if (!p.query && !tab.empty) p.sel = p.starts[tab.index] }
            }
        }
    }

    // ---- the grid ----
    GridView {
        id: grid
        width: parent.width
        height: 6 * cellHeight
        cellWidth: width / p.cols
        cellHeight: 42
        clip: true
        model: p.shown
        currentIndex: p.sel
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 200
        highlight: Rectangle { radius: 10; color: Qt.alpha(Look.accent, 0.18) }
        highlightMoveDuration: Look.ms("effects")
        highlightFollowsCurrentItem: true
        preferredHighlightBegin: cellHeight
        preferredHighlightEnd: height - cellHeight
        highlightRangeMode: GridView.ApplyRange

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            Rectangle {
                anchors { fill: parent; margins: 1 }
                radius: 10
                color: hov.hovered && cell.index !== p.sel ? Look.hover : "transparent"
                Behavior on color { Fade {} }
            }
            Text {
                anchors.centerIn: parent
                text: cell.modelData.ch
                font { family: p.src.font; pixelSize: p.src.size }
                color: p.src.tinted ? (cell.index === p.sel ? Look.text : Qt.alpha(Look.text, 0.8)) : Look.text
            }
            HoverHandler { id: hov; onHoveredChanged: if (hovered) p.sel = cell.index }
            TapHandler { onTapped: { p.sel = cell.index; p.pick() } }
        }

        T {
            anchors.centerIn: parent
            visible: !p.shown.length
            text: p.query ? `No ${p.src.noun} match` : "Loading…"
            color: Look.faint
        }
    }

    // ---- what's selected ----
    Item {
        width: parent.width
        height: 48
        Rectangle {
            id: big
            width: 48; height: 48; radius: 14
            color: Look.raise
            Text {
                anchors.centerIn: parent
                text: p.cur?.ch ?? ""
                font { family: p.src.font; pixelSize: p.src.size + 6 }
                color: Look.text
            }
        }
        Column {
            anchors { left: big.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 2
            T {
                width: parent.width
                text: p.cur ? p.cur.name.charAt(0).toUpperCase() + p.cur.name.slice(1) : ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.weight: Font.DemiBold
            }
            T {
                width: parent.width
                text: p.cur ? p.cur.sub || p.cur.group : ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: Look.small
                color: Look.faint
            }
        }
    }

    // ---- keys ----
    T {
        width: parent.width
        horizontalAlignment: Text.AlignRight
        color: Look.faint
        font.pixelSize: Look.small
        text: "tab group    ↵ copy    esc close"
    }
}
