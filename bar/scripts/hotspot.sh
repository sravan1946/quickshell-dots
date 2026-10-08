#!/bin/sh
# Wi-Fi hotspot for the tray's Wi-Fi panel (components/WifiMenu.qml), always alongside the
# Wi-Fi link on a second interface (ap0); it never takes the link down.
#   hotspot.sh can   exit 0 if it can start now, else print why: no-dnsmasq | no-link | radar | no-sudo
#   hotspot.sh on    start it (exits 1 with the same reasons when it can't)
#   hotspot.sh off   stop it and remove ap0
# One radio on one channel: the hotspot shares the link's channel, and the driver won't
# host a network on a radar (DFS) one, so on those it can't run. NetworkManager hands out
# addresses to joining devices with dnsmasq, which has to be installed. ap0 needs root for `iw`,
# granted once by a sudoers rule:
#   <user> ALL=(root) NOPASSWD: /usr/bin/iw dev <dev> interface add ap0 type __ap, /usr/bin/iw dev ap0 del
# The "Hotspot" profile is made once (random password) and reused, so the name, password
# and QR stay the same between runs.

dev=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2 == "wifi" && $1 != "ap0" {print $1; exit}')
[ -n "$dev" ] || { echo no-link; exit 1; }
freq=$(iw dev "$dev" link | awk '/freq:/ {print int($2); exit}')

why() {
    command -v dnsmasq >/dev/null || { echo no-dnsmasq; return; }
    [ -n "$freq" ] || { echo no-link; return; }
    phy=$(cat "/sys/class/net/$dev/phy80211/name")
    # the link channel's block in `iw phy <phy> channels`
    iw phy "$phy" channels | awk -v f="$freq" '
        $0 ~ "\\* " f " MHz" { on = 1; if (/disabled/) bad = 1; next }
        on && /\* [0-9]+ MHz/ { exit }
        on && /Radar detection/ { bad = 1 }
        END { exit bad || !on }' || { echo radar; return; }
    [ -e /sys/class/net/ap0 ] || sudo -n -l /usr/bin/iw dev "$dev" interface add ap0 type __ap >/dev/null 2>&1 || echo no-sudo
}

case "$1" in
    can)
        r=$(why); [ -z "$r" ] || { echo "$r"; exit 1; } ;;
    on)
        r=$(why); [ -z "$r" ] || { echo "$r"; exit 1; }
        [ -e /sys/class/net/ap0 ] || sudo -n /usr/bin/iw dev "$dev" interface add ap0 type __ap || exit 1
        if ! nmcli -t -f NAME con show | grep -qx Hotspot; then
            pw=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)
            nmcli con add type wifi con-name Hotspot ifname ap0 autoconnect no ssid "Hotspot-$(hostname)" \
                802-11-wireless.mode ap 802-11-wireless.cloned-mac-address stable \
                ipv4.method shared ipv6.method ignore \
                wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$pw" >/dev/null
        fi
        # same band and channel as the link; NM gives ap0 its own (stable) MAC
        band=bg; [ "$freq" -ge 5000 ] && band=a
        ch=$(iw dev "$dev" info | awk '/channel/ {print $2; exit}')
        nmcli con modify Hotspot connection.interface-name ap0 802-11-wireless.band "$band" 802-11-wireless.channel "$ch"
        nmcli con up Hotspot ifname ap0 || { sudo -n /usr/bin/iw dev ap0 del; exit 1; } ;;
    off)
        nmcli con down Hotspot
        [ -e /sys/class/net/ap0 ] && sudo -n /usr/bin/iw dev ap0 del ;;
    *) echo "usage: $0 can|on|off" >&2; exit 2 ;;
esac
