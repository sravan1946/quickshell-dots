pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Every notification the daemon receives, newest first, kept across restarts.
// ponytail: rewrites the whole file per change (max 100 small entries), fine until it isn't
Singleton {
    id: root

    readonly property alias entries: model
    readonly property int max: 100

    ListModel { id: model }

    // actions worth drawing: the unlabelled "default" action is the card click, not a button
    function buttons(actions) { return actions.filter(a => a.identifier !== "default" && a.text.trim() !== "") }

    // a one-time code worth a copy button: only when the text says it is a code, so
    // years, amounts and order numbers in ordinary notifications don't get one
    function otp(summary, body) {
        const t = (summary + " " + body).replace(/<[^>]*>/g, " ")
        if (!/\b(otp|code|passcode|verification|verify|2fa|one[- ]time|pin)\b/i.test(t)) return ""
        const m = t.match(/(?:^|[^\d.,:\/])(\d{4,8})(?![\d]|[.,:\/-]\d)/)
        return m ? m[1] : ""
    }
    function copy(text) { Quickshell.execDetached(["wl-copy", "--", text]) }

    function add(n) {
        model.insert(0, {
            app: n.appName, summary: n.summary, body: n.body, time: Date.now(),
            buttons: JSON.stringify(buttons(n.actions).map(a => a.text)),
            icon: n.appIcon !== "" ? Quickshell.iconPath(n.appIcon, true) : ""
        })
        while (model.count > max) model.remove(model.count - 1)
        save()
    }
    function remove(i) { model.remove(i); save() }
    function removeApp(app) {
        for (let i = model.count - 1; i >= 0; i--) if (model.get(i).app === app) model.remove(i)
        save()
    }
    function clear() { model.clear(); save() }

    function save() {
        const out = []
        for (let i = 0; i < model.count; i++) out.push(model.get(i))
        file.setText(JSON.stringify(out))
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.cache/quickshell-notifs.json"
        printErrors: false
        onLoaded: {
            try { for (const e of JSON.parse(text()).reverse()) model.insert(0, Object.assign({ buttons: "[]" }, e)) } catch (e) {}
        }
        // first run: no file yet
        onLoadFailed: {}
    }
}
