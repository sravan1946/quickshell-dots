pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit

// The polkit agent (replaces hyprpolkitagent): an app asking for authentication drops a card
// out of the clock on the focused monitor (panels/Auth.qml). PAM decides what it asks for:
// with pam_fprintd first in /etc/pam.d/polkit-1 it waits for a finger, then falls back to the
// password. `showing` outlives the flow by a moment so a success can be seen before it closes.
//
// polkit tells an agent the action, not the caller, so "who's asking" is the action's own
// .policy file in /usr/share/polkit-1/actions and the package that installed it.
//
//   qs -c bar ipc call auth preview finger|pass|error|ok   (a fake request, for looking at it)
//   qs -c bar ipc call auth preview ""                      (close it)
//
// sudo shows in the same card, without polkit: /etc/pam.d/sudo runs sudo-bar-hook (in
// ../sudo/) around pam_fprintd, which calls sudo() with where it is (finger, pass, ok), and
// SUDO_ASKPASS=bar-askpass calls ask() and waits on a fifo for what's typed here. The stage is
// driven through `preview` (no AuthFlow); `sudo` says it's real. SSH_ASKPASS is bar-askpass too:
// the same card, for ssh's passphrase or its yes/no questions, with the git command and remote
// that set it off. Only sudo has a PAM hook to say how it went; for ssh the card goes on answer,
// and comes back with "didn't work" if ssh asks again.
Singleton {
    id: s
    readonly property AuthFlow flow: agent.flow
    property bool showing: false
    property bool ok: false            // succeeded: the card shows it, then goes
    property int fails: 0              // wrong password/finger rounds in this request
    property string message: ""
    property string icon: ""
    property string action: ""         // the polkit action id
    property string app: ""            // the policy's vendor, or its package
    property string pkg: ""            // the package that installed the policy ("" if none did)
    property bool found: false         // a policy file defines the action at all
    property string preview: ""        // a fake stage, from IPC
    // skipping the finger: kill fprintd (allowed without a prompt by
    // /etc/polkit-1/rules.d/49-fprintd-skip.rules), so pam_fprintd gives up and PAM asks for the
    // password at once. What was typed meanwhile goes into the box. Once skipped, later rounds
    // of the same request (after a wrong password) skip the finger too.
    property bool skipping: false
    property bool preferPass: false
    property string typed: ""
    // ---- sudo ----
    property bool sudo: false
    property int sudoPid: 0
    property string fifo: ""           // the askpass waiting for an answer ("" if none is)
    property bool cancelled: false
    property bool answered: false      // a password went back: another ask() means it was wrong
    property string prompt: ""         // what the askpass was asked ("[sudo] password for …:", ssh's)
    property string remote: ""         // host:repo, for ssh run by git
    property string mode: "secret"     // secret, text (a visible answer) or confirm (OK/Cancel)
    property string cwd: ""            // where the command runs, ~ for home
    readonly property bool hooked: app === "sudo"   // sudo-bar-hook reports the outcome
    // the prompt as a heading: "Passphrase for ~/.ssh/id_ed25519", "Password for sravan"
    readonly property string ask: {
        const home = Quickshell.env("HOME")
        const t = prompt.replace(/^\[sudo\]\s*/, "").replace(/^Enter\s+/i, "")
            .replace(/key '([^']+)'/, (m, k) => k.replace(home, "~")).replace(/[:\s]+$/, "")
        return t.charAt(0).toUpperCase() + t.slice(1)
    }

    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: {
            doneT.stop()
            s.sudo = false
            s.preview = ""
            s.ok = false
            s.fails = 0
            s.skipping = false
            s.preferPass = false
            s.typed = ""
            s.message = flow?.message ?? ""
            s.icon = flow?.iconName ?? ""
            s.lookup(flow?.actionId ?? "")
            s.showing = true
        }
        // the flow ends however it ends: success holds the card a moment, anything else closes it
        onIsActiveChanged: if (!isActive) endT.restart()
    }
    Connections {
        target: agent.flow
        ignoreUnknownSignals: true
        function onAuthenticationSucceeded() { s.ok = true; doneT.restart() }
        function onAuthenticationFailed() { s.fails++ }
        function onIsResponseRequiredChanged() { if (agent.flow?.isResponseRequired) s.skipping = false }
        // a fresh round asking for the finger again, after the user chose the password
        function onSupplementaryMessageChanged() {
            if (s.preferPass && /finger|swipe|touch/i.test(agent.flow?.supplementaryMessage ?? "")) s.skipFinger("")
        }
    }
    Timer { id: endT; interval: 60; onTriggered: if (!s.ok && !agent.isActive && !s.preview) s.showing = false }
    Timer { id: doneT; interval: 650; onTriggered: if (!agent.isActive) { s.showing = false; s.preview = ""; s.sudo = false } }

    function submit(v) {
        if (sudo) {
            if (!fifo) return
            reply("P" + v); answered = true
            if (hooked) preview = "wait"
            else { preview = ""; showing = false; sudo = false }
            return
        }
        if (!preview) { flow?.submit(v); return }
        if (v === "") { preview = "error"; fails++ } else { preview = "ok"; ok = true; doneT.restart() }
    }
    function skipFinger(first) {
        typed += first ?? ""
        preferPass = true
        if (skipping) return
        skipping = true
        if (preview && !sudo) { preview = "pass"; skipping = false; return }
        Quickshell.execDetached(["systemctl", "kill", "--no-ask-password", "--signal=SIGKILL", "fprintd.service"])
    }
    function cancel() {
        if (flow) { flow.cancelAuthenticationRequest(); return }
        if (sudo) {
            // the askpass gets "C"; mid-finger, drop the finger so sudo gets to the askpass
            cancelled = true
            if (fifo) reply("C")
            else Quickshell.execDetached(["systemctl", "kill", "--no-ask-password", "--signal=SIGKILL", "fprintd.service"])
        }
        preview = ""; showing = false; sudo = false
    }

    // ---- sudo (sudo-bar-hook and bar-askpass) ----
    function sudoStart(pid, cmd, cwd) {
        const here = cwd ? cwd.replace(new RegExp("^" + Quickshell.env("HOME")), "~") : ""
        if (sudo && pid === sudoPid) {   // the hook can't always read sudo's cwd; the askpass can
            if (!s.cwd && here) s.cwd = here
            return
        }
        doneT.stop()
        sudo = true; sudoPid = pid; fifo = ""; cancelled = false; answered = false
        ok = false; fails = 0; skipping = false; preferPass = false; typed = ""
        app = (cmd.split(" ")[0] || "sudo").split("/").pop(); pkg = ""; found = false; icon = ""
        message = cmd.replace(/^\S*sudo(\s+-\S+)*\s+/, "").trim()
        action = ""; s.cwd = here; prompt = ""; remote = ""; mode = "secret"
        showing = true
    }
    // the answer goes in the environment, not argv: /proc/*/environ is yours alone
    function reply(line) {
        answer.environment = { A: line }
        answer.command = ["sh", "-c", '[ -p "$1" ] && printf "%s\\n" "$A" > "$1"', "sh", fifo]
        fifo = ""
        answer.running = true
    }
    Process { id: answer }
    // sudo is gone (cancelled, or out of tries): whatever's showing for it goes. Polled, and
    // only while a sudo card is up
    Timer {
        interval: 1000
        repeat: true
        running: s.sudo && s.showing
        onTriggered: if (!alive.running) { alive.pid = s.sudoPid; alive.command = ["test", "-d", "/proc/" + s.sudoPid]; alive.running = true }
    }
    Process {
        id: alive
        property int pid
        onExited: code => { if (code !== 0 && s.sudo && pid === s.sudoPid && !s.ok) { if (s.fifo) s.reply("C"); s.preview = ""; s.showing = false; s.sudo = false } }
    }
    Timer {   // "pass" with no askpass coming: a terminal sudo, the password goes there
        id: ttyT
        interval: 1500
        onTriggered: if (s.sudo && !s.fifo && s.preview === "wait") { s.preview = ""; s.showing = false; s.sudo = false }
    }

    // ---- who's asking: the policy file defining the action, its vendor, its package ----
    function lookup(id) {
        action = id; app = ""; pkg = ""; found = false
        if (!id) return
        who.command = ["sh", "-c",
            'f=$(grep -l -F "id=\\"$1\\"" /usr/share/polkit-1/actions/*.policy 2>/dev/null | head -1); [ -n "$f" ] || exit 0; ' +
            'printf "%s\\n" "$(sed -n "s:.*<vendor>\\(.*\\)</vendor>.*:\\1:p" "$f" | head -1)"; pacman -Qqo "$f" 2>/dev/null | head -1; echo',
            "sh", id]
        who.running = true
    }
    Process {
        id: who
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n")
                s.pkg = (l[1] ?? "").trim()
                s.found = l.length > 1
                // no <vendor>: the app's name from the action id (com.bitwarden.Bitwarden.unlock)
                const parts = s.action.split(".")
                const guess = parts.length > 2 ? parts[parts.length - 2] : s.pkg
                s.app = (l[0] ?? "").trim() || (guess.charAt(0).toUpperCase() + guess.slice(1))
            }
        }
    }

    IpcHandler {
        target: "auth"
        // from sudo-bar-hook (root's PAM, run as you)
        function sudo(stage: string, pid: int, cmd: string, cwd: string): void {
            if (s.flow) return
            if (stage === "finger") { s.sudoStart(pid, cmd, cwd); s.preview = "finger"; return }
            if (!s.sudo || pid !== s.sudoPid || s.cancelled) return
            if (stage === "pass") { if (!s.fifo) { s.preview = "wait"; ttyT.restart() } }
            else if (stage === "ok") { s.ok = true; s.preview = "ok"; doneT.restart() }
        }
        // from bar-askpass: answer into `fifo`
        function ask(fifo: string, pid: int, cmd: string, cwd: string, prompt: string, remote: string, mode: string): void {
            if (s.flow) { Quickshell.execDetached(["sh", "-c", 'echo C > "$1"', "sh", fifo]); return }
            // the same process asking again after an answer went back: that answer was wrong
            const wrong = pid === s.sudoPid && s.answered, missed = s.fails
            ttyT.stop()   // the askpass came: not a terminal sudo after all
            s.sudoStart(pid, cmd, cwd)
            s.prompt = prompt; s.remote = remote; s.mode = mode || "secret"
            s.fifo = fifo
            if (s.cancelled) { s.reply("C"); return }
            if (wrong) { s.fails = missed + 1; s.preview = "error" }
            else s.preview = "pass"
            s.skipping = false
        }
        function preview(stage: string): void {
            if (s.flow || s.sudo) return
            if (!stage) { s.preview = ""; s.showing = false; return }
            s.ok = stage === "ok"
            s.fails = stage === "error" ? 1 : 0
            s.message = "Authenticate to unlock Bitwarden"
            s.icon = ""
            s.lookup("com.bitwarden.Bitwarden.unlock")
            s.preview = stage
            s.showing = true
        }
    }
}
