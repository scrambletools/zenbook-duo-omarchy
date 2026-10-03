# ASUS Zenbook Duo (UX8407AA) on Omarchy — hardware setup guide

Everything needed to make a 2026 Zenbook Duo UX8407AA fully work under
[Omarchy](https://omarchy.org) (Arch + Hyprland) on Omarchy's kernel,
`linux-omarchy` 7.2.5. Every config and script referenced here ships in this
directory.

> **Always power on with the keyboard lifted off the laptop**, and dock it at
> the disk-unlock prompt. The bottom screen only works if the firmware lit it
> at power-on. If it stays black after undocking, the keyboard freezes for
> ten seconds after each dock, or shutdown hangs for a minute: shut down,
> unplug the charger, hold the power button for 15 seconds, wait a minute,
> and power on with the keyboard off. A reboot or quick power-off keeps the
> bad state. Details in section 7.

## Features

In order of how much you'd miss them:

| # | Feature | Without it |
|---|---|---|
| 2 | Sound | no sound card at all ("Dummy Output") |
| 3 | Displays: upright top screen, stacked layout, correct mouse pointer, bar on the top screen only | top screen upside down; pointer mirrored; a second bar on the bottom screen |
| 4 | Screen brightness, on both screens | brightness keys and slider change nothing |
| 5 | Reliable boot | some boots hang with a dark top screen after login |
| 6 | Touchscreens, each mapped to its own screen | top touchscreen dead, kernel oops, shutdown hangs |
| 7 | Bottom screen turns off when the keyboard is docked | bottom screen stays on under the keyboard |
| 8 | Keyboard function keys and keyboard backlight | volume, brightness, backlight and mic-mute keys do nothing |
| 9 | Detached keyboard over Bluetooth | keyboard won't pair or reconnect |
| 10 | On-screen keyboard and touchpad on the bottom screen | no keyboard when the physical one isn't with you |
| 11 | Auto-rotation, and sharing mode when opened flat | screens never turn |
| 12 | Auto-brightness from the light sensor | brightness ignores the room light |

## 1. Install

```sh
bash setup.sh
```

Run it as your normal user; root steps go through `pkexec`. It installs:

- the kernel parameters (`boot/`) and rebuilds the boot image
- the audio overlay (`audio/`), built with DKMS for the running kernel
- the touchscreen driver blacklist (`touchscreen/`)
- the keyboard helper, Fn-key daemon and udev rule (`scripts/`, `udev/`)
- ASUS's sensor-hub firmware, downloaded from ASUS and checked against
  pinned checksums (section 11)
- the helper scripts, into `~/.config/zenbook/`
- Omarchy hooks for the bar (section 3), a kernel check after updates and a
  health check after boot (below)
- the on-screen keyboard and its bar button, built from `keyboard/` if
  `cargo` is installed (section 10)
- four Hyprland blocks from `hypr/`, in `~/.config/hypr/monitors.lua`,
  `input.lua`, `autostart.lua` and `bindings.lua`, between
  `-- >>> zenbook-duo-omarchy >>>` marker comments. It asks before touching
  each file: a missing block is appended, and a block that differs from the
  one in `hypr/` is shown as a diff and replaced, so re-running setup.sh
  after an update brings them up to date. Settings merged by hand without
  the markers are left alone, with a note if they look older than `hypr/`.

Then power off and power on with the keyboard lifted off. Section 14 lists
checks for every feature.

**After updates and at boot,** two Omarchy hooks (installed by setup.sh)
watch for the things that have actually broken on this machine:

- **After `omarchy update`** (post-update hook `zenbook-duo-kernel-check`):
  for each newly installed kernel, before you reboot into it, it checks that
  the audio overlay built for it (retrying once) and warns, in the update
  output and with a notification, if sound would be missing on it. It notes
  when a new kernel's `hid-asus` knows the keyboard itself, and once every
  installed kernel has the upstream audio fix (Linux 7.3) it offers to remove
  the overlay. Kernels it has checked are remembered in
  `~/.local/state/zenbook/kernels-checked`, so an update without a new kernel
  prints just "no new kernel". It runs in the update's terminal and only asks
  a question when there is something to remove (`omarchy update -y` never
  asks and changes nothing).
- **After boot** (post-boot hook `zenbook-duo-health`): in the background, it
  waits for the sound card, the keyboard on `hid-asus` (when connected) and
  the accelerometer, and sends a notification for any that don't come up.
  Silent when all is well.

Both live in `~/.config/omarchy/hooks/` alongside the bar's hook (section 3).

## 2. Sound

The firmware advertises a **ghost Realtek RT722 codec** on SoundWire link 3
that isn't fitted, next to the real Cirrus CS42L43. The generic `sof_sdw`
machine driver builds an audio link for both, hits a duplicate
`SDW3-Playback-SimpleJack`, and aborts with error -12, so **no sound card
registers** and PipeWire shows only "Dummy Output".

`audio/` is a DKMS overlay that rebuilds `snd-soc-sof-sdw` with a narrow
filter: it drops only a device with the RT722's ID (mfg `0x025d`, part
`0x0722`) that the SoundWire core has marked unattached, and only on this
board (DMI-matched to `UX8407AA`). It is adapted from
[burakgon/asus-expertbook-linux](https://github.com/burakgon/asus-expertbook-linux),
which fixes the same bug on the ExpertBook B9406CAA.

The overlay is a patched copy of the kernel's own `sof_sdw.c`, so each
version builds only against the kernel it was made from:

| Version | Kernel |
|---|---|
| `zenbook-duo-sof-sdw-3.1.0/` | Omarchy `linux-omarchy` 7.2.5 (v7.2.5 `sof_sdw.c` plus the sof_sdw parts of Omarchy's sound patches `0510`–`0514` in [omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs)) |
| `zenbook-duo-sof-sdw-3.0.0/` | stock Arch `linux` |

`audio/install-audio-fix.sh` (run by setup.sh) picks the version for the
running kernel, builds it with DKMS and regenerates the initramfs. After a
kernel update, `dkms status` must list a `zenbook-duo-sof-sdw` version for
the new kernel; if it doesn't, or sound is back to "Dummy Output", the
overlay needs porting to that kernel's `sof_sdw.c`.

**Temporary:** the real fix, a `ghost_realtek` DMI quirk for `UX8407AA` in
`drivers/soundwire/dmi-quirks.c` (commit `ca02ffd4975c`), ships in Linux
7.3. The install script refuses to run on a kernel that has it. Remove the
overlay once you are on 7.3:

```sh
sudo dkms remove -m zenbook-duo-sof-sdw -v 3.0.0 --all
sudo dkms remove -m zenbook-duo-sof-sdw -v 3.1.0 --all
sudo rm -rf /usr/src/zenbook-duo-sof-sdw-3.*
sudo limine-mkinitcpio
```

Everything else audio needs is already in Arch: `alsa-ucm-conf` ≥ 1.2.16 has
the UCM profile and `linux-firmware` has the CS35L56 amp tuning.

## 3. Displays

Both panels are 2880×1800 OLEDs. The top panel (`eDP-1`) is mounted upside
down, and the kernel has no orientation quirk for this model yet.

**Orientation.** `boot/zenbook-duo-panel-orientation.conf` adds the kernel
parameter `video=eDP-1:panel_orientation=upside_down`. The kernel then marks
the connector as rotated, and the boot splash, text console and Hyprland all
turn the picture themselves, so `eDP-1` needs **no** `transform` in
Hyprland. Don't also set `transform = 2`: the panel would be turned twice.
The parameter becomes redundant (harmless) once the kernel's
`drm_panel_orientation_quirks.c` lists the UX8407AA.

**Layout.** `hypr/monitors.lua` places the bottom panel (`eDP-2`) directly
below the top one: `eDP-1` at `0x0`, `eDP-2` at `0x900` (the panel height at
scale 2). The same block holds the rotated layouts (section 11).

**Mouse pointer.** Hyprland places the hardware cursor in the panel's
unrotated coordinates, so on the top screen the pointer moves mirrored.
`hypr/input.lua` draws the cursor in software (`cursor:no_hardware_cursors`),
which rotates with the picture. Drop it once Hyprland rotates the cursor
plane itself.

**Bar on the top screen only.** Omarchy's bar puts a panel on every screen,
and the bottom screen doesn't need one. Until Omarchy has a setting for it
([PR #6501](https://github.com/omacom/omarchy/pull/6501), `bar.screens`),
`scripts/zenbook-duo-bar` clones the built-in bar (`omarchy plugin clone
omarchy.bar`, which becomes "My Bar") and filters its per-screen panels to
every screen except `eDP-2`, so an external monitor still gets a bar.
setup.sh installs it as an Omarchy **post-update hook**: during every
`omarchy update` it asks whether to rebuild the clone from the freshly
updated bar, so the bar keeps getting Omarchy's changes (`omarchy update -y`
rebuilds without asking). Like Omarchy's own update prompt, the question is
erased from the terminal once answered. If the bar's code has changed so the filter no longer
applies, it switches back to the standard bar and shows a notification. Run
`~/.config/omarchy/hooks/post-update.d/zenbook-duo-bar remove` to go back to
the standard bar by hand. Updates that bypass `omarchy update` (a plain
`pacman -Syu`) don't trigger the hook, so the clone waits for the next
`omarchy update`.

## 4. Brightness

**OLED brightness.** The panels set brightness through commands over the
display link (VESA DPCD), but the firmware tells the Intel driver they use a
PWM line. By default the driver trusts the firmware and drives a PWM that
goes nowhere: `brightnessctl` reports success and the picture never changes.
`boot/zenbook-duo-dpcd-backlight.conf` adds `xe.enable_dpcd_backlight=1`,
which makes the driver use the panels' own brightness control. (Ignore the
`asus_screenpad` backlight device; it drives neither panel on this model.)

**Bottom screen follows the top.** The brightness keys, the Omarchy slider
and auto-brightness only drive the top panel (`intel_backlight`). The bottom
panel has its own backlight (`card0-eDP-2-backlight`) that nothing else
touches. `scripts/zenbook-duo-brightness-sync` watches the top backlight and
copies its level to the bottom one.

## 5. Reliable boot (Panel Replay off)

Without this, on some boots the top screen goes dark seconds after login and
nothing responds. Both panels support **eDP Panel Replay**, which the Intel
driver enables on `eDP-1` by default; when the panel fails to report idle at
boot, the first display changes after login lock up its display pipeline.
The kernel log then opens with hundreds of

```
xe … *ERROR* Timed out waiting for PSR Idle for re-enable
```

followed by `flip_done timed out` on pipe A. `boot/zenbook-duo-panel-replay.conf`
adds `xe.enable_panel_replay=0`, at the cost of a little idle power on the
top panel.

## 6. Touchscreens

**Driver.** The top touchscreen (ACPI `RAYD0001`) is a standard HID-over-I2C
device, but the kernel's `raydium_i2c_ts` driver claims it first, misreads
it, and oopses on the first touch. The crashed interrupt thread also hangs
shutdown and reboot at the goodbye splash. `touchscreen/zenbook-duo-touchscreen.conf`
blacklists `raydium_i2c_ts` in `/etc/modprobe.d/`; `i2c-hid-acpi` then
drives both touchscreens and their pens. Drop the blacklist once the kernel
fixes that driver.

**Mapping.** Two identical touchscreens confuse Hyprland's automatic
mapping. `hypr/input.lua` binds each touchscreen and pen to its own panel
(`rayd0001` to `eDP-1`, `rayd0002` to `eDP-2`), and rotates touch input
along with its panel (section 11).

## 7. Docking the keyboard

The keyboard covers the bottom screen when docked, so the screen should go
off, and come back when you lift the keyboard away.
`scripts/zenbook-duo-screen-watch` (started from `autostart.lua`) does that:

- It detects the keyboard by its USB ID (`0b05:1cd7`) and ignores contact
  bounce from the pogo pins.
- It turns the bottom panel off through a rule file in Omarchy's toggles
  directory (`~/.local/state/omarchy/toggles/hypr/`), the same mechanism
  Omarchy's clamshell mode uses, so the setting survives every Hyprland
  reload.
- It leaves the panel alone during shutdown, and runs as a single instance.

**The power-on rule.** The Intel driver can't bring the bottom panel's
display hardware (PHY B) up from scratch; it only works if the firmware
already lit the panel at power-on, and the firmware does that only when the
keyboard is off. If the bottom screen fails to come back, every later
display change involving it freezes the machine for ten seconds, and the bad
state survives reboots and quick power-offs. So:

1. Power on with the keyboard lifted off; dock it at the disk-unlock prompt.
2. Don't dock or undock while shutting down or rebooting.
3. If the bottom screen fails to come back: shut down, unplug the charger,
   hold the power button for 15 seconds, wait a minute, and power on with
   the keyboard off. (Firmware "load setup defaults" also clears it.)

The kernel log shows `PHY B failed to request refclk` and `Failed to bring
PHY B to idle` when this happens. The screen watcher spots that, keeps the
panel off for the rest of the boot (so docking doesn't freeze the machine
every time), and shows a notification with the steps above. Reported upstream as
[drm/xe issue 9196](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196);
the report and kernel logs are in `reference/xe-bug-report/`.

## 8. Keyboard function keys and backlight

| Key | Does |
|---|---|
| F1 / F2 / F3 | mute / volume down / volume up |
| F4 | cycle the keyboard backlight (off, low, mid, high) |
| F5 / F6 | screen brightness down / up |
| F10 | mic mute |
| Super + F5 | auto-brightness back to its default curve (section 12) |
| Super + Ctrl + K | on-screen keyboard and touchpad (section 10) |

The keyboard (USB `0b05:1cd7` docked, Bluetooth `0b05:1cd8` detached) isn't
in the kernel's `hid-asus` driver yet, so out of the box it lands on the
generic HID driver, and its special keys send plain F-keys. Two pieces fix
that:

1. **`scripts/zenbook-duo-hid-asus` + `udev/61-zenbook-duo-keyboard.rules`.**
   When the keyboard's vendor interface (the one declaring usage page
   `0xFF31`) appears on the generic driver, the rule runs the helper, which
   registers the keyboard with `hid-asus`, including its keyboard-backlight
   flag, and hands the interface over. The keyboard then sends proper volume
   codes and ASUS hotkey reports, and `hid-asus` provides the
   `asus::kbd_backlight` light device that Omarchy's keyboard-backlight keys
   drive. The rule also catches a keyboard docked at power-on: it was set up
   for the disk-unlock prompt before the rule existed, so it is handled when
   systemd replays existing devices after boot. Side effect: the keyboard
   shows up as "Asus Keyboard".
2. **`scripts/zenbook-duo-fnkeys` + `udev/zenbook-duo-fnkeys.service`.**
   `hid-asus` receives this keyboard's hotkey reports (report `0x5a`: `0x10`
   / `0x20` screen brightness, `0xc7` keyboard backlight, `0x7c` mic mute)
   but can't map them, because the keyboard describes them differently from
   the models the driver knows. This root daemon reads them and injects the
   matching keys, so Omarchy's own key bindings handle them. It follows the
   keyboard through docking, undocking and Bluetooth, and logs unknown
   codes (`journalctl -u zenbook-duo-fnkeys`) so new keys are easy to add.

