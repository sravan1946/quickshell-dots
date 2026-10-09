#!/bin/sh
# Run by quickshell-bar-reload.service when the bar's config changes (quickshell-bar-reload.path).
# 1. Let the burst of writes settle, so one reload sees all of it.
# 2. Reload over IPC. For a second or two after a reload the bar answers "Not ready to accept
#    queries yet" (an edit landing then was lost), so retry for up to ~5 s.
# 3. A newly added inline component (`component X: ...`) fails a hot reload with "X is not a
#    type" though a fresh start loads it fine: in that case restart the bar.
sleep 0.4
log() {
    id=$(qs list --all 2>/dev/null | grep -B3 "quickshell/bar/shell.qml" | sed -n 's/^Instance \(.*\):$/\1/p' | head -1)
    [ -n "$id" ] && echo "$XDG_RUNTIME_DIR/quickshell/by-id/$id/log.log"
}
f=$(log)
before=$( [ -n "$f" ] && wc -l < "$f" || echo 0)
for i in $(seq 20); do
    out=$(qs -c bar ipc call bar reload 2>&1) && ! echo "$out" | grep -q "Not ready" && break
    sleep 0.25
done
sleep 1.5
if [ -n "$f" ] && tail -n +"$((before + 1))" "$f" | grep -q "is not a type"; then
    echo "hot reload can't take a new inline component: restarting the bar"
    systemctl --user restart quickshell-bar
fi
exit 0
