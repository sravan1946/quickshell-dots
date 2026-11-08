pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Every copy, whoever made it: what kind (t text, i image, s a password manager's, o other) and
// the start of the text. The bar drops it out of the clock (panels/Clip.qml).
Singleton {
    id: root
    property string kind: ""
    property string text: ""
    signal copied()

    // CLIPBOARD_STATE: data, nil (emptied, e.g. its app quit) or sensitive (KeePassXC & co.)
    Process {
        id: watch
        running: true
        command: ["wl-paste", "--watch", "sh", "-c", `
            cat >/dev/null
            case $CLIPBOARD_STATE in
                sensitive) echo s ;;
                data) case $(wl-paste -l) in
                    *text/plain*) printf t; wl-paste -n -t text | head -c 400 | tr '\\n\\r\\t' '   '; echo ;;
                    *image/*) echo i ;;
                    *) echo o ;;
                esac ;;
            esac`]
        stdout: SplitParser {
            onRead: line => {
                root.kind = line[0]
                root.text = line.slice(1).replace(/\s+/g, " ").trim()
                root.copied()
            }
        }
        onExited: restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: watch.running = true }
}