The proper fix is a kernel patch: the IDs in `hid-asus`'s device table with
`QUIRK_USE_KBD_BACKLIGHT`, plus a report-descriptor fix for the `0x5a`
report. Then `hid-asus` maps everything itself and both pieces can go.

To diagnose: read the keyboard's `/dev/hidraw*` nodes while pressing keys.
`5a 20 00 …` on the vendor interface means the hotkeys work; plain F-key
codes (`0x3a`–`0x45`) on the keyboard interface mean `hid-asus` doesn't
have the keyboard.

## 9. Bluetooth keyboard

Lifted off the laptop, the keyboard is a Bluetooth keyboard; docked, its
radio is off.

**Pair from the laptop, not the keyboard.** Omarchy's pairing agent
(`bt-agent`) can't answer when a *device* starts pairing, so it rejects it,
and the keyboard connects and drops every few seconds (`Authorize this
device pairing (yes/no)?` in `journalctl --user -b`). Pairing started from
the laptop works. This applies to any Bluetooth LE device:

```sh
bluetoothctl scan le &
bluetoothctl pair    XX:XX:XX:XX:XX:XX
bluetoothctl trust   XX:XX:XX:XX:XX:XX
bluetoothctl connect XX:XX:XX:XX:XX:XX
```

**Re-pairing the keyboard.** Each time the keyboard enters pairing mode
(hold its Bluetooth key about 3 s), it takes a **new Bluetooth address**.
The laptop's existing pairing then points at an address the keyboard no
longer uses, and the new address is a stranger that is never reconnected
automatically. Since the keyboard can't type while undocked and unpaired,
start the helper first, then undock and hold the key:

