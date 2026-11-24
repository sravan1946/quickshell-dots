import QtQuick
import QtQuick.Effects
import Quickshell
import qs.islands

// The full-screen backdrop the wallpaper and theme pickers share: `source` (a local path; a
// thumbnail is plenty, it's blurred), blurred and vignetted, cross-fading on every change.
// Two layers: the next image decodes into the hidden one and fades in over the shown one once
// it's ready, so fast browsing never flashes. A click on it emits dismissed().
Item {
    id: bd

    property string source: ""
    signal dismissed()

    property Item front: null
    readonly property string want: source ? "file://" + source : ""

    function promote(l) { front = l; l.fadeIn() }

    // Where `look` grows the new wallpaper out of (awww --transition-pos): the chosen card,
    // centre and a bit above middle. Both pickers pass it to `look` as LOOK_POS.
    readonly property string growFrom: "0.5,0.45"
    onWantChanged: {
        if (!want || front?.wanted === want) return       // already showing it
        const l = front === la ? lb : la
        // the hidden layer may still hold this image from a moment ago (right, then back
        // left): its source wouldn't change, no status change would come, so promote it now
        if (l.wanted === want && l.status === Image.Ready) return promote(l)
        l.wanted = want
        l.source = want
    }

    Item {
        anchors.fill: parent
        layer.enabled: bd.visible && bd.opacity > 0
        layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 56; saturation: 0.15 }

        component Layer: Image {
            id: layer
            property string wanted: ""     // source as asked for (source itself comes back %-encoded)
            function fadeIn() { fade.restart() }
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(640, 360)   // blurred anyway: small decodes fast
            z: bd.front === layer ? 1 : 0
            opacity: 0
            onStatusChanged: if (status === Image.Ready && wanted === bd.want && bd.front !== layer) bd.promote(layer)
            Anim { id: fade; target: layer; property: "opacity"; from: 0; to: 1; type: "enter" }
        }
        Layer { id: la }
        Layer { id: lb }
    }
    // dark at the edges and the bottom, so the cards and the text over it read
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha("black", 0.55) }
            GradientStop { position: 0.45; color: Qt.alpha("black", 0.25) }
            GradientStop { position: 1.0; color: Qt.alpha("black", 0.75) }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: bd.dismissed() }
}
