import QtQuick
import QtQuick.Shapes
import Quickshell
import qs
import qs.islands

// An app asking for authentication (AuthState, the polkit agent), dropped out of the clock.
// What it shows follows the PAM conversation, and nothing is drawn before PAM says what it
// wants: a ring waiting for a finger, a password box once a password is asked for, green when
// it's through. The body keeps one height through every stage, so the card never resizes
// mid-conversation. Esc cancels.
Panel {
    id: p
    implicitWidth: 300
    spacing: 14
    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: AuthState.cancel()
    // typing while it waits for a finger: skip the finger, the letters go into the password box
    Keys.onPressed: e => {
        if ((stage === "finger" || stage === "wait") && e.text.length && e.text.charCodeAt(0) >= 32) {
            AuthState.skipFinger(e.text)
            e.accepted = true
        }
    }

    readonly property var flow: AuthState.flow
    readonly property string pv: AuthState.preview      // a fake request (IPC), for looking at it
    readonly property string said: pv === "error" ? "Sorry, that didn't work" : flow?.supplementaryMessage ?? ""
    readonly property bool error: pv === "error" || (!!flow?.supplementaryIsError && said !== "")
    readonly property bool finger: pv === "finger" || /finger|swipe|touch/i.test(said)
    readonly property string stage: AuthState.ok ? "ok"
        : pv === "pass" || pv === "error" || flow?.isResponseRequired ? "pass"
        : finger ? "finger" : "wait"
    // what success means here: unlocking something (Bitwarden), sudo running the command, or
    // polkit letting an action through
    readonly property string done: /unlock/i.test(AuthState.action + " " + AuthState.message) ? "Unlocked"
        : AuthState.sudo ? "Running it"
        : "Allowed"
    onStageChanged: if (stage === "pass") {
        field.text = AuthState.typed + field.text
        AuthState.typed = ""
        Qt.callLater(field.grab)
    }

    // a miss shakes what was being used (the ring or the box)
    property real shake: 0
    SequentialAnimation {
        id: shakeA
        NumberAnimation { target: p; property: "shake"; to: 1; duration: 45 }
        NumberAnimation { target: p; property: "shake"; to: -1; duration: 70 }
        NumberAnimation { target: p; property: "shake"; to: 0.6; duration: 60 }
        NumberAnimation { target: p; property: "shake"; to: 0; duration: 90; easing.type: Easing.OutCubic }
    }
    onErrorChanged: if (error) shakeA.restart()
    Connections { target: AuthState; function onFailsChanged() { if (AuthState.fails) shakeA.restart() } }

    // ---- who's asking ----
    Row {
        width: parent.width
        spacing: 12
        Rectangle {
            id: badge
            width: 34; height: 34
            radius: 11
            color: Look.raise
            Image {
                id: appIcon
                readonly property string src: AuthState.icon ? Quickshell.iconPath(AuthState.icon, true) : ""
                anchors.centerIn: parent
                width: 20; height: 20
                visible: src !== "" && status === Image.Ready
                source: src
                sourceSize: Qt.size(40, 40)
                mipmap: true
            }
            G {
                anchors.centerIn: parent
                visible: !appIcon.visible
                glyph: 0xF099D
                color: Look.accent
                font.pixelSize: 17
            }
        }
        Column {
            width: parent.width - badge.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            T {
                width: parent.width
                text: (AuthState.app ? AuthState.app + " asks" : "Authentication required")
                color: Look.faint
                font.pixelSize: Look.small
                elide: Text.ElideRight
            }
            T {
                width: parent.width
                text: AuthState.message
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            // what's asked: the polkit action, and where its policy came from (a package, or
            // not: an app that installed its own, like Bitwarden)
            T {
                width: parent.width
                topPadding: 2
                text: AuthState.action + (!AuthState.found ? "" : "  ·  " + (AuthState.pkg ? AuthState.pkg + " package" : "policy from no package"))
                visible: AuthState.action !== ""
                color: Look.faint
                font.pixelSize: 10
                wrapMode: Text.Wrap
            }
        }
    }

    // ---- the body: one height, the stages cross-fade inside it ----
    Item {
        width: parent.width
        height: 110

        // finger (and wait, and ok): the ring
        Item {
            id: ringView
            anchors.fill: parent
            opacity: p.stage === "pass" ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { Anim { type: "effects" } }

            Item {
                id: ring
                width: 56; height: 56
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: p.shake * 7
                y: 2
                readonly property color col: p.stage === "ok" ? Look.good
                    : p.error || (AuthState.fails > 0 && p.stage === "finger" && !p.said) ? Look.alert
                    : Look.accent
                // waiting for PAM: dim; waiting for the finger: a lit arc circling; through: closed green
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Qt.alpha("white", 0.09)
                        strokeWidth: 2
                        fillColor: Qt.alpha(ring.col, p.stage === "ok" ? 0.16 : 0.07)
                        Behavior on fillColor { Fade {} }
                        PathAngleArc { centerX: 28; centerY: 28; radiusX: 27; radiusY: 27; startAngle: 0; sweepAngle: 360 }
                    }
                }
                Shape {
                    id: arc
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    opacity: p.stage === "wait" ? 0 : 1
                    Behavior on opacity { Anim { type: "effects" } }
                    property real sweep: p.stage === "ok" ? 360 : 70
                    Behavior on sweep { Anim { type: "enter" } }
                    ShapePath {
                        strokeColor: ring.col
                        Behavior on strokeColor { Fade {} }
                        strokeWidth: 2.4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: 28; centerY: 28; radiusX: 27; radiusY: 27; startAngle: -90; sweepAngle: arc.sweep }
                    }
                    // circles only while it waits for a finger (rule 17: no idle repaint otherwise)
                    RotationAnimation on rotation {
                        running: p.stage === "finger"
                        loops: Animation.Infinite
                        from: arc.rotation; to: arc.rotation + 360
                        duration: 1800
                    }
                }
                G {
                    anchors.centerIn: parent
                    glyph: p.stage === "ok" ? 0xF012C : 0xF0237
                    height: 30
                    font.pixelSize: 28
                    color: p.stage === "wait" ? Look.faint : ring.col
                    Behavior on color { Fade {} }
                }
            }
            T {
                anchors.horizontalCenter: parent.horizontalCenter
                y: caption.y + caption.height + 2
                text: "or just start typing your password"
                opacity: p.stage === "finger" && !AuthState.skipping && !p.error ? 1 : 0
                Behavior on opacity { Anim { type: "effects" } }
                color: Look.faint
                font.pixelSize: Look.small
            }
            T {
                id: caption
                anchors.horizontalCenter: parent.horizontalCenter
                y: ring.y + ring.height + 12
                text: p.stage === "ok" ? p.done
                    : p.stage === "wait" ? " "
                    : AuthState.skipping ? "Switching to password…"
                    : p.error ? "Not recognised, try again"
                    : "Touch the fingerprint sensor"
                color: p.error ? Look.alert : p.stage === "ok" ? Look.good : Look.dim
                Behavior on color { Fade {} }
            }
        }

        // pass: the password box
        Column {
            id: passView
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 10
            opacity: p.stage === "pass" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Anim { type: "effects" } }
            Field {
                id: field
                x: p.shake * 7
                width: parent.width
                implicitHeight: 34
                secret: !(p.flow?.responseVisible ?? false)
                glyph: 0xF033E
                hint: (p.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password"
                onAccepted: { AuthState.submit(text); text = "" }
            }
            T {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: p.error ? p.said
                    : AuthState.fails > 0 ? "That didn't work, try again"
                    : AuthState.preferPass ? " "
                    : p.finger ? "Fingerprint not recognised, use your password"
                    : p.said || " "
                color: p.error || AuthState.fails > 0 ? Look.alert : Look.dim
                font.pixelSize: Look.small
                elide: Text.ElideRight
            }
        }
    }

    // ---- what's asked (the polkit action and the package that defines it), and the buttons ----
    Item {
        width: parent.width
        height: buttons.height
        T {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - buttons.width - 12
            // in the finger stage: what happens if it doesn't take
            text: ""
            color: Look.faint
            font.pixelSize: Look.small
            elide: Text.ElideMiddle
        }
        Row {
            id: buttons
            anchors.right: parent.right
            spacing: 8
            Btn { visible: p.stage === "finger" && !AuthState.skipping; text: "Use password"; onClicked: AuthState.skipFinger("") }
            Btn { text: "Cancel"; onClicked: AuthState.cancel() }
            Btn {
                visible: p.stage === "pass"
                text: "Unlock"
                strong: true
                onClicked: { AuthState.submit(field.text); field.text = "" }
            }
        }
    }
}