```sh
~/.config/zenbook/zenbook-duo-keyboard-pair     # waits up to 5 minutes
```

It pairs, trusts and connects whatever appears under the keyboard's name,
and removes the stale entries. To just *reconnect* a paired keyboard, press
any key; don't hold the Bluetooth key.

## 10. On-screen keyboard and touchpad

With the physical keyboard lifted off, the bottom screen can show a copy of
the detachable keyboard and its touchpad, like ASUS's Windows virtual
keyboard. Key positions are measured from a photo of the real keyboard, so
the layout, the half-height F-row and the arrow cluster match it.

**Opening and closing.** Tap the keyboard button in the Omarchy bar, or
press **Super + Ctrl + K**; do the same, or tap the keyboard icon left of
DEL/INS, to close it. The bar button only appears while the physical
keyboard is undocked (the bottom screen is on), and lights up while the
on-screen keyboard is showing.

**Typing.** Taps type into the window that had focus. Keys fire on touch,
and held keys repeat after half a second (letters, Backspace, arrows, Enter,
F-row). Shift, Ctrl, Alt and Super latch for the next key (tap again to
unlatch); Caps toggles; Fn latches the F-row to F1–F12 and the arrows to
Home / Page Up / Page Down / End. Otherwise the F-row sends the media
functions, as on the physical keyboard. The two keys left of DEL/INS close
the keyboard and swap the two screens' workspaces.

