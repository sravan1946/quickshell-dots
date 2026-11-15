#!/bin/bash
# Tablet mode for a convertible whose hinge switch can't be trusted (it fires on a tilt), so
# it is flipped by hand: the bar's quick-settings tile, or `tablet-mode.sh toggle`.
#   on|off|toggle  built-in keyboard and touchpad off/on, on-screen keyboard up/down
#   rotate         follow the accelerometer (iio-sensor-proxy); runs as tablet-rotate.service
# State is in $XDG_RUNTIME_DIR/tablet-mode (1/0), which the tile watches. Everything is set
# through `hyprctl eval`, so a Hyprland reload or a new login puts it back to laptop mode.

state=${XDG_RUNTIME_DIR:-/run/user/$UID}/tablet-mode
panel=eDP-1
# names from `hyprctl devices`; anything not listed (touchscreen, stylus, power button) stays on
devices=(
	at-translated-set-2-keyboard
	asue140d:00-04f3:31bc-keyboard
	asue140d:00-04f3:31bc-touchpad
	asue140d:00-04f3:31bc-mouse
)

set_mode() { # 1 = tablet, 0 = laptop
	local enabled=true
	[ "$1" = 1 ] && enabled=false
	for d in "${devices[@]}"; do
		hyprctl -q eval "hl.device({ name = \"$d\", enabled = $enabled })"
	done
	if [ "$1" = 1 ]; then
		command -v squeekboard >/dev/null &&
			systemd-run --user --quiet --collect --unit=tablet-osk squeekboard
	else
		systemctl --user --quiet stop tablet-osk 2>/dev/null
	fi
	echo "$1" >"$state"
}

rotate() { # screen, touchscreen and stylus together
	local t
	case $1 in
	normal) t=0 ;;
	left-up) t=1 ;;
	bottom-up) t=2 ;;
	right-up) t=3 ;;
	*) return ;;
	esac
	# hl.monitor replaces the whole rule, so carry the current mode, position and scale over
	local rule
	rule=$(hyprctl -j monitors | jq -r --arg p "$panel" --argjson t "$t" '.[] | select(.name == $p) |
		"{ output = \"\(.name)\", mode = \"\(.width)x\(.height)@\(.refreshRate)\", position = \"\(.x)x\(.y)\", scale = \(.scale), transform = \($t) }"')
	[ -n "$rule" ] || return
	hyprctl -q eval "hl.monitor($rule) hl.config({ input = { touchdevice = { transform = $t }, tablet = { transform = $t } } })"
}

case $1 in
on) set_mode 1 ;;
off) set_mode 0 ;;
toggle) [ "$(cat "$state" 2>/dev/null)" = 1 ] && set_mode 0 || set_mode 1 ;;
rotate)
	[ -e "$state" ] || echo 0 >"$state" # so the tile has a file to watch
	monitor-sensor --accel | while read -r line; do
		case $line in *"orientation changed: "*) rotate "${line##*: }" ;; esac
	done
	;;
*) echo "usage: $0 on|off|toggle|rotate" >&2; exit 2 ;;
esac
