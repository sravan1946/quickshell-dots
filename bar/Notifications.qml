import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs

// Popup-only notification daemon (replaces dunst/swaync). Colours come from Theme,
// so HyDE theme switches recolour it like the bar.
// Only one daemon can own org.freedesktop.Notifications: keep swaync/dunst masked.
// DND (Config.dnd) hides the popups but keeps every notification tracked, so they
// show again when it is turned off.
// History.qml keeps what was received; the panel lives in modules/Dnd.qml.
Scope {
    readonly property int slide: 392   // window width: cards slide in from the screen edge

    NotificationServer {
        id: server
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: true
        // false: a reload would re-emit every still-tracked notification as new, re-popping
        // and re-logging it (a 100+ flood on 2026-10-06). Live popups are in History anyway.
        keepOnReload: false
        // every notification goes to the history (unless paused); while the history panel
        // is open and logging, it is the only place it shows, so no popup
        onNotification: n => {
            // a fresh stack opens on the monitor the cursor is on; it stays put until cleared
            if (server.trackedNotifications.values.length === 0)
                win.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            if (!Config.historyPaused) History.add(n)
            n.tracked = !(Config.historyOpen && !Config.historyPaused)
        }
    }
    // opening the history panel clears live popups: they are all in the history
    Connections {
        target: Config
        function onHistoryOpenChanged() {
            if (Config.historyOpen && !Config.historyPaused) [...server.trackedNotifications.values].forEach(n => n.tracked = false)
        }
    }
    Binding { target: Config; property: "held"; value: server.trackedNotifications.values.length }

    // qs -c bar ipc call notifications toggleDnd
    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { Config.dnd = !Config.dnd }
        function toggleHistory(): void { Config.toggleHistory() }
        function toggleLogging(): void { Config.historyPaused = !Config.historyPaused }
    }

    PanelWindow {
        id: win
        anchors { top: true; right: true }
        margins { top: Config.height + 8 }
        implicitWidth: slide
        // full height under the bar; the mask keeps the empty part click-through
        implicitHeight: (screen ? screen.height : 1080) - Config.height - 16
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // click-through everywhere except the cards
        mask: Region { item: bounds }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notifications"   // HyDE's blur layerrule lists notifications

        // what the cards and the clear-all pill cover; everything else is click-through
        Item {
            id: bounds
            width: 380
            height: Config.dnd ? 0 : list.y + list.height
        }

        ListView {
            id: list
            // the clear-all pill sits above the stack
            y: clearAll.shown ? clearAll.height + 8 : 0
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            width: 380
            // a burst taller than the screen scrolls instead of running off the bottom.
            // DND only fades it (and drops it from the mask): collapsing the height cut the fade off
            height: Math.min(contentHeight, win.height - y)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 8
            model: server.trackedNotifications
            opacity: Config.dnd ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; from: slide; to: 0; duration: 280; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
                }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; to: slide; duration: 200; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: 160 }
                }
            }
            // new cards land at the bottom: keep them in view unless you're reading the stack
            HoverHandler { id: listHover }
            onCountChanged: if (!listHover.hovered) Qt.callLater(() => list.positionViewAtEnd())

            displaced: Transition {
                NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
            }

            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool critical: modelData.urgency === NotificationUrgency.Critical

                width: list.width
                height: content.implicitHeight + 24
                radius: Theme.radius
                color: hover.hovered ? Qt.lighter(Theme.mainBg, 1.3) : Theme.mainBg
                Behavior on color { ColorAnimation { duration: 150 } }
                border { width: 2; color: critical ? "#f7768e" : Theme.mainFg }

                // expireTimeout arrives in ms (the docs say seconds); <= 0 means server default; critical never expires
                Timer {
                    running: !hover.hovered && !card.critical && !Config.dnd
                    interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout : Settings.notifTimeout
                    onTriggered: card.modelData.tracked = false
                }
                HoverHandler { id: hover }
                // left: run the "default" action (what clicking the card itself should do, e.g.
                // focus the sender) and dismiss. middle: dismiss this one. right: dismiss all.
                TapHandler {
                    onTapped: {
                        if (closeMouse.containsMouse || btnHover.hovered) return
                        const d = card.modelData.actions.find(a => a.identifier === "default")
                        if (d) d.invoke()
                        card.modelData.tracked = false
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.MiddleButton
                    onTapped: card.modelData.tracked = false
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: [...server.trackedNotifications.values].forEach(n => n.tracked = false)
                }

                RowLayout {
                    id: content
                    anchors { fill: parent; margins: 12 }
                    spacing: 12

                    Image {
                        readonly property string src: card.modelData.image !== "" ? card.modelData.image
                            : (card.modelData.appIcon !== "" ? Quickshell.iconPath(card.modelData.appIcon, true) : "")
                        visible: src !== ""
                        source: src
                        // device pixels on the 1.5x screen; fit, so non-square images aren't squashed
                        sourceSize: Qt.size(80, 80)
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            color: Theme.mainFg
                            font { family: Theme.font; pixelSize: 14; bold: true }
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.body
                            textFormat: Text.StyledText
                            color: Theme.actFg
                            font { family: Theme.font; pixelSize: 13 }
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }
                        Row {
                            id: buttons
                            HoverHandler { id: btnHover }   // a button press must not also count as a card click
                            readonly property var labelled: History.buttons(card.modelData.actions)
                            readonly property string code: History.otp(card.modelData.summary, card.modelData.body)
                            spacing: 6
                            visible: labelled.length > 0 || code !== ""
                            Rectangle {
                                visible: buttons.code !== ""
                                radius: 8
                                color: codeHover.hovered ? Qt.lighter(Theme.actBg, 1.12) : Theme.actBg
                                Behavior on color { ColorAnimation { duration: 120 } }
                                HoverHandler { id: codeHover; cursorShape: Qt.PointingHandCursor }
                                implicitWidth: codeLabel.implicitWidth + 16
                                implicitHeight: codeLabel.implicitHeight + 8
                                Text {
                                    id: codeLabel
                                    anchors.centerIn: parent
                                    text: Theme.g(0xF018F) + " Copy " + buttons.code
                                    color: Theme.mainBg
                                    font { family: Theme.font; pixelSize: 12 }
                                }
                                TapHandler { onTapped: { History.copy(buttons.code); card.modelData.tracked = false } }
                            }
                            Repeater {
                                model: buttons.labelled
                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 8
                                    color: actHover.hovered ? Qt.lighter(Theme.actBg, 1.12) : Theme.actBg
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
                                    implicitWidth: label.implicitWidth + 16
                                    implicitHeight: label.implicitHeight + 8
                                    Text {
                                        id: label
                                        anchors.centerIn: parent
                                        text: parent.modelData.text
                                        color: Theme.mainBg
                                        font { family: Theme.font; pixelSize: 12 }
                                    }
                                    TapHandler { onTapped: { parent.modelData.invoke(); card.modelData.tracked = false } }
                                }
                            }
                        }
                    }
                    Text {
                        text: Theme.g(0xF0156)
                        color: closeMouse.containsMouse ? "#f7768e" : Theme.mainFg
                        opacity: closeMouse.containsMouse ? 1 : 0.6
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        font { family: Theme.font; pixelSize: 14 }
                        Layout.alignment: Qt.AlignTop
                        MouseArea {
                            id: closeMouse
                            anchors { fill: parent; margins: -4 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.modelData.tracked = false
                        }
                    }
                }
            }
        }

        // only worth a button when there is a stack to clear; sits above it
        Rectangle {
            id: clearAll
            readonly property bool shown: !Config.dnd && list.count > 1
            opacity: shown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            x: list.width - width
            y: 0
            radius: height / 2
            color: clearMouse.containsMouse ? Theme.hvrBg : Theme.mainBg
            border { width: 1; color: Theme.mainFg }
            implicitWidth: clearLabel.implicitWidth + 24
            implicitHeight: 26
            width: implicitWidth
            height: implicitHeight
            Behavior on color { ColorAnimation { duration: 150 } }
            Text {
                id: clearLabel
                anchors.centerIn: parent
                text: "Clear all"
                color: clearMouse.containsMouse ? Theme.hvrFg : Theme.mainFg
                font { family: Theme.font; pixelSize: 12 }
            }
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: [...server.trackedNotifications.values].forEach(n => n.tracked = false)
            }
        }
    }
}