**Touchpad.** One finger moves the pointer, a tap clicks, a two-finger tap
right-clicks, and a two-finger slide scrolls.

**While it is up, the bottom screen is all keyboard:**

- The cursor stays on the top screen. The touchpad's pointer is bound to the
  top screen, and `hypr/monitors.lua` leaves a 100-pixel gap between the
  screens in the layout, so the cursor reaches the top screen's last row
  without its image spilling onto the bottom screen, and no mouse can move it
  there.
- Workspaces stay on the top screen. The bottom screen's workspaces move up,
  and it shows an empty named workspace that no number key reaches, so
  nothing opens unseen under the keyboard.
- Closing the keyboard undoes both: the screens line up again and the bottom
  screen shows workspace 2, which `monitors.lua` binds to it whenever the
  keyboard is down.
- `hypr/input.lua` turns off Hyprland's `cursor:hide_on_touch`, which would
  otherwise hide the cursor on every touch of the touchpad (and so also when
  you tap a touchscreen elsewhere).

**How it is built.**

| Piece | Does |
|---|---|
| `keyboard/` | The keyboard itself: a small Rust program (iced, CPU renderer, about 4 MB) drawn on a Wayland layer-shell surface, which takes touch but never keyboard focus. Keys go out through one persistent virtual keyboard with a standard US keymap, each on its real key code with Shift held for shifted characters, so Hyprland's key bindings see the same keys apps do. The touchpad is a virtual pointer. No root access. |
| `scripts/zenbook-duo-osk` | `toggle` / `open` / `close`: what the bar button, Super + Ctrl + K and the close key run. On start the keyboard records its pid and runs the script's `park` step itself (gap on, workspaces moved up), so it behaves the same however it is launched. |
| `omarchy-plugin/` | The bar button, an Omarchy shell plugin. |
| `hypr/` blocks | Super + Ctrl + K (`bindings.lua`), the gap and the workspace-2 rule (`monitors.lua`), `hide_on_touch` (`input.lua`). |

