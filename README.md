# ASUS Zenbook Duo (UX8407AA) on Omarchy — hardware setup guide

Everything needed to make a 2026 Zenbook Duo UX8407AA fully work under
[Omarchy](https://omarchy.org) (Arch + Hyprland), collected from getting one
machine working in September–October 2026, first on Arch's `7.1.9-arch1-2`
and then on Omarchy's own kernel, `linux-omarchy` 7.2.5. Every config and
binary referenced here ships in this directory, ready to copy.

> **If the bottom screen stays black after undocking, the keyboard goes dead
> for ten seconds after each dock event, or shutdown sits on a blank screen
> for a minute:** the bottom panel's display PHY is wedged. Shut down, unplug
> the charger, hold the power button for 15 seconds, leave the machine off
> for a minute, then power on with the keyboard lifted off and dock it at the
> disk-unlock prompt. A reboot or a quick power-off carries the bad state
> forward. Details in section 2b. (A top screen that goes dark right after
> login is a different problem, section 2a.)

**Quick start:** `bash setup.sh` (it asks before appending its four blocks to
your Hyprland config, and downloads ASUS's sensor driver to extract the
sensor-hub firmware, section 1d), power off, and power on with the keyboard
lifted off (section 2b).
The sections below explain each fix so you can tell whether a newer
kernel/Omarchy has made one obsolete.

| Problem out of the box | Fix | Files |
|---|---|---|
| Top screen upside down (boot splash, console and desktop); panels not stacked | kernel panel-orientation parameter + Hyprland monitor layout | `boot/zenbook-duo-panel-orientation.conf`, `hypr/monitors.lua` |
| Bottom screen stays on under the docked keyboard | dock/undock watcher | `scripts/zenbook-duo-screen-watch`, `hypr/autostart.lua` |
| Top screen goes dark right after login and the machine hangs; kernel log starts with a burst of `PSR Idle` timeouts | Panel Replay off (section 2a) | `boot/zenbook-duo-panel-replay.conf` |
| Bottom screen never comes back after undocking; machine freezes for 10 s per dock event; shutdown hangs a minute | power on with the keyboard off the laptop (section 2b) | none |
| Brightness keys/slider change nothing on either screen | DPCD backlight kernel parameter | `boot/zenbook-duo-dpcd-backlight.conf` |
| Bottom panel brightness stuck (often near 0) | brightness mirror | `scripts/zenbook-duo-brightness-sync`, `hypr/autostart.lua` |
| Screens don't turn when the laptop is turned (no accelerometer); no sharing mode when opened flat | ASUS sensor-hub firmware + iio-sensor-proxy + rotation watcher (with hinge-sensor sharing mode) | `scripts/zenbook-duo-sensor-firmware`, `scripts/zenbook-duo-rotate-watch`, `hypr/monitors.lua`, `hypr/input.lua` |
| Screen brightness doesn't follow the room light | ambient-light auto-brightness (same sensor firmware) | `scripts/zenbook-duo-auto-brightness`, `hypr/autostart.lua` |
| Mouse pointer moves mirrored on the top screen | software cursor | `hypr/input.lua` |
| Touch on one panel moves the cursor on the other | explicit touch→output mapping | `hypr/input.lua` |
| Top touchscreen dead + kernel oops on first touch | blacklist `raydium_i2c_ts` | `touchscreen/zenbook-duo-touchscreen.conf` |
| Shutdown/reboot hangs at the goodbye splash | same blacklist (see below) | same file |
| No sound at all ("Dummy Output") | ghost-RT722 DKMS overlay | `audio/` |
| Detached keyboard won't (re)connect over Bluetooth | pair from the host with one scan open | `scripts/zenbook-duo-keyboard-pair` |
| Keyboard's mute / volume / display-brightness / keyboard-backlight / mic-mute keys do nothing | hid-asus on the vendor interface + a small hotkey bridge daemon | `scripts/zenbook-duo-hid-asus`, `scripts/zenbook-duo-fnkeys`, `udev/` |
| Keyboard backlight and F-row keys dead after powering on docked | helper rule also matches the boot-time `add` event (section 3c) | `udev/61-zenbook-duo-keyboard.rules` |

---

## 1. Displays: orientation and layout

Both panels are 2880×1800. Two quirks:

- **The top panel (`eDP-1`) is physically mounted upside down.** The firmware
  knows this, so the Limine menu looks right, but the kernel has no
  panel-orientation quirk for the UX8407AA yet. As soon as the `xe` driver
  takes over, everything drawn on that panel (Plymouth splash, text console,
  and a compositor with no transform) comes out rotated 180°.
- Hyprland doesn't know the physical stacking, so place the bottom panel
  (`eDP-2`) directly below the top one. At scale 2 the logical size is
  1440×900, hence position `0x900`.

### 1a. Orientation: tell the kernel once, everything follows

`boot/zenbook-duo-panel-orientation.conf` is a drop-in for Omarchy's
`limine-entry-tool` that adds one kernel parameter:

```
video=eDP-1:panel_orientation=upside_down
```

With it the kernel tags the `eDP-1` connector with a "panel orientation"
property. Plymouth, fbcon and Hyprland (via aquamarine) all read that
property and rotate by themselves, so the boot splash is upright and
Hyprland needs **no** `transform` on `eDP-1`. Install:

```sh
sudo install -D -m 0644 boot/zenbook-duo-panel-orientation.conf \
  /etc/limine-entry-tool.d/zenbook-duo-panel-orientation.conf
sudo limine-update     # rebuilds the UKI / boot entries with the new cmdline
```

(`setup.sh` does this. Not on Limine? Add the parameter to your bootloader's
kernel command line by any other means; the effect is the same.) Reboot to
apply — the parameter is baked into the unified kernel image.

**Don't combine this with `transform = 2` in `monitors.lua`** — the panel
would be rotated twice and end up upside down again. If you skip the kernel
parameter, put `transform = 2` back on the `eDP-1` line and only the desktop
is upright; splash and console stay flipped.

### 1b. Layout

From `hypr/monitors.lua`, which `setup.sh` offers to append to
`~/.config/hypr/monitors.lua` (after Omarchy's catch-all monitor rule, so
these win):

In the normal (laptop) orientation it places eDP-1 at `0x0` and eDP-2
directly below it at `0x900` (the panel height at scale 2). The same block
also does the auto-rotation layouts (section 1d).

Verify with `hyprctl monitors`: eDP-1 at `0x0` with transform 0 and the
image upright, eDP-2 at `0x900`. The permanent fix is a `UX8407AA` entry in
the kernel's `drm_panel_orientation_quirks.c`; once a kernel ships it the
drop-in becomes redundant (harmless to keep).

### 1c. Mouse pointer mirrored on the top panel

With the kernel-side rotation in place, Hyprland (aquamarine 0.14, Hyprland
0.56) rotates the rendered frame correctly but still positions the
**hardware cursor plane** in the panel's raw, unrotated coordinates. The
pointer is drawn at the mirror image of where it logically is, so on the
top screen it appears to move upside down while windows and touch are fine.
Render the cursor in software instead; it is then part of the frame that
gets rotated. From `hypr/input.lua`:

```lua
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})
```

Cost: the cursor moves in lockstep with the frame instead of one frame
ahead, and each move damages a small region for repaint. Not noticeable in
practice. Drop this once the backend rotates the cursor plane itself.

### 1d. Auto-rotation (turn the laptop, both screens follow)

Turned on its side, the Duo is a book: the two panels sit side by side. To
follow the device, Linux needs its accelerometer, which sits behind Intel's
sensor hub (ISH). Out of the box the hub never starts: it rejects
linux-firmware's generic `intel/ish/ish_ptl.bin` (`ISH loader: cmd 2 failed
10` in the kernel log), and linux-firmware has no ASUS image for Panther
Lake. ASUS's Windows "Intel Integrated Sensor Solution Driver" contains a
signed one (`AsusSign_ishS_SI_CommonPTL_…bin`). With it loaded, the hub
reports an accelerometer, an ambient light sensor and a hinge-angle sensor.

`scripts/zenbook-duo-sensor-firmware` (run by setup.sh) downloads that driver
from ASUS, checks it against pinned SHA-256 sums, pulls the firmware out of
the installer's embedded 7-Zip archive, and installs it as
`/usr/lib/firmware/updates/intel/ish/ish_ptl_<crc32(vendor)>_<crc32(product)>.bin`,
the board-specific name the kernel's ISH loader tries before the generic
image. The firmware itself can't be redistributed, which is why it is
fetched rather than shipped. Remove the file and reboot to undo it.

The rotation itself is three pieces:

- `iio-sensor-proxy` (setup.sh installs it) turns the raw accelerometer into
  `normal` / `left-up` / `right-up` / `bottom-up`.
- `scripts/zenbook-duo-rotate-watch` (started from `autostart.lua`) waits
  until a reading has held for a second, writes it to
  `~/.local/state/zenbook/rotation`, and reloads Hyprland.
- `hypr/monitors.lua` reads that file and sets each panel's transform
  plus a stacked or side-by-side layout. Keeping the layout in the config,
  not in a one-off `hyprctl` command, means it survives every reload,
  including the dock watcher's. `hypr/input.lua` gives each touchscreen its
  panel's transform: Hyprland does not rotate touch input with the display.

Workspaces stay on the panel they were created on, so after a turn the
watcher swaps the two panels' visible workspaces if needed. The left panel
(side by side), or the upper one (stacked), then always shows the
lower-numbered workspace.

**Sharing mode.** Opened fully flat on a table, the top panel turns around
(transform 2, touch included) so someone sitting opposite can read it, while
the bottom panel stays the right way up for you. The ISH's hinge sensor
tells the two flat cases apart: its `hinge` channel is the opening angle and
its `keyboard` channel the base's tilt from level (both in degrees). Measured
on a UX8407AA:

| Pose | hinge | base tilt |
|---|---|---|
| Laptop | 107–118° | 2–3° |
| Opened flat, lying on the table | 177° | 1–2° |
| Opened flat, tilted up (kickstand or in hand) | 177° | ~45–55° |

So sharing needs both hinge ≥ 170° and base tilt ≤ 15°, and ends at hinge
≤ 160° or base tilt ≥ 25°. Tilted-up flat stays normal use. While sharing,
the accelerometer orientation is ignored.

To hold the current layout (reading in bed, say), create
`~/.local/state/zenbook/rotation-lock`; delete it to resume.

Existing installs: setup.sh leaves Hyprland files that already have their
Zenbook block alone, so merge the new `monitors.lua`, `input.lua` and
`autostart.lua` blocks from `hypr/` by hand.

## 2. Bottom screen ⇄ pogo-pin keyboard

When the detachable keyboard is docked it physically covers the bottom
screen, so the screen should turn off — and come back the moment you lift
the keyboard away. `scripts/zenbook-duo-screen-watch` does this:

- Detects the keyboard by USB ID (`0b05:1cd7`, the 2026/144 Hz model — if
  yours differs, check `lsusb` and edit the two variables at the top).
- On dock/undock it writes/removes a one-line disable rule in **Omarchy's
  toggles directory** (`~/.local/state/omarchy/toggles/hypr/`) and runs one
  `hyprctl reload`. This is the same mechanism Omarchy's clamshell mode uses:
  toggle files load after your config on every reload, so the disabled state
  survives any other reload and never fights
  `omarchy-hyprland-monitor-watch`.
- Debounces the pogo-contact bounce (two consistent reads 1 s apart) and
  fires a DPMS enable after re-enabling, since a reload alone doesn't always
  power the panel back up.
- Runs as a single instance (a lock file), because Hyprland can start
  autostart entries more than once and two watchers racing the same modeset
  is exactly what the display driver does not survive.
- Leaves the panel disabled if the keyboard comes off while the system is
  shutting down, since re-enabling it then only stalls the shutdown.
- Checks the kernel log at startup and after each re-enable. If the panel's
  PHY has failed (section 2b), it disables the panel again, leaves it alone
  for the rest of the boot, and sends one critical notification telling you
  to do the power reset. Without this, every dock event costs a ten-second
  freeze. It retires that notification itself when it stops and when it
  starts (Omarchy restores critical toasts at the next login), so the
  warning only ever refers to the current boot.

`setup.sh` installs it to `~/.config/zenbook/` and offers to append the
start line to `~/.config/hypr/autostart.lua`:

```lua
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-screen-watch")
```

### 2a. Top screen goes dark after login, machine hangs (Panel Replay)

Symptom, on some boots: the disk-unlock prompt and login work, then the top
screen goes dark within seconds and nothing responds; power-cycle. The
kernel log starts with a burst of

```
xe … *ERROR* Timed out waiting for PSR Idle for re-enable      (hundreds, in the first seconds)
xe … Selective fetch area calculation failed in pipe A
```

followed by `flip_done timed out` on pipe A and "Failed to bring PHY A to
idle". Both OLED panels advertise **eDP Panel Replay** (the successor of
PSR), the xe driver enables it on `eDP-1` by default, and `xe.enable_psr=0`
does *not* cover it. When the panel fails to report PSR idle at boot, the
first modesets (Hyprland starting, the dock watcher disabling `eDP-2`)
wedge the top panel's pipe. `boot/zenbook-duo-panel-replay.conf` adds

```
xe.enable_panel_replay=0
```

(installed by `setup.sh` like the other drop-ins; `sudo limine-update`,
reboot). Cost: a little idle power on `eDP-1`, the same trade as
`enable_psr=0`. Across two weeks of boots here, none with the parameter
showed the burst; without it, roughly every other boot did.

### 2b. Bottom screen never comes back after undocking (and the machine freezes)

Symptom: lift the keyboard, the bottom screen stays black, and the top screen
and keyboard freeze for ten seconds or more. Docking again "works" after a
similar pause. Shutdown then sits on a blank screen with the power light on
for about a minute (hold the power button). The kernel log has the same
sequence every time, about two seconds after USB sees the keyboard leave:

```
xe … PHY B failed to request refclk
xe … PHY B failed to change powerdown state
xe … *ERROR* Failed to bring PHY B to idle.
xe … *ERROR* [CONNECTOR:521:eDP-2][ENCODER:520:DDI B/PHY B][DPRX] Failed to enable link training
xe … *ERROR* [CRTC:270:pipe B] flip_done timed out          (then every 10 s)
```

**What is going on.** The xe driver on 7.1.9 cannot bring the bottom panel's
PHY (PHY B, DDI B) up from scratch. It works only when it inherits a PHY the
firmware initialised at power-on, and the firmware lights the bottom panel
only when the keyboard is off the laptop at that moment. Once the PHY has
wedged, every display update that touches it blocks the compositor for a
ten-second kernel timeout (the "dead keyboard" after each dock event, the
slow shutdown), and the bad state outlives the boot: a warm reboot and a
quick power-off both carry it forward, and the next boot then fails by
itself two seconds after the boot splash starts ("AUX B … Failed to write
aux backlight level: -110", then pipe B timeouts), keyboard or no keyboard.
Only a real power reset clears it, so the state is held by something that
stays powered through a short shutdown (embedded controller or panel), not
by the SoC.

**The rules.**

1. Power on with the keyboard lifted off; dock it at the disk-unlock prompt.
2. Never dock or undock while the machine is shutting down or rebooting.
3. If the bottom screen fails to come back, or the dock watcher's
   notification appears: shut down, unplug the charger, hold the power
   button for 15 seconds, leave the machine off for a minute, then power on
   with the keyboard off. Firmware "load setup defaults" clears it too.

Evidence, from two days of boots on identical software:

| Situation | Boots | Result |
|---|---|---|
| keyboard docked at power-on | 9 | first undock fails |
| keyboard off at power-on, previous boot healthy | 5 | clean, dock cycles work |
| keyboard off at power-on, previous boot wedged, reboot or quick power-off | 5 | fails 2 s into the boot splash |
| same, after a full power reset | 1 | clean |

Ruled out: `xe.enable_dc=0`, Panel Replay (2a, a separate problem), the
charger, package updates, the BIOS version, docking during boot (a boot
with the disk password typed on an external USB keyboard failed the same
way), forcing the connector off during boot (`video=eDP-2:d`), and keeping
the panel enabled but dark while docked (Hyprland's first modeset at login
hits the same PHY).

Reported upstream as
[drm/xe issue 9196](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196);
the report and both kernel logs are in `reference/xe-bug-report/`.

## 3. Brightness

### 3a. Nothing changes on either screen (OLED needs DPCD backlight)

Both panels are BOE NB140B9M **OLEDs**. They have no PWM backlight line;
brightness is a command sent over the eDP AUX channel (VESA DPCD backlight,
which both panels advertise: `EDP_BACKLIGHT_CAP` has the AUX-set bit). The
firmware's VBT nevertheless tells the Intel driver the panels use the PWM
pin, so the driver's default (`enable_dpcd_backlight=-1`, "trust VBT")
programs a PWM that goes nowhere: `brightnessctl` reports success,
`/sys/class/backlight/intel_backlight/actual_brightness` follows the value,
and the picture never changes. On `eDP-2` it is even more visible —
`card0-eDP-2-backlight` always reads `actual_brightness = 0`.

`boot/zenbook-duo-dpcd-backlight.conf` is a `limine-entry-tool` drop-in that
adds:

```
xe.enable_dpcd_backlight=1
```

(1 = enable DPCD control, driver picks the interface; 2 would force VESA,
3 the Intel proprietary one.) Install like the orientation drop-in:

```sh
sudo install -D -m 0644 boot/zenbook-duo-dpcd-backlight.conf \
  /etc/limine-entry-tool.d/zenbook-duo-dpcd-backlight.conf
sudo limine-update
```

Reboot; afterwards `brightnessctl set 30%` visibly dims the top panel and
the bottom panel's own backlight device starts applying values. Diagnose
without rebooting by writing the panel's DPCD registers directly through
`/dev/drm_dp_aux0` (0x721 = 0x02 selects AUX brightness, 0x722/0x723 set the
level) — if the screen reacts, the panel is fine and only the driver mode is
wrong.

Note the unrelated `asus_screenpad` backlight device that `asus-nb-wmi`
registers: writes to it stick but drive neither panel on this model.

### 3b. Bottom panel does not follow the top one

Brightness keys and the DE only drive the top panel's backlight
(`intel_backlight`); the bottom panel's own backlight
(`card0-eDP-2-backlight`) never follows and can sit near zero — a "broken
dark screen" that is really just brightness.
`scripts/zenbook-duo-brightness-sync` watches the top backlight with
inotify and mirrors the percentage across using `brightnessctl`. Needs the
`brightnessctl` and `inotify-tools` packages (setup.sh installs them).
Started from `autostart.lua` the same way as the screen watcher.

### 3c. Keyboard backlight dead after powering on docked

The keyboard's backlight is the `asus::kbd_backlight` LED that `hid-asus`
registers once section 6c's helper hands it the keyboard's vendor
interface; Omarchy's stock keyboard-backlight key and brightness keys then
drive it. With the keyboard docked at power-on, the helper used to never
run: the keyboard binds to `hid-generic` inside the initramfs (it is needed
for the disk-unlock prompt), where the helper's udev rule does not exist,
and the rule only reacted to `bind` events. The only event the keyboard sees
after the switch to the real root is the `add` that `systemd-udev-trigger`
replays, so it stayed on `hid-generic` for the whole session: no backlight
LED, and the F-row sent plain F-keys (section 6c). The rule now matches
`add|bind`, which covers a keyboard docked at power-on as well as one docked
or reconnected later. Verified on 7.2.5: powered on docked, the helper
rebinds within seconds of boot, and over Bluetooth the vendor interface also
lands on `hid-asus`.

### 3d. Auto-brightness from the ambient light sensor

The same ASUS sensor-hub firmware that enables auto-rotation (section 1d)
also brings up an ambient light sensor, which `iio-sensor-proxy` reports in
lux. `scripts/zenbook-duo-auto-brightness` (started from `autostart.lua`)
sets the top panel's backlight from it, and the brightness mirror (3b)
carries it to the bottom panel.

- **Curve:** brightness follows the light on a logarithmic scale, about 8%
  in the dark plus 22 points for every tenfold increase in light (so ~30% at
  10 lux, ~52% at 100 lux, ~74% at 1000 lux).
- **Smooth:** readings are smoothed, changes smaller than 4 points are
  ignored, and new levels fade in over about a second.
- **Manual changes win.** When the brightness keys, the Omarchy slider or
  anything else changes the backlight, the difference from the curve is
  saved as an offset (`~/.local/state/zenbook/auto-brightness-offset`) and
  kept as the light changes. On first start it adopts the current
  brightness instead of jumping to the curve.
- **Back to the default curve:** **Super + F5** (the display-brightness-down
  key, bound in `hypr/bindings.lua`), or
  `~/.config/zenbook/zenbook-duo-auto-brightness reset`, forgets the offset;
  the running instance picks it up within a few seconds.
- **Pause:** create `~/.local/state/zenbook/auto-brightness-off`; delete it to
  resume.

## 4. Touchscreens

Two independent problems here.

### 4a. Top touchscreen dead, kernel oops, and the shutdown/reboot hang

The top touchscreen (ACPI `RAYD0001`) is a HID-over-I2C device
(PNP0C50-compatible), but the kernel's native `raydium_i2c_ts` driver claims
it first, misreads the protocol (zero axis ranges, so libinput rejects the
device) and **oopses in `raydium_i2c_irq` on the first touch** — deterministic
on kernel 7.1.9.

That oops is also the cause of the mysterious **shutdown/reboot hang at the
Omarchy goodbye splash**: the crashed IRQ thread dies holding interrupts
disabled, userspace shutdown completes, and the late kernel poweroff wedges.
One blacklist fixes both. `touchscreen/zenbook-duo-touchscreen.conf` goes in
`/etc/modprobe.d/`:

```
blacklist raydium_i2c_ts
```

With the native driver out of the way, `i2c-hid-acpi` binds the controller
and the panel (and pen) just work. If a future kernel fixes
`raydium_i2c_ts`, the blacklist can be dropped.

### 4b. Touch input mapped to the wrong screen

Two identical internal touchscreens confuse Hyprland's auto-mapping —
touching the bottom screen moved the cursor on the top one. Bind each device
to its panel explicitly. From `hypr/input.lua`, which `setup.sh` offers to
append to `~/.config/hypr/input.lua`:

```lua
-- Bottom panel touchscreen + stylus (i2c-hid, RAYD0002).
hl.device({ name = "rayd0002:00-2386:8c06", output = "eDP-2" })
hl.device({ name = "rayd0002:00-2386:8c06-stylus", output = "eDP-2" })
-- Top panel touchscreen + stylus (i2c-hid, RAYD0001; the native raydium_i2c_ts
-- driver is blacklisted in /etc/modprobe.d/zenbook-duo-touchscreen.conf).
hl.device({ name = "rayd0001:00-2386:8c05", output = "eDP-1" })
hl.device({ name = "rayd0001:00-2386:8c05-stylus", output = "eDP-1" })
```

(Device names come from `hyprctl devices`; they should match on any
UX8407AA.)

## 5. Audio: no sound card at all ("Dummy Output")

The firmware advertises a **ghost Realtek RT722 codec** on SoundWire link 3
that isn't physically fitted, next to the real Cirrus CS42L43. On kernels
without the upstream quirk (still the case for Arch 7.2.3 and Omarchy's
`linux-omarchy` 7.2.5) the generic `sof_sdw` machine driver builds a DAI
link for both, hits a
duplicate `SDW3-Playback-SimpleJack`, and the whole probe aborts with error
-12 — so **no ALSA card registers** and PipeWire shows only "Dummy Output".
Diagnose with:

```sh
cat /proc/asound/cards            # "no soundcards" = this bug
journalctl -k -b | grep -E 'SimpleJack|sof_sdw'
```

`audio/` contains a DKMS overlay that rebuilds the `snd-soc-sof-sdw` module
with a narrow filter: it drops only a device
with the RT722's ID (mfg `0x025d`, part `0x0722`) that the SoundWire core has
already marked UNATTACHED, and only on this board (DMI-gated to `UX8407AA`).
It is adapted from
[burakgon/asus-expertbook-linux](https://github.com/burakgon/asus-expertbook-linux)
(same Panther Lake audio bug on the ExpertBook B9406CAA) with two changes:
a DMI entry for `UX8407AA`, and `LLVM=1` removed from `dkms.conf` — the stock
Arch kernel is GCC-built and clang chokes on its cflags.

The overlay is a patched copy of the kernel's own `sof_sdw.c`, so it has to
match the kernel it is built for, and there are two versions:

| Version | Kernel | Source |
|---|---|---|
| `zenbook-duo-sof-sdw-3.0.0/` | stock Arch `linux` | 7.1-era `sof_sdw.c` |
| `zenbook-duo-sof-sdw-3.1.0/` | Omarchy `linux-omarchy` 7.2.5 | v7.2.5 `sof_sdw.c` plus the sof_sdw hunks of Omarchy's sound patches (`0510`–`0514` in [omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs)) |

Omarchy's sound patches change the `soc_sdw_utils` API
(`asoc_sdw_parse_sdw_endpoints()` takes `dev, ctx` instead of `card`), so
3.0.0 fails to build there and DKMS silently leaves the stock, broken module
in place. That is how Omarchy's switch to its own kernel brings "Dummy
Output" back. The ghost filter itself is identical in both versions.

Install with `audio/install-audio-fix.sh` (run via `pkexec`/sudo; setup.sh
does this). It picks the version for the running kernel, installs `dkms` +
headers, builds the module, and regenerates the initramfs. Reboot afterwards.
After a kernel switch, boot the new kernel and run it again.

**This is a temporary shim.** The permanent fix — a `ghost_realtek` DMI
quirk for `UX8407AA` in `drivers/soundwire/dmi-quirks.c` — is already in
Linus' tree, but not yet in the 7.2 kernels Arch and Omarchy ship. The
install script detects a fixed kernel and refuses to install. Once your
kernel has it, remove the overlay:

```sh
sudo dkms remove -m zenbook-duo-sof-sdw -v 3.0.0 --all
sudo dkms remove -m zenbook-duo-sof-sdw -v 3.1.0 --all
sudo rm -rf /usr/src/zenbook-duo-sof-sdw-3.*
sudo limine-mkinitcpio
```

Each version only builds against the kernel it was made from. After any
kernel update, check `dkms status` and `wpctl status`: a version missing
from `dkms status` for the new kernel, or a "Dummy Output" sink, means the
overlay needs porting to that kernel's `sof_sdw.c`.

Everything else audio-related is already upstream on a current Arch install:
`alsa-ucm-conf ≥ 1.2.16` ships the HiFi UCM profile and `linux-firmware`
ships this laptop's CS35L56 amp tuning (`cirrus/cs35l56-*-10431444-*`).

## 6. Bluetooth: the detachable keyboard, and pairing in general

### 6a. Omarchy's pairing agent rejects pairings a device starts

Omarchy runs `bt-agent -c NoInputNoOutput` as a user service meant to
auto-accept pairing. Its unit gives it no terminal, so when a *device*
initiates pairing BlueZ asks the agent "Authorize this device pairing
(yes/no)?", the read hits end-of-file, and the answer is no. The symptom is
a keyboard that connects and drops every ~3 s with

```
bt-agent[…]: Authorize this device pairing (yes/no)? Device: … (XX:XX:…)
bluetoothd[…]: No matching connection for device
```

repeating in `journalctl --user -b`. Pairing **from the laptop** never asks
that question and works first time:

```sh
bluetoothctl scan le &          # keep one discovery open
bluetoothctl pair  XX:XX:XX:XX:XX:XX
bluetoothctl trust XX:XX:XX:XX:XX:XX
bluetoothctl connect XX:XX:XX:XX:XX:XX
```

The same applies to any BLE peripheral (it bit a ZMK keyboard first).

### 6b. The Zenbook keyboard gets a new address every time it pairs

The detachable keyboard (`ASUS Zenbook Duo Keyboard`; USB `0b05:1cd7` when
docked) is a Bluetooth keyboard only while lifted off the pogo pins — docked,
its radio is off and it is a USB keyboard. Each time it is put into pairing
mode (hold its Bluetooth key ~3 s until the indicator blinks) it **mints a
new static address** (an `EE:…` address whose low bytes step up with each
pairing — four different addresses over one afternoon). Two consequences:

- The bond the laptop holds is for an address the keyboard no longer uses,
  so "it just stopped reconnecting" after someone held the key.
- The keyboard's new address is an unknown device to BlueZ, which never
  auto-connects to strangers, and with 6a the keyboard's own pairing attempt
  is refused. Net effect: silence.

And you cannot type the fix, because the keyboard is undocked. So start
`scripts/zenbook-duo-keyboard-pair` (installed to `~/.config/zenbook/` by
`setup.sh`) **first**, then undock and hold the key:

```sh
~/.config/zenbook/zenbook-duo-keyboard-pair     # waits up to 5 min
```

It keeps one scan open, pairs/trusts/connects whatever advertises under that
name (reconnecting a known address if that is what appears), and removes the
stale entries for the same name afterwards. To merely *reconnect* a keyboard
that is still bonded, do not hold the Bluetooth key — a keypress is enough.

### 6c. The keyboard's special function keys

None of these F-row keys work out of the box, docked or on Bluetooth:

| Key (F-row) | What it should do |
|---|---|
| Mute / volume down / volume up (F1 / F2 / F3) | Speaker mute and volume |
| Display brightness down / up (F5 / F6) | Dim / brighten the **screens** — the same thing the Omarchy brightness slider does (needs the OLED fix from section 3a to be visible) |
| Keyboard backlight (F4) | **Cycle the keyboard's own key backlight** through its levels (off, low, mid, high) |
| Mic mute (F10) | Toggle the microphone |

Two different backlights are involved, so to be clear: the two *brightness*
keys drive the display panels, and the single *keyboard backlight* key
drives the LEDs under the keycaps and only cycles those. What is going on,
found by capturing the raw HID traffic:

- Until an ASUS driver has claimed the keyboard's **vendor interface** (the
  one whose report descriptor declares usage page `0xFF31`), the firmware
  sends those keys as plain **F1/F2/F3/F5/F6/F4/F10** and nothing at all with Fn held.
- Once `hid-asus` is bound to that interface *with its keyboard-backlight
  quirk*, the firmware switches to real ASUS hotkey reports: report id `0x5a`
  with one code byte (`0x20` display brightness up, `0x10` display
  brightness down, `0xc7` keyboard backlight cycle, `0x7c` mic mute). Mute
  and volume switch to ordinary consumer-page codes, which work as they are.
- `hid-asus` would normally map those codes to keys, but this keyboard
  declares the `0x5a` report as a single `Usage 0x76` with variable data,
  not the usage array the driver's mapping table works on; the driver only
  rewrites that shape for two old models, keyed on exact descriptor sizes.
  So the reports arrive and stop there.

Two pieces, both installed by `setup.sh`:

1. **`scripts/zenbook-duo-hid-asus` + `udev/61-zenbook-duo-keyboard.rules`** —
   this 2026 keyboard (USB `0b05:1cd7`, Bluetooth `0b05:1cd8`) is not in
   `hid-asus`'s device table, so the rule runs the helper whenever the
   vendor interface lands on `hid-generic`; it adds the id with
   `QUIRK_USE_KBD_BACKLIGHT` (`new_id … 20`) and rebinds. That both enables
   the hotkey reports and registers `/sys/class/leds/asus::kbd_backlight`
   (levels 0–3) for the keyboard's key backlight, which
   `omarchy brightness keyboard up|down|cycle` drives. (Display brightness
   needs no LED: it goes through `intel_backlight`, section 3a.)
   Side effect: the driver renames the keyboard "Asus Keyboard".
2. **`scripts/zenbook-duo-fnkeys` + `udev/zenbook-duo-fnkeys.service`** — a
   root daemon that follows those interfaces as they come and go (dock,
   undock, Bluetooth), reads the `0x5a` reports from `hidraw`, and injects
   the matching keys through `/dev/uinput` as a virtual keyboard "Zenbook
   Duo Keyboard Fn keys": `KEY_BRIGHTNESSDOWN` / `KEY_BRIGHTNESSUP` for the
   display, `KEY_KBDILLUMTOGGLE` for the keyboard backlight, `KEY_MICMUTE`.
   Omarchy's stock bindings then fire — display brightness steps the panels,
   the backlight key cycles the LED levels, mic mute toggles the microphone. Unknown codes are logged
   (`journalctl -u zenbook-duo-fnkeys`) so new keys are easy to add.

The proper fix is a kernel patch: the ids in `hid-ids.h`, a device-table
entry with `QUIRK_USE_KBD_BACKLIGHT`, and a report-descriptor fixup that
turns `Usage 0x76` into `Usage Min 0x00 / Max 0xff` for the `0x5a` input
report, after which `hid-asus` maps everything natively and piece 2
becomes unnecessary.

An earlier version of this package also remapped the plain F-keys with an
hwdb file and drove the backlight through its own hidraw tool. Both only
covered for `hid-asus` not being bound, which in practice meant a keyboard
docked at power-on (section 3c); with that fixed they were removed, and
`setup.sh` deletes them from older installs.

Verified on both paths: docked over USB and detached over Bluetooth, the
keys work and the backlight LED follows the keyboard; everything comes back
by itself after docking, reconnecting, or a reboot. With `hid-asus` bound,
each key press is a single report, even when held.

Diagnose with a raw capture (root): read `/dev/hidraw*` for the keyboard
plus `/dev/input/event*` while pressing keys. `5a 20 00 …` on the vendor
interface means the hotkey channel is alive; F-key usages (`0x3d`–`0x43`)
on the plain keyboard report mean `hid-asus` is not bound.

## 7. Kernel command line (reference)

The working machine also boots with these parameters (drop-ins in
`/etc/limine-entry-tool.d/`):

- `video=eDP-1:panel_orientation=upside_down` — **required** by the
  `monitors.lua` shipped here; see section 1a.
- `xe.enable_dpcd_backlight=1` — **required** for brightness control at all
  on these OLED panels; see section 3a.
- `xe.enable_panel_replay=0` — **required** or some boots hang with a dark
  top screen; see section 2a.
- `xe.enable_psr=0` — disables Panel Self Refresh on the Intel Xe driver,
  a common cure for flicker/artifacts on eDP panels.
- `rtc_cmos.use_acpi_alarm=1` — makes RTC wake alarms go through ACPI.

The last two are not required by anything in this package; listed so a diff
against your own cmdline doesn't surprise you.

## 8. Post-install verification

After `setup.sh` and a power cycle:

```sh
wpctl status                       # Speaker/Headphone sinks, not Dummy Output
cat /proc/asound/cards             # one real card
hyprctl monitors                   # eDP-1 transform 0 @ 0x0 (upright), eDP-2 @ 0x900
grep -o 'panel_orientation=[a-z_]*' /proc/cmdline   # upside_down
grep -o 'enable_dpcd_backlight=[0-9]' /proc/cmdline # 1
grep -o 'enable_panel_replay=[0-9]' /proc/cmdline   # 0
journalctl -k -b | grep -c 'PSR Idle for re-enable'  # 0
brightnessctl set 30%; sleep 2; brightnessctl set 60%  # top panel visibly dims/brightens
bluetoothctl devices Paired | grep 'Zenbook Duo Keyboard'   # exactly one entry
ls /sys/class/leds | grep kbd_backlight   # asus::kbd_backlight, also when powered on docked (section 3c)
systemctl is-active zenbook-duo-fnkeys     # active; journal shows "watching /dev/hidrawN"
hyprctl devices | grep rayd        # both touchscreens present
hyprctl getoption cursor:no_hardware_cursors   # int: 1
journalctl -k -b | grep -i ghost   # "ignoring unattached firmware ghost" (kernels before 7.3)
dkms status | grep zenbook         # an overlay version installed for the running kernel (section 5)
journalctl -k -b | grep 'ISH loader'   # "firmware loaded", FW 5.8.1.x (section 1d)
cat /sys/bus/iio/devices/*/name    # includes accel_3d, als and hinge
monitor-sensor                     # orientation and light level change as you move the laptop / cover the sensor
cat ~/.local/state/zenbook/rotation   # current layout: normal, left-up, right-up, bottom-up or sharing
```

Power on with the keyboard off the laptop and dock it only once the
unlock prompt is on both screens (section 2b). Then:

- Dock the keyboard: the bottom screen blanks within ~2 s and returns when
  undocked, with no `PHY B` lines in `journalctl -k -b`.
- Undock and press a key: it types over Bluetooth within a few seconds (if
  not, section 6b).
- Mute, volume, brightness, keyboard backlight and mic mute keys work docked
  and detached (section 6c).
- Turn the laptop onto each side: both screens rotate, workspace 1 stays on
  the left screen, and touch lands where you touch (section 1d).
- Open it flat on the table: the top screen turns around for the person
  opposite; tilt it up and it turns back (section 1d).
- Cover the sensor near the webcam: the screens fade darker; Super+F5
  returns auto-brightness to its default curve (section 3d).
- Touch each screen: the cursor reacts on the screen you touched.
- Change brightness: both panels follow.
- Reboot and shutdown complete without hanging at the splash, and the
  splash is upright on both panels.

## License

MIT (see `LICENSE`). The exception is `audio/zenbook-duo-sof-sdw-*/`,
which is a modified copy of a GPL-2.0 Linux kernel module and stays under
that license; see its own sources for attribution.
