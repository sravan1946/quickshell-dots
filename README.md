# quickshell-dots

A [Quickshell](https://quickshell.org) desktop shell for Hyprland, built as a Waybar
replacement on top of [HyDE](https://github.com/HyDE-Project/HyDE). It covers the bar, the
notification daemon, the OSD and the quick-settings panel, plus a small Hyprland plugin that
carries the bar's beat wave onto the focused window's border.

## What's in it

```
bar/                        the Quickshell config (run with `qs -c bar`)
  shell.qml                 entry point: bar, quick settings, OSD, notifications, now playing
  Config.qml                bar layout: which modules go in which pill
  Theme.qml                 colours, read live from HyDE's wallbash output
  modules/                  one file per bar module (Workspaces, Media, Clock, Network, …)
  components/               shared pieces (pills, dropdowns, Wi-Fi / Bluetooth lists, …)
  shaders/                  GLSL effects + their compiled .qsb (rebuild with build.sh)
  scripts/                  cava config, Google Calendar fetcher
hypr/beatglow/              Hyprland plugin: the beat wave on the window border
systemd/                    user unit that runs the bar
```

**Bar.** Workspaces, media pill with a live spectrum, clock with a calendar and Google
Calendar events, DND, idle inhibitor, network rates with a sparkline (click for the Wi-Fi
panel), privacy indicators, tray, battery, taskbar, brightness and volume.

**Now Playing.** Rest the pointer on the media pill. A vinyl record spins inside a radial
spectrum ring, throws sparks on each kick, and is tinted from the cover art. Click the record
to play/pause, scroll it to seek.

**Quick settings.** Rest the pointer on the right screen edge, just below the bar, and the
panel pours out of that point. It holds only what the bar's pills don't: settings, lock and
power buttons, night light (HyDE's hyprsunset), airplane mode, mic, your phone through KDE
Connect (battery, tap to ring), output and input device pickers, a mic slider and a per-app volume mixer.

**Power menu.** Replaces wlogout: the screen blurs, a big clock shows the date and uptime, and a
pill of actions pours out under it. Lock and Suspend run at once; Log out, Reboot and Shut down
have to be held (mouse, Enter or their letter) until a ring fills, so a stray press can't end
the session.

**Beat effects.** cava feeds a beat detector. Each kick flashes the pills, runs a wave
along the bar and, with the plugin loaded, around the focused window's border.

**Notifications.** A popup notification daemon with history and actions, plus
do-not-disturb (which holds notifications and shows them when turned off). It replaces
dunst/swaync.

**OSD.** Shows volume, mic and brightness changes on the focused monitor, whatever caused
them.

## Requirements

Arch package names; tested on Hyprland 0.56 (Lua config), Quickshell 0.3.1, Qt 6.11.

| Needed for | Packages |
|---|---|
| the shell | `quickshell`, `qt6-declarative`, `ttf-jetbrains-mono-nerd` |
| audio, media, battery | `pipewire`, `wireplumber`, any MPRIS player, `upower` |
| spectrum and beat effects | `cava` |
| Wi-Fi | `networkmanager` (`nmcli`), `nm-connection-editor` |
| Bluetooth | `bluez`, `blueman` (its applet is the pairing agent that answers PIN prompts) |
| brightness | `brightnessctl` |
| calendar events | `uv` (runs `scripts/gcal.py` with its own deps) |
| clipboard copy | `wl-clipboard` |
| lock / logout / night light, mixer | HyDE's `hyde-shell`, `hyprsunset`, `pavucontrol` |
| phone tile | `kdeconnect` |
| building the plugin | `hyprland` headers, `pkgconf`, a C++23 compiler |
| rebuilding shaders | `qt6-shadertools` (`qsb`) |

Without HyDE the bar falls back to the Tokyo Night colours in `Theme.qml`; with it, theme
switches recolour everything live. Lock, logout and night light call `hyde-shell`
directly.

## Install

Clone it anywhere and symlink the pieces into place. Edits in the clone then apply live.

```sh
git clone https://github.com/sravan1946/quickshell-dots ~/dev/quickshell
cd ~/dev/quickshell

ln -s "$PWD" ~/.config/quickshell                    # qs looks for ~/.config/quickshell/bar
mkdir -p ~/.config/systemd/user ~/.config/hypr/plugins
ln -s "$PWD/systemd/quickshell-bar.service" ~/.config/systemd/user/
ln -s "$PWD/hypr/beatglow" ~/.config/hypr/plugins/beatglow
systemctl --user daemon-reload

make -C hypr/beatglow                                # optional: the window-border wave
```

Only one program can own the notification service, so stop dunst/swaync and Waybar.

### Hyprland config (Lua)

Start the bar with the session and load the plugin. With HyDE, override its bar and
notification launchers in `~/.config/hypr/hyprland.lua`:

```lua
hyde.config.start.bar = "systemctl --user start quickshell-bar.service"
hyde.config.start.notifications = ""   -- the bar owns org.freedesktop.Notifications

hl.plugin.load(os.getenv("HOME") .. "/.config/hypr/plugins/beatglow/beatglow.so")

hl.bind("ALT + Control_R", hl.dsp.exec_cmd("qs -c bar ipc call bar toggle"))

-- Settings is a normal window ("Bar Settings") so it can be moved around; float it at its
-- own size, or Hyprland tiles it.
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
other. **Run `make -C hypr/beatglow` again after every Hyprland update.** The bar works
without the plugin; you only lose the border wave.

### Google Calendar (optional)

The clock's calendar reads your calendar's **secret iCal address** (Google Calendar →
Settings → your calendar → *Secret address in iCal format*). It never uses OAuth and never
writes to the calendar. Keep the address out of the repo:

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
| quick settings | `qs -c bar ipc call quick toggle`, or rest the pointer on the right edge |
| power menu | `qs -c bar ipc call power toggle` (bind it in place of HyDE's logout menu) |
| now playing | `qs -c bar ipc call media toggle`, or rest the pointer on the media pill |
| settings | `qs -c bar ipc call settings toggle`, or `... settings page media` to open on a page |
| change a setting | `qs -c bar ipc call settings set mediaStyle 2` (any key in `Settings.qml`, value as JSON) |
| do not disturb | `qs -c bar ipc call notifications toggleDnd` |

In the Bluetooth list, click a paired device to connect or disconnect it, click a new one to
pair it, and right-click a paired one to forget it.

If a broken config makes the bar exit five times within a minute, systemd stops restarting
it. Once the config is fixed: `systemctl --user reset-failed quickshell-bar && systemctl --user start quickshell-bar`.

## Customising

- **Layout:** edit the `left`, `center` and `right` pill lists in `bar/Config.qml`; module
  names are file names in `bar/modules/`.
- **Colours and font:** `bar/Theme.qml`.
- **Shaders:** Qt only loads precompiled shaders. After editing a `.frag`, run
  `bar/shaders/build.sh`, then bump the `?v=` on that shader's URL in its QML file. Qt caches
  shaders by URL across reloads.
- Saving any `.qml` file reloads the shell live.