setup.sh builds `keyboard/` with `cargo` (install Rust with `pacman -S rust`,
or `mise use -g rust@stable`; `keyboard/mise.toml` pins stable for mise
users), installs it to `~/.config/zenbook/zenbook-duo-keyboard`, links the
plugin into `~/.config/omarchy/plugins/`, adds it to the bar and restarts
the Omarchy shell.

**Limits and troubleshooting.**

- It types with a US layout whatever your keyboard layout setting is.
- It only shows while the bottom screen is on, so with the keyboard undocked.
- If the layout or workspaces don't come back after closing it, the trace of
  the last open or close is in `$XDG_RUNTIME_DIR/zenbook-duo-osk.log`, and
  `~/.config/zenbook/zenbook-duo-osk close` restores them.
- After editing the bar button, run `omarchy restart shell`: a running shell
  can keep the old version.

## 11. Auto-rotation and sharing mode

Turn the laptop on its side and both screens rotate into a side-by-side
book layout; turn it upside down and they swap. Lay it opened flat on a
table and the top screen turns around for the person opposite.

**Sensor firmware.** The accelerometer, light sensor and hinge sensor sit
behind Intel's sensor hub, which won't start with the generic firmware in
`linux-firmware` (`ISH loader: cmd 2 failed 10` in the kernel log); ASUS's
signed firmware isn't in `linux-firmware`. It can't be redistributed, so
`scripts/zenbook-duo-sensor-firmware` (run by setup.sh) downloads ASUS's
Windows sensor driver from ASUS, checks it against pinned SHA-256 sums,
extracts the firmware, and installs it as
`/usr/lib/firmware/updates/intel/ish/ish_ptl_<crc32(vendor)>_<crc32(product)>.bin`,
the board-specific name the kernel looks for first. Delete that file and
reboot to undo it.

