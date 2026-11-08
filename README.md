# quickshell-dots

A [Quickshell](https://quickshell.org) desktop shell for Hyprland on top of
[HyDE](https://github.com/HyDE-Project/HyDE). It replaces Waybar, the notification daemon, the
OSD, the polkit agent and wlogout. It also has a small Hyprland plugin that carries the bar's beat
wave onto the focused window's border.

This is **v2, the island bar**. The original pill bar is on the
[`main`](https://github.com/sravan1946/quickshell-dots/tree/main) branch.

## The island bar

Three islands float at the top of each screen:

- **Left:** CPU and memory rings, workspaces with their app icons, the focused window, and
  the music playing.
- **Centre:** the clock.
- **Right:** the tray, network, Bluetooth, privacy, battery, brightness, volume, notifications
  and quick settings.

Rest the pointer on an item and a **card** grows out of the island under it. The card and the
island are drawn as one liquid surface, joined by curved fillets. Move to another item and the
open card slides over and changes its content instead of closing and reopening. Each card is
one panel:

| Item | Card |
|---|---|
| CPU / memory rings | two-minute graph, a bar per core, memory and swap; click for btop |
| workspace | the windows on it; click one to go there |
| window title | the window's app, full title and place, with fullscreen and close |
| music | cover as backdrop, synced lyrics (Musixmatch word timings, lrclib lines), seek filament, controls |
| clock | month calendar with Google Calendar events; a meeting about to start gets its own item |
| caffeine | keep the screen and laptop awake |
| tray icon | the app's own menu, submenus in place |
| network | link, two minutes of traffic, addresses, Wi-Fi networks, VPNs (nmcli, pritunl) |
| Bluetooth | devices, connect/pair/forget, battery per earbud (Nothing/CMF buds) |
| privacy | who is using the mic or capturing the screen |
| battery | charge and time left, the last 12 hours, power mode, health |
| brightness / volume | levels, outputs and inputs, per-app volume |
| bell | do-not-disturb and the notification history, by app |
| quick settings (right end) | session, lock and power, night light, airplane mode, KDE Connect phone, bar update |

Some cards also drop out on their own for a moment, then go back up:

- **Notifications** drop out of the bell, newest on top, with their buttons and a copy chip
  for one-time codes. Critical ones get a red edge and stay until dismissed.
- **Volume and brightness** drop a level out of their icon whenever they change, whatever
  changed them.
- **Copies** drop out of the clock, showing what was copied.
- **Authentication requests** (polkit) drop out of the clock and stay until answered (below).

**Music light.** cava feeds a kick detector (`scripts/kicks.py`). Each kick sends a wave from
the music along the islands' lower edges, an aurora curtain glows under the music item, and a
progress filament hangs under the left island. With the plugin loaded, the wave also runs
around the focused window's border.

**Polkit agent.** It replaces hyprpolkitagent. The prompt follows the PAM conversation instead
of always opening as a password box:

- **Fingerprint:** a ring waits for a finger when `pam_fprintd` is in the stack. If the
  sensor is stuck, click **Use password** or just start typing.
- **Password:** a box with the keyboard already on it.
- **Done:** it turns green when it's through. A mismatch shakes.

The prompt also shows which app and polkit action asked, and whether that action's policy
file came from a package or the app installed it itself.

**Power menu.** The screen blurs, a big clock shows the date and uptime, and a pill of actions
pours out under it. Log out, reboot and shut down must be held until a ring fills.

**Settings** is a normal window (`Bar Settings`): bar, system, media, alerts and colours.

## Layout of the repo

```
CRAFT.md                    the rules the bar is built to (windows, motion, layout, efficiency)
bar/                        the Quickshell config (run with `qs -c bar`)
  shell.qml                 entry point
  islands/                  the island bar: IslandBar (one per screen), Island, Card, Look
                            (colours, type, geometry and motion tokens), *State singletons
  islands/panels/           one file per card
  Settings.qml              every setting and its default, saved to ~/.config/quickshell-bar
  Theme.qml                 colours, read live from HyDE's wallbash output
  Notifications.qml, PowerMenu.qml, SettingsPanel.qml, Lyrics.qml, Player.qml, Visualizer.qml, ...
  shaders/                  GLSL effects + their compiled .qsb (rebuild with build.sh)
  scripts/                  cava config, kick detector, lyrics, earbud battery, Google Calendar
  Bar.qml, modules/         the v1 pill bar, kept on disk but unused
hypr/beatglow/              Hyprland plugin: the beat wave on the window border
polkit/                     rule that lets the polkit prompt skip a stuck fingerprint wait
systemd/                    user units: the bar, and live reload on edits
```

## Requirements

Arch package names. Tested on Hyprland 0.57 (Lua config), Quickshell 0.3.2, Qt 6.11.

| Needed for | Packages |
|---|---|
| the shell | `quickshell`, `qt6-declarative`, `ttf-jetbrains-mono-nerd`, `adwaita-fonts` |
| audio, media, battery | `pipewire`, `wireplumber` (`wpctl`, `pw-cat`), any MPRIS player, `upower` |
| music light and kicks | `cava`, `python` |
| lyrics, earbud battery | `python` (standard library only) |
| Wi-Fi | `networkmanager` (`nmcli`), `nm-connection-editor` |
| Bluetooth | `bluez`, `blueman` (its applet is the pairing agent that answers PIN prompts) |
| brightness | `brightnessctl` |
| calendar events | `uv` (runs `scripts/gcal.py` with its own deps) |
| clipboard | `wl-clipboard` |
| fingerprint in the polkit prompt | `fprintd` (optional) |
| lock / logout / night light | HyDE's `hyde-shell`, `hyprsunset` |
| phone tile | `kdeconnect` |
| building the plugin | `hyprland` headers, `pkgconf`, a C++23 compiler |
| rebuilding shaders | `qt6-shadertools` (`qsb`) |

Without HyDE the bar falls back to the colours in `Theme.qml`. With it, theme switches
recolour everything live.

## Install

Clone it and symlink the pieces into place, so edits in the clone apply live. The live-reload
unit runs its script from `~/dev/quickshell`; clone it there, or change `ExecStart` in
`systemd/quickshell-bar-reload.service`.

```sh
git clone https://github.com/sravan1946/quickshell-dots ~/dev/quickshell
cd ~/dev/quickshell

ln -s "$PWD" ~/.config/quickshell                    # qs looks for ~/.config/quickshell/bar
mkdir -p ~/.config/systemd/user ~/.config/hypr/plugins
ln -s "$PWD"/systemd/quickshell-bar{,-reload}.service "$PWD"/systemd/quickshell-bar-reload.path ~/.config/systemd/user/
ln -s "$PWD/hypr/beatglow" ~/.config/hypr/plugins/beatglow
systemctl --user daemon-reload
systemctl --user enable --now quickshell-bar-reload.path   # reload the bar when files change

make -C hypr/beatglow                                # optional: the window-border wave
```

The bar owns the notification service and the polkit agent, and only one program can hold
each. So stop dunst/swaync, Waybar and any other polkit agent (hyprpolkitagent,
polkit-gnome, ...).

### Hyprland config (Lua)

With HyDE, override its launchers in `~/.config/hypr/hyprland.lua`:

```lua
hyde.config.start.bar = "systemctl --user start quickshell-bar.service"
hyde.config.start.notifications = ""   -- the bar owns org.freedesktop.Notifications
hyde.config.start.auth_dialogue = ""   -- the bar is the polkit agent

hl.plugin.load(os.getenv("HOME") .. "/.config/hypr/plugins/beatglow/beatglow.so")

-- blur behind the islands and their cards; no layer animation (the bar animates itself)
hl.layer_rule({
	name = "islands_blur",
	match = { namespace = "^islands$" },
	blur = true,
	ignore_alpha = 0.4,
	no_anim = true,
})

hl.bind("ALT + Control_R", hl.dsp.exec_cmd("qs -c bar ipc call bar toggle"))
hl.bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd("qs -c bar ipc call power toggle"))

hl.window_rule({
	name = "bar_settings_float",
	match = { class = "^org\\.quickshell$", title = "^Bar Settings$" },
	float = true,
	center = true,
	size = "620 540",
})
```

Without HyDE, start it from the startup hook:

```lua
hl.on("hyprland.start", function()
	hl.exec_cmd("systemctl --user start quickshell-bar.service")
end)
```

The plugin is built against one exact Hyprland version and refuses to load against any
other. After a Hyprland update, quick settings shows a **Rebuild** button, or run
`make -C hypr/beatglow load`, which rebuilds it and swaps it into the running Hyprland. The bar
works without the plugin; you only lose the border wave.

### Fingerprint in the polkit prompt (optional)

Put `pam_fprintd` in front of polkit's PAM stack only, so `sudo` and login stay on the
password. Create `/etc/pam.d/polkit-1`, which overrides `/usr/lib/pam.d/polkit-1`:

```
#%PAM-1.0
auth       sufficient   pam_fprintd.so max-tries=2 timeout=15
auth       include      system-auth
account    include      system-auth
password   include      system-auth
session    include      system-auth
```

PAM can't ask for the password until `pam_fprintd` gives up. For the prompt's
**Use password** and type-to-skip to work, you must be able to kill `fprintd` without being
asked. Change the user name in the rule, then install it:

```sh
sudo install -m 644 polkit/49-fprintd-skip.rules /etc/polkit-1/rules.d/
```

The rule allows only killing `fprintd.service`, and only from your active local session.

### Google Calendar (optional)

The calendar reads your calendar's **secret iCal address** (Google Calendar → Settings → your
calendar → *Secret address in iCal format*). It never uses OAuth and never writes to the
calendar. Keep the address out of the repo:

```sh
mkdir -p ~/.local/share/quickshell-bar
echo 'https://calendar.google.com/calendar/ical/…/basic.ics' > ~/.local/share/quickshell-bar/gcal-ics.url
chmod 600 ~/.local/share/quickshell-bar/gcal-ics.url
```

## Usage

| | |
|---|---|
| restart the bar | `systemctl --user restart quickshell-bar` |
| logs | `qs log -c bar -f` |
| hide / show the bar | `qs -c bar ipc call bar toggle` |
| open a card | `qs -c bar ipc call islands open media` (`... islands keys` lists them; with several monitors the target is `islands-<output>`) |
| close the card | `qs -c bar ipc call islands close` |
| quick settings | `qs -c bar ipc call quick toggle` |
| power menu | `qs -c bar ipc call power toggle` |
| settings | `qs -c bar ipc call settings toggle`, or `... settings page media` to open on a page |
| change a setting | `qs -c bar ipc call settings set notifDrop false` (any key in `Settings.qml`, value as JSON) |
| do not disturb | `qs -c bar ipc call notifications toggleDnd` |
| look at the polkit prompt | `qs -c bar ipc call auth preview finger` (`pass`, `error`, `ok`; `""` closes it) |
| slow all motion down | `qs -c bar ipc call islands slow 4` (`1` is normal) |

If a broken config makes the bar exit five times within a minute, systemd stops restarting
it. Once the config is fixed, run
`systemctl --user reset-failed quickshell-bar && systemctl --user start quickshell-bar`.

## Customising

- **Look and motion:** `bar/islands/Look.qml` holds every colour, size, curve and duration
  the island bar uses. `CRAFT.md` explains why the rules are what they are.
- **Settings:** the Settings window, or `~/.config/quickshell-bar/settings.json`.
- **Shaders:** Qt only loads precompiled shaders. After editing a `.frag`, run
  `bar/shaders/build.sh`. Qt caches shaders by URL across reloads, so the script also stamps
  each shader's `?v=` in the QML with the new build's hash.
- **Reload:** saving a file reloads the bar through `quickshell-bar-reload.path`
  (Quickshell's own watcher misses rename-style saves). A newly added inline component needs
  a full restart, and the reload script does that for you.
