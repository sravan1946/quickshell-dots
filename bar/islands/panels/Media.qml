import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs
import qs.components
import qs.islands

// Now playing, as a poster: the cover is the card's backdrop, edge to edge across the top and
// melting into the glass below, drifting slowly while it plays; the title is set large over
// its foot. Then the synced lyrics; a hairline timeline whose elapsed time rides the playhead;
// and the transport: shuffle, previous, play, next, repeat. While it's open Player.open is set,
// so the position and lyrics follow every frame.
Panel {
    id: p
    implicitWidth: 340
    spacing: 14
    readonly property var pl: Player.player
    Component.onCompleted: Player.open = true
    Component.onDestruction: Player.open = false
    function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }

    Item {
        id: hero
        width: parent.width
        height: 196

        // the backdrop, out to the card's edges, its corners the card's, melting downwards into
        // the glass. It lives in the card itself, under the panes (the pane's reveal layer would
        // crop it to the padding until the reveal ends), following the pane's fade.
        ClippingRectangle {
            id: poster
            readonly property Item pane: p.parent
            parent: pane?.parent ?? hero
            z: -1
            opacity: pane ? pane.opacity * pane.reveal : 1
            width: hero.width + 28        // the card's padding: 14 at the sides, 12 on top
            height: hero.height + 12
            radius: 16
            color: "transparent"
            Art {
                id: art
                anchors.centerIn: parent
                width: parent.width
                height: parent.width
                sourceSize: Qt.size(680, 680)
                instant: true
                layer.enabled: true
                layer.effect: MultiEffect { saturation: Player.playing ? 0.15 : -0.85; brightness: -0.1 }
                // a slow drift while it plays (CRAFT rule 17: stills while paused)
                property real drift: 0
                scale: 1.06 + 0.06 * drift
                transform: Translate { y: -18 * art.drift + 10 }
                SequentialAnimation on drift {
                    running: Player.playing
                    loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: 14000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 14000; easing.type: Easing.InOutSine }
                }
            }
            // shade for the title, then the card's own surface
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.1) }
                    GradientStop { position: 0.75; color: Qt.rgba(Look.surface.r, Look.surface.g, Look.surface.b, 0.75) }
                    GradientStop { position: 1; color: Qt.rgba(Look.surface.r, Look.surface.g, Look.surface.b, 1) }
                }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            spacing: 2
            T {
                text: (p.pl?.identity ?? "").toUpperCase()
                color: Qt.alpha(Look.text, 0.5)
                font { pixelSize: 9; weight: Font.DemiBold; letterSpacing: 1.6 }
            }
            MediaTitle {
                cover: art
                maxWidth: parent.width
                font { family: Look.sans; pixelSize: 22; weight: Font.Bold }
            }
            T {
                width: parent.width
                text: [p.pl?.trackArtist, p.pl?.trackAlbum].filter(s => s).join("  —  ")
                color: Look.dim
                elide: Text.ElideRight
            }
        }
    }

    LyricLines { width: parent.width }
    // no lines: say why (still looking, none anywhere, or which source failed)
    T {
        visible: !!Lyrics.status
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: ({ searching: "Looking for lyrics…", none: "No synced lyrics found", error: "Lyrics failed: " + Lyrics.error })[Lyrics.status] ?? ""
        color: Lyrics.status === "error" ? Qt.alpha(Look.text, 0.7) : Look.faint
        font.pixelSize: Look.small
    }

    // the timeline: a hairline, the elapsed time riding the playhead, the length at the end
    Item {
        id: line
        width: parent.width
        height: 30
        readonly property real at: width * Player.frac
        T {
            id: now
            x: Math.max(0, Math.min(line.width - width - total.width - 10, line.at - width / 2))
            text: p.fmt(Player.pos)
            color: Look.text
            font { pixelSize: Look.small; weight: Font.DemiBold; features: ({ tnum: 1 }) }
        }
        T {
            id: total
            anchors.right: parent.right
            text: p.fmt(Player.length)
            color: Look.faint
            font { pixelSize: Look.small; features: ({ tnum: 1 }) }
        }
        Rectangle {
            y: 22
            width: parent.width
            height: scrub.hovered ? 3 : 1.5
            radius: height / 2
            color: Qt.alpha("white", 0.14)
            Behavior on height { Anim { type: "fast" } }
            Rectangle { width: line.at; height: parent.height; radius: parent.radius; color: Look.text }
        }
        // the playhead: a short upright tick, under the riding time
        Rectangle {
            x: line.at - 1
            y: 17
            width: 2; height: 11; radius: 1
            color: Look.text
        }
        HoverHandler { id: scrub; enabled: !!p.pl?.canSeek; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            enabled: !!p.pl?.canSeek
            onTapped: e => { p.pl.position = Player.length * Math.max(0, Math.min(1, e.position.x / line.width)); Player.refreshPos() }
        }
    }

    Item {
        width: parent.width
        height: 48
        Ctl {
            anchors.left: parent.left
            glyph: 0xF049D
            small: true
            on: !!p.pl?.shuffle
            enabled: !!p.pl?.shuffleSupported
            onTap: p.pl.shuffle = !p.pl.shuffle
        }
        Row {
            anchors.centerIn: parent
            spacing: 22
            Ctl { glyph: 0xF04AE; onTap: p.pl?.previous() }
            Ctl { glyph: Player.playing ? 0xF03E4 : 0xF040A; main: true; onTap: p.pl?.togglePlaying() }
            Ctl { glyph: 0xF04AD; onTap: p.pl?.next() }
        }
        Ctl {
            anchors.right: parent.right
            // MprisLoopState: 0 none, 1 track, 2 playlist
            glyph: p.pl?.loopState === 1 ? 0xF0458 : 0xF0456
            small: true
            on: (p.pl?.loopState ?? 0) !== 0
            enabled: !!p.pl?.loopSupported
            onTap: p.pl.loopState = (p.pl.loopState + 1) % 3
        }
    }

    component Ctl: Rectangle {
        id: c
        property int glyph
        property bool main: false
        property bool small: false
        property bool on: false
        signal tap()
        width: main ? 48 : small ? 30 : 36
        height: width
        radius: width / 2
        anchors.verticalCenter: parent?.verticalCenter
        opacity: enabled ? 1 : 0.3
        color: main ? Look.text : hov.hovered ? Look.hover : "transparent"
        Behavior on color { Fade {} }
        scale: tap.pressed ? 0.9 : 1
        Behavior on scale { Anim { type: "fast" } }
        G {
            anchors.centerIn: parent
            glyph: c.glyph
            font.pixelSize: c.main ? 22 : c.small ? 15 : 19
            color: c.main ? Qt.rgba(Look.surface.r, Look.surface.g, Look.surface.b, 1) : c.on ? Look.accent : c.small ? Look.faint : Look.text
        }
        // a lit dot under a toggle that's on
        Rectangle {
            visible: c.small && c.on
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: 3; height: 3; radius: 1.5
            color: Look.accent
        }
        HoverHandler { id: hov; enabled: c.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tap; enabled: c.enabled; onTapped: c.tap() }
    }
}