**Rotation.** `iio-sensor-proxy` turns the accelerometer into `normal`,
`left-up`, `right-up` or `bottom-up`. `scripts/zenbook-duo-rotate-watch`
(started from `autostart.lua`) waits until a reading has held for a second,
writes the layout to `~/.local/state/zenbook/rotation` and reloads Hyprland.
`hypr/monitors.lua` reads that file and sets each panel's rotation and
position; `hypr/input.lua` rotates each touchscreen to match, since
Hyprland doesn't rotate touch input with the display. Because the layout
lives in the config, it survives every reload, including the dock
watcher's. After a turn, the watcher keeps workspace order: the left screen
(side by side) or the upper one (stacked) shows the lower-numbered
workspace.

**Sharing mode.** The hinge sensor reports the opening angle and the base's
tilt from level. Sharing mode starts when the hinge is open at least 170°
**and** the base is within 15° of level, and ends below 160° or above 25°.
Opened flat but tilted up (on the kickstand or in your hands) stays normal
use. Typical readings:

| Pose | Hinge | Base tilt |
|---|---|---|
| Laptop | 107–118° | 2–3° |
| Opened flat, lying on the table | 177° | 1–2° |
| Opened flat, tilted up | 177° | 45–55° |

To hold the current layout, create `~/.local/state/zenbook/rotation-lock`;
delete it to resume.

## 12. Auto-brightness

