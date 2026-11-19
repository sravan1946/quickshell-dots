import QtQuick
import Quickshell
import Quickshell.Io
import qs.islands

// Key help, in place of HyDE's rofi keybinds hint (SUPER+/): every live bind from
// `hyprctl binds -j`, yours included, grouped by HyDE's "[Category|Sub]" descriptions into
// balanced columns. Runs like "workspace 1 … 10" fold into one row. Typing filters by what a
// bind does or its keys; arrows/PgUp/PgDn scroll.
// `qs -c bar ipc call keys toggle`
Sheet {
    id: root
    namespace: "sheets"
    title: "Keys"
    hint: "Search binds"
    help: "↑↓ scroll    esc close"
    cardW: 1180
    cardH: 720

    property var binds: []            // [{ cat, sub, text, keys: [..] }]

    onOpenChanged: if (open) list.running = true

    IpcHandler {
        target: "keys"
        function toggle(): void { root.open = !root.open }
    }

    Process {
        id: list
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { root.binds = root.fold(JSON.parse(text)) } catch (e) {} } }
    }

    readonly property var names: ({
        slash: "/", comma: ",", period: ".", minus: "−", equal: "=", grave: "`", backslash: "\\",
        semicolon: ";", apostrophe: "'", bracketleft: "[", bracketright: "]",
        Return: "Enter", Escape: "Esc", Delete: "Del", Print: "PrtSc", space: "Space", Tab: "Tab",
        Left: "←", Right: "→", Up: "↑", Down: "↓", Page_Up: "PgUp", Page_Down: "PgDn",
        mouse_down: "Wheel ↓", mouse_up: "Wheel ↑", "mouse:272": "Left drag", "mouse:273": "Right drag",
        Control_R: "Right Ctrl", Control_L: "Left Ctrl", Alt_R: "Right Alt", Alt_L: "Left Alt",
        AudioRaiseVolume: "Vol +", AudioLowerVolume: "Vol −", AudioMute: "Mute", AudioMicMute: "Mic mute",
        AudioPlay: "Play", AudioPause: "Pause", AudioNext: "Next", AudioPrev: "Prev", AudioStop: "Stop",
        MonBrightnessUp: "Bright +", MonBrightnessDown: "Bright −"
    })
    function keyName(k) {
        k = k.replace(/^XF86/, "")
        const hit = names[k] ?? names[Object.keys(names).find(n => n.toLowerCase() === k.toLowerCase()) ?? ""]
        if (hit) return hit
        return k.length === 1 ? k.toUpperCase() : k.replace(/([a-z])([A-Z])/g, "$1 $2")
    }
    function mods(m) {
        const out = []
        if (m & 64) out.push("Super")
        if (m & 4) out.push("Ctrl")
        if (m & 8) out.push("Alt")
        if (m & 1) out.push("Shift")
        return out
    }

    // hyprctl's binds → rows. Binds that differ only by a number in what they do and in their
    // key (1…0 on the top row, or the numpad with Num Lock on and off) fold into one row.
    function fold(raw) {
        const rows = [], runs = {}
        for (const b of raw) {
            const m = (b.description || "").match(/^\[([^\]]+)\]\s*(.*)$/)
            const path = m ? m[1].split("|") : ["Your binds"]
            let text = (m ? m[2] : b.description) || b.dispatcher.replace(/^HL\.Dispatcher\((.*)\)$/, "$1")
            text = text.charAt(0).toUpperCase() + text.slice(1)
            const cat = path[0].trim(), sub = (path[1] ?? "").trim()
            const family = /^\d+$/.test(b.key) ? "row" : /^KP_/.test(b.key) ? "pad" : ""
            const num = text.match(/\d+/)?.[0]
            if (family && num !== undefined) {
                const shape = [cat, sub, text.replace(/\d+/, "#"), b.modmask, family].join("|")
                const run = runs[shape]
                if (run) { run.nums.push(+num); run.keys.push(b.key); continue }
                const row = { cat, sub, text, mods: mods(b.modmask), family, nums: [+num], keys: [b.key] }
                runs[shape] = row
                rows.push(row)
            } else rows.push({ cat, sub, text, mods: mods(b.modmask), keys: [b.key] })
        }
        return rows.map(r => {
            if (!r.nums || r.nums.length < 3) return { cat: r.cat, sub: r.sub, text: r.text, keys: r.mods.concat(r.keys.slice(0, 1).map(keyName)) }
            const lo = Math.min(...r.nums), hi = Math.max(...r.nums)
            return {
                cat: r.cat, sub: r.sub,
                text: r.text.replace(/\d+/, lo + " … " + hi),
                keys: r.mods.concat([r.family === "pad" ? "Numpad" : keyName(r.keys[0]) + " … " + keyName(r.keys[r.keys.length - 1])])
            }
        })
    }

    // filtered and grouped: [{ cat, items: [{ head } | { text, keys }] }], dealt into 3 columns
    readonly property var columns: {
        const q = query.trim().toLowerCase()
        const cats = [], byCat = {}
        for (const r of binds) {
            if (q && !(r.text + " " + r.keys.join(" ") + " " + r.cat + " " + r.sub).toLowerCase().includes(q)) continue
            let c = byCat[r.cat]
            if (!c) { c = byCat[r.cat] = { cat: r.cat, items: [], lastSub: null }; cats.push(c) }
            if (r.sub !== c.lastSub) { if (r.sub) c.items.push({ head: r.sub }); c.lastSub = r.sub }
            c.items.push({ text: r.text, keys: r.keys })
        }
        const cols = [[], [], []], h = [0, 0, 0]
        for (const c of cats.sort((a, b) => b.items.length - a.items.length)) {
            const i = h.indexOf(Math.min(...h))
            cols[i].push(c)
            h[i] += 46 + c.items.length * 26
        }
        return cols
    }

    onKey: e => {
        const step = e.key === Qt.Key_Down ? 60 : e.key === Qt.Key_Up ? -60
                   : e.key === Qt.Key_PageDown ? flick.height * 0.9 : e.key === Qt.Key_PageUp ? -flick.height * 0.9 : 0
        if (!step) return
        e.accepted = true
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + step))
    }

    Flickable {
        id: flick
        anchors { fill: parent; leftMargin: 22; rightMargin: 22; bottomMargin: 14 }
        contentHeight: cols.height + 10
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Behavior on contentY { enabled: !flick.moving; Anim { type: "effects" } }

        Row {
            id: cols
            spacing: 26
            readonly property real colW: (flick.width - 2 * spacing) / 3
            Repeater {
                model: root.columns
                Column {
                    required property var modelData
                    width: cols.colW
                    spacing: 18
                    Repeater {
                        model: parent.modelData
                        Column {
                            id: section
                            required property var modelData
                            width: cols.colW
                            spacing: 2
                            Text {
                                text: section.modelData.cat
                                color: Look.accent
                                bottomPadding: 6
                                font { family: Look.sans; pixelSize: Look.small; weight: Font.Bold; letterSpacing: 1.6; capitalization: Font.AllUppercase }
                            }
                            Repeater {
                                model: section.modelData.items
                                Item {
                                    id: row
                                    required property var modelData
                                    width: cols.colW
                                    height: modelData.head ? 24 : 26
                                    // a sub-category
                                    Text {
                                        visible: !!row.modelData.head
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 3
                                        text: row.modelData.head ?? ""
                                        color: Look.dim
                                        font { family: Look.sans; pixelSize: Look.small; weight: Font.DemiBold }
                                    }
                                    // a bind: what it does, then its keys
                                    Text {
                                        visible: !row.modelData.head
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - caps.width - 10
                                        text: row.modelData.text ?? ""
                                        elide: Text.ElideRight
                                        color: Look.text
                                        font { family: Look.sans; pixelSize: 12 }
                                    }
                                    Row {
                                        id: caps
                                        visible: !row.modelData.head
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        spacing: 3
                                        Repeater {
                                            model: row.modelData.keys ?? []
                                            Rectangle {
                                                required property var modelData
                                                width: Math.max(20, capText.implicitWidth + 12)
                                                height: 20
                                                radius: 5
                                                color: Look.raise
                                                border.width: 1
                                                border.color: Look.line
                                                Text {
                                                    id: capText
                                                    anchors.centerIn: parent
                                                    text: parent.modelData
                                                    color: Look.dim
                                                    font { family: Look.sans; pixelSize: 10; weight: Font.DemiBold }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.binds.length && !root.columns.some(c => c.length)
        text: "Nothing bound matches “" + root.query + "”"
        color: Look.faint
        font { family: Look.sans; pixelSize: 13 }
    }
}
