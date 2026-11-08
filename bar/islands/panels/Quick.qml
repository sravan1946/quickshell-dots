import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs
import qs.islands

// Quick settings: who and how long up, settings / lock / power, the bar's update and the
// border plugin's rebuild when they're due, then night light, airplane mode, the mic and the
// phone (KDE Connect). Sound devices and levels are the volume item's panel.
// Also `qs -c bar ipc call quick toggle`.
Panel {
    id: p
    implicitWidth: 320
    spacing: 12
    readonly property var src: Pipewire.defaultAudioSource
    readonly property var bt: Bluetooth.defaultAdapter
    PwObjectTracker { objects: [p.src] }
    function launch(cmd) { ctl.hide(); Util.run(cmd) }

    Component.onCompleted: {
        Config.quickOpen = true
        Update.stale()
        NetStats.refresh()
        up.running = true
        phoneGet.running = true
    }
    Component.onDestruction: Config.quickOpen = false

    property string uptime: ""
    Process {
        id: up
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = Math.floor(parseFloat(text) / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
                p.uptime = d ? `${d}d ${h % 24}h` : h ? `${h}h ${m % 60}m` : `${m}m`
            }
        }
    }

    // ---- night light: HyDE's hyprsunset.sh and its state file (temp|gamma|on|identity) ----
    // "on" means toggled on AND warmer than identity: HyDE ships it on at 6000K, which tints nothing
    readonly property var nlState: (nlFile.text() || "6000|100|0|6000").trim().split("|").map(Number)
    readonly property int nlTemp: nlState[0]
    readonly property int nlIdentity: nlState[3] || 6000
    readonly property bool nlOn: nlState[2] === 1 && nlTemp < nlIdentity
    readonly property int nlMin: 2500
    property int nlLive: 0
    FileView {
        id: nlFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hyde/hyprsunset"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: p.nlLive = 0
    }
    function nlToggle() {
        const sh = "hyde-shell hyprsunset.sh -q"
        if (nlOn) return Util.run(`${sh} -t`)
        const t = nlTemp < nlIdentity ? nlTemp : 4500
        Util.run(nlState[2] === 1 ? `${sh} -s ${t}` : `${sh} -s ${t}; ${sh} -t`)
    }
    // while dragging, talk to hyprsunset directly (the script is a slow bash start-up); save on release
    Timer { id: nlApply; interval: 50; onTriggered: Util.run(`hyprctl --quiet hyprsunset temperature ${p.nlLive}`) }

    // ---- phone (KDE Connect): first reachable device, its name and battery ----
    property var phone: null
    Process {
        id: phoneGet
        command: ["sh", "-c", `
            id=$(kdeconnect-cli -a --id-only 2>/dev/null | head -1); [ -n "$id" ] || exit 0
            p=/modules/kdeconnect/devices/$id; g() { busctl --user get-property org.kde.kdeconnect "$@" 2>/dev/null | cut -d' ' -f2-; }
            echo "$id|$(g $p org.kde.kdeconnect.device name | tr -d '"')|$(g $p/battery org.kde.kdeconnect.device.battery charge)|$(g $p/battery org.kde.kdeconnect.device.battery isCharging)"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("|")
                p.phone = f.length < 4 ? null : { id: f[0], name: f[1], charge: parseInt(f[2]), charging: f[3] === "true" }
            }
        }
    }
    Timer { id: refreshSoon; interval: 700; onTriggered: NetStats.refresh() }

    // ---- who, session ----
    Item {
        width: parent.width
        height: 34
        Rectangle {
            id: avatar
            width: 34; height: 34; radius: 17
            color: Look.accent
            G { anchors.centerIn: parent; glyph: 0xF0004; color: Look.accentInk; font.pixelSize: 17 }
        }
        Column {
            anchors { left: avatar.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            T { text: Quickshell.env("USER"); font.weight: Font.DemiBold; font.pixelSize: 13 }
            T { visible: !!p.uptime; text: "up " + p.uptime; color: Look.dim; font.pixelSize: Look.small }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            Round { glyph: 0xF0493; onTap: { p.ctl.hide(); Config.openSettings() } }        // settings
            Round { glyph: 0xF033E; onTap: p.launch("hyde-shell lockscreen.sh") }            // lock
            Round { glyph: 0xF0425; onTap: { p.ctl.hide(); Config.togglePower() } }          // power menu
        }
    }

    // ---- due: the bar's update, the border plugin's rebuild ----
    Notice {
        visible: Update.behind > 0
        title: Update.behind === 1 ? "1 update on GitHub" : `${Update.behind} updates on GitHub`
        sub: Update.error || (Update.subjects[0] ?? "")
        bad: !!Update.error
        action: Update.busy ? "Updating…" : "Update"
        onAct: Update.pull()
    }
    Notice {
        visible: Update.pluginStale
        title: "Border plugin needs a rebuild"
        sub: "Hyprland updated since beatglow was built"
        action: Update.pluginBusy ? "Building…" : "Rebuild"
        onAct: Update.rebuildPlugin()
    }

    // ---- toggles ----
    GridLayout {
        width: parent.width
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        QTile {
            Layout.fillWidth: true
            glyph: 0xF0594
            label: "Night light"
            sub: p.nlOn ? `${p.nlLive || p.nlTemp}K` : "Off"
            on: p.nlOn
            onClicked: p.nlToggle()
        }
        QTile {
            Layout.fillWidth: true
            readonly property bool wifi: !!NetStats.info.wifiOn
            glyph: on ? 0xF001D : 0xF001E
            label: "Airplane mode"
            sub: on ? "Radios off" : "Off"
            on: !wifi && !p.bt?.enabled
            onClicked: {
                Util.run(`nmcli radio wifi ${on ? "on" : "off"}`)
                if (p.bt) p.bt.enabled = on
                refreshSoon.restart()
            }
        }
        QTile {
            Layout.fillWidth: true
            readonly property bool muted: !!p.src?.audio?.muted
            glyph: muted ? 0xF036D : 0xF036C
            label: "Microphone"
            sub: !p.src ? "None" : muted ? "Muted" : "On"
            on: !!p.src && !muted
            onClicked: if (p.src?.audio) Util.setMuted(p.src, !muted)
        }
        QTile {
            Layout.fillWidth: true
            glyph: 0xF011C
            label: p.phone?.name || "Phone"
            sub: !p.phone ? "Not connected" : `${p.phone.charge}%${p.phone.charging ? " · charging" : ""} · tap to ring`
            on: !!p.phone
            onClicked: p.phone ? Util.run(`kdeconnect-cli -d ${p.phone.id} --ring`) : p.launch("kdeconnect-app")
        }
    }

    // night light's warmth, while it's on
    Row {
        visible: p.nlOn
        width: parent.width
        spacing: 10
        G { width: 18; glyph: 0xF050F; color: Look.text }
        Slide {
            id: nl
            width: parent.width - 72
            fill: Look.warm
            readonly property int temp: p.nlLive || p.nlTemp
            value: (temp - p.nlMin) / (p.nlIdentity - p.nlMin)
            onMoved: v => {
                p.nlLive = Math.round((p.nlMin + v * (p.nlIdentity - p.nlMin - 100)) / 100) * 100
                if (!nlApply.running) nlApply.start()
                saveNl.restart()
            }
        }
        T { width: 44; horizontalAlignment: Text.AlignRight; text: nl.temp + "K"; color: Look.dim }
        // saved once the drag settles
        Timer { id: saveNl; interval: 600; onTriggered: if (p.nlLive) Util.run(`hyde-shell hyprsunset.sh -q -s ${p.nlLive}`) }
    }

    component Round: Rectangle {
        id: r
        property int glyph
        signal tap()
        width: 32; height: 32; radius: 16
        color: rh.hovered ? Look.hover : Look.raise
        Behavior on color { Fade {} }
        G { anchors.centerIn: parent; glyph: r.glyph; color: Look.text; font.pixelSize: 15 }
        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: r.tap() }
    }
    component Notice: Rectangle {
        id: n
        property string title
        property string sub
        property bool bad: false
        property string action
        signal act()
        width: parent.width
        height: 48
        radius: 12
        color: Qt.alpha(Look.accent, 0.12)
        G { id: ni; x: 12; anchors.verticalCenter: parent.verticalCenter; glyph: 0xF06B0; color: Look.accent; font.pixelSize: 17 }
        Column {
            anchors { left: ni.right; leftMargin: 10; right: nb.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            T { width: parent.width; text: n.title; font.weight: Font.DemiBold; elide: Text.ElideRight }
            T { width: parent.width; text: n.sub; color: n.bad ? Look.alert : Look.dim; font.pixelSize: Look.small; elide: Text.ElideRight }
        }
        Btn { id: nb; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: n.action; strong: true; onClicked: n.act() }
    }
}