`scripts/zenbook-duo-auto-brightness` (started from `autostart.lua`) sets
screen brightness from the ambient light sensor (same firmware as section
11, read through `iio-sensor-proxy`); the brightness mirror (section 4)
carries it to the bottom screen.

- **Curve:** about 8% in the dark, plus 22 points for every tenfold increase
  in light (~30% at 10 lux, ~52% at 100 lux, ~74% at 1000 lux).
- **Smooth:** readings are smoothed, changes under 4 points are ignored, and
  new levels fade in over about a second.
- **Your adjustments stick.** When you change brightness with the keys or
  the slider, the difference from the curve is saved
  (`~/.local/state/zenbook/auto-brightness-offset`) and kept as the light
  changes. On first start it adopts the current brightness.
- **Back to the default curve:** **Super + F5**, or
  `~/.config/zenbook/zenbook-duo-auto-brightness reset`.
- **Pause:** create `~/.local/state/zenbook/auto-brightness-off`; delete it
  to resume.

## 13. Kernel command line

Drop-ins in `/etc/limine-entry-tool.d/`, installed by setup.sh:

| Parameter | Section |
|---|---|
| `video=eDP-1:panel_orientation=upside_down` | 3 (required by `hypr/monitors.lua`) |
| `xe.enable_dpcd_backlight=1` | 4 |
| `xe.enable_panel_replay=0` | 5 |

Panel Self Refresh (PSR) needs no parameter; leave it at the driver
default. On other bootloaders, add the same parameters to the kernel command
line some other way.

## 14. Verification

After `setup.sh` and powering on with the keyboard off:

```sh
wpctl status                        # real Speaker/Headphone sinks, not Dummy Output
dkms status | grep zenbook          # an overlay version for the running kernel
grep -oE 'panel_orientation=[a-z_]+|enable_dpcd_backlight=[0-9]|enable_panel_replay=[0-9]' /proc/cmdline
hyprctl monitors                    # eDP-1 at 0x0, upright; eDP-2 at 0x900
hyprctl devices | grep rayd         # both touchscreens
ls /sys/class/leds | grep kbd_backlight      # asus::kbd_backlight
systemctl is-active zenbook-duo-fnkeys       # active
bluetoothctl devices Paired | grep 'Zenbook Duo Keyboard'   # exactly one
journalctl -k -b | grep 'ISH loader'         # "firmware loaded"
cat /sys/bus/iio/devices/*/name     # includes accel_3d, als and hinge
cat ~/.local/state/zenbook/rotation # current layout
omarchy plugin list | grep -E '^\S+\.bar '  # your user.bar ("My Bar") enabled, omarchy.bar disabled
ls ~/.config/omarchy/hooks/*.d/ | grep zenbook   # zenbook-duo-bar, -kernel-check (post-update), -health (post-boot)
```

Then:

- Play something: sound comes from the speakers.
- F5 / F6 change brightness on both screens.
- Touch each screen: the cursor reacts on the screen you touched.
- Dock the keyboard: the bottom screen turns off within about 2 s, and comes
  back a few seconds after you lift the keyboard away, with no bar on it.
- Volume, mute, keyboard backlight and mic-mute keys work, docked and over
  Bluetooth.
- Lifted off, the keyboard types over Bluetooth within a few seconds (if
  not, section 9).
- Super + Ctrl + K with the keyboard lifted off: the bottom screen shows the
  on-screen keyboard; taps type into the focused window and the touchpad
  moves the pointer.
- Turn the laptop onto each side: both screens rotate, workspace 1 stays on
  the left, and touch lands where you touch.
- Lay it opened flat on the table: the top screen turns around; tilt it up
  and it turns back.
- Cover the light sensor near the webcam: the screens fade darker.
- Shutdown and reboot finish without hanging at the splash.

## License

MIT (see `LICENSE`). The exception is `audio/zenbook-duo-sof-sdw-*/`, a
modified copy of a GPL-2.0 Linux kernel module, which stays under that
license; see its sources for attribution.
