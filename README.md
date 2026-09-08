# ASUS Zenbook Duo (UX8407AA) on Omarchy — hardware setup guide

Everything needed to make a 2026 Zenbook Duo UX8407AA fully work under
[Omarchy](https://omarchy.org) (Arch + Hyprland), collected from getting one
machine working in September 2026 on kernel `7.1.9-arch1-2`. Every config and
binary referenced here ships in this directory, ready to copy.

> **If the bottom screen stays black after undocking, the keyboard goes dead
> for ten seconds after each dock event, or shutdown sits on a blank screen
> for a minute:** the bottom panel's display PHY was never initialised by the
> firmware, because the keyboard was sitting on it when the machine powered
> on. Power off completely, lift the keyboard off, power on, and dock it only
> once the disk-unlock prompt is showing on *both* screens (the bottom one
> lights first). A reboot does not help while the keyboard is docked. Details
> and the evidence in section 2b. (A top screen that goes dark right after
> login is a different problem, section 2a.)

**Quick start:** `bash setup.sh` (it asks before appending its three blocks to
your Hyprland config), power off, and power on with the keyboard lifted off
(section 2b).
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
| Mouse pointer moves mirrored on the top screen | software cursor | `hypr/input.lua` |
| Touch on one panel moves the cursor on the other | explicit touch→output mapping | `hypr/input.lua` |
| Top touchscreen dead + kernel oops on first touch | blacklist `raydium_i2c_ts` | `touchscreen/zenbook-duo-touchscreen.conf` |
| Shutdown/reboot hangs at the goodbye splash | same blacklist (see below) | same file |
| No sound at all ("Dummy Output") | ghost-RT722 DKMS overlay | `audio/` |
| Detached keyboard won't (re)connect over Bluetooth | pair from the host with one scan open | `scripts/zenbook-duo-keyboard-pair` |
| Keyboard's display-brightness / keyboard-backlight / mic-mute keys do nothing | hid-asus on the vendor interface + a small hotkey bridge daemon | `scripts/zenbook-duo-hid-asus`, `scripts/zenbook-duo-fnkeys`, `udev/` |

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

```lua
local zenbook_duo_scale = omarchy_monitor_scale or 2
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = zenbook_duo_scale })
hl.monitor({ output = "eDP-2", mode = "preferred", position = "0x900", scale = zenbook_duo_scale })
```

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
and keyboard freeze for ten seconds or more, sometimes for good. Docking again
"works" after a similar pause. Shutdown then sits on a blank screen with the
power light on for about a minute (hold the power button). The kernel log has
the same sequence every time, about two seconds after USB sees the keyboard
leave:

```
xe … PHY B failed to request refclk
xe … PHY B failed to change powerdown state
xe … *ERROR* Failed to bring PHY B to idle.
xe … *ERROR* [CONNECTOR:521:eDP-2][ENCODER:520:DDI B/PHY B][DPRX] Failed to enable link training
xe … *ERROR* [CRTC:270:pipe B] flip_done timed out          (then every 10 s)
```

**Cause: the firmware only initialises the bottom panel's PHY when the
keyboard is off the laptop at power-on.** With the keyboard docked, the
firmware never lights the covered panel, and the xe driver on 7.1.9 cannot
bring that PHY (PHY B, DDI B) up from scratch on its own: the first time it
has to power the panel back on after Hyprland disabled it, the refclk
handshake fails and the port is wedged for the rest of that boot. If the
firmware did light the panel, the kernel inherits a working PHY and can
power it down and up as often as the dock watcher asks.

**The rule:** power on with the keyboard lifted off. Wait for the disk-unlock
prompt to appear on both screens (the bottom one comes up first), then dock
the keyboard and type. From then on dock and undock freely. If you ever
powered on docked, a reboot will not fix it, because the firmware skips the
panel again; do a full power-off first. Once the port is wedged, every
display update that touches it blocks the compositor for a ten-second
kernel timeout, which is the "dead keyboard" after each dock event and the
slow shutdown.

Evidence, from one day of boots on identical software (same kernel, same
parameters, same scripts):

| Keyboard at power-on | Boots | First undock after login |
|---|---|---|
| docked | 9 (cold and warm, before and after a BIOS defaults reset) | PHY B failed every time |
| off the laptop | 4 (two on Sept 1, two on Sept 7) | clean, zero xe errors, up to three dock cycles each |

Ruled out on the way, so nobody repeats them: a warm reboot versus a full
power-off (both fail when docked at power-on), the USB-C charger, a BIOS
defaults reset, `xe.enable_dc=0`, package updates, and the BIOS version.
Panel Replay (2a) is a separate problem: turning it off does not change
this one. Keeping eDP-2 enabled and merely dark while
docked does not help either: Hyprland's first modeset at login already hits
the same PHY.

This is a driver limitation, reported upstream as
[drm/xe issue 9196](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196);
the report and both kernel logs are in `reference/xe-bug-report/`. Until it
is fixed, the watcher is fine as long as the power-on rule is followed.

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
< 7.2 the generic `sof_sdw` machine driver builds a DAI link for both, hits a
duplicate `SDW3-Playback-SimpleJack`, and the whole probe aborts with error
-12 — so **no ALSA card registers** and PipeWire shows only "Dummy Output".
Diagnose with:

```sh
cat /proc/asound/cards            # "no soundcards" = this bug
journalctl -k -b | grep -E 'SimpleJack|sof_sdw'
```

`audio/` contains a DKMS overlay (`zenbook-duo-sof-sdw-3.0.0/`) that rebuilds
the `snd-soc-sof-sdw` module with a narrow filter: it drops only a device
with the RT722's ID (mfg `0x025d`, part `0x0722`) that the SoundWire core has
already marked UNATTACHED, and only on this board (DMI-gated to `UX8407AA`).
It is adapted from
[burakgon/asus-expertbook-linux](https://github.com/burakgon/asus-expertbook-linux)
(same Panther Lake audio bug on the ExpertBook B9406CAA) with two changes:
a DMI entry for `UX8407AA`, and `LLVM=1` removed from `dkms.conf` — the stock
Arch kernel is GCC-built and clang chokes on its cflags.

Install with `audio/install-audio-fix.sh` (run via `pkexec`/sudo; setup.sh
does this). It installs `dkms` + headers, builds the module, and regenerates
the initramfs. Reboot afterwards.

**This is a temporary shim.** The permanent fix — a `ghost_realtek` DMI
quirk for `UX8407AA` in `drivers/soundwire/dmi-quirks.c` — is already in
Linus' tree and expected in Linux 7.2+. The install script detects a fixed
kernel and refuses to install. Once your kernel has it, remove the overlay:

```sh
sudo dkms remove -m zenbook-duo-sof-sdw -v 3.0.0 --all
sudo rm -rf /usr/src/zenbook-duo-sof-sdw-3.0.0
sudo limine-mkinitcpio
```

Don't leave a stale overlay installed across major kernel upgrades — it's
built from 7.1-era sources and may stop compiling or misbehave.

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
new static address** (`EE:02:2C:39:01:90`, `…02:90`, `…03:90`, `…05:90` over
one afternoon). Two consequences:

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

Volume up/down/mute on the F-row work out of the box (ordinary consumer-page
keys). Four other F-row keys do not, docked or on Bluetooth:

| Key (F-row) | What it should do |
|---|---|
| Display brightness down / up (F5 / F6) | Dim / brighten the **screens** — the same thing the Omarchy brightness slider does (needs the OLED fix from section 3a to be visible) |
| Keyboard backlight (F4) | **Cycle the keyboard's own key backlight** through its levels (off, low, mid, high) |
| Mic mute (F10) | Toggle the microphone |

Two different backlights are involved, so to be clear: the two *brightness*
keys drive the display panels, and the single *keyboard backlight* key
drives the LEDs under the keycaps and only cycles those. What is going on,
found by capturing the raw HID traffic:

- Until an ASUS driver has claimed the keyboard's **vendor interface** (the
  one whose report descriptor declares usage page `0xFF31`), the firmware
  sends those keys as plain **F5/F6/F4/F10** and nothing at all with Fn held.
- Once `hid-asus` is bound to that interface *with its keyboard-backlight
  quirk*, the firmware switches to real ASUS hotkey reports: report id `0x5a`
  with one code byte (`0x20` display brightness up, `0x10` display
  brightness down, `0xc7` keyboard backlight cycle, `0x7c` mic mute).
- `hid-asus` would normally map those codes to keys, but this keyboard
  declares the `0x5a` report as a single `Usage 0x76` with variable data,
  not the usage array the driver's mapping table works on; the driver only
  rewrites that shape for two old models, keyed on exact descriptor sizes.
  So the reports arrive and stop there.

Three pieces, all installed by `setup.sh`:

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
3. **`udev/61-zenbook-duo-keyboard.hwdb`** — belt and braces: maps the plain
   F5/F6/F4/F10 scancodes to the same functions for this keyboard only, so
   the keys still work in the window before `hid-asus` binds. Harmless
   otherwise, since the firmware sends either the F-key or the hotkey, never
   both.

The proper fix is a kernel patch: the ids in `hid-ids.h`, a device-table
entry with `QUIRK_USE_KBD_BACKLIGHT`, and a report-descriptor fixup that
turns `Usage 0x76` into `Usage Min 0x00 / Max 0xff` for the `0x5a` input
report, after which `hid-asus` maps everything natively and pieces 2 and 3
become unnecessary.

Verified on both paths: docked over USB and detached over Bluetooth, the
four keys work and the backlight LED follows the keyboard; everything comes
back by itself after docking, reconnecting, or a reboot.

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
ls /sys/class/leds | grep kbd_backlight   # asus::kbd_backlight once the keyboard is docked/connected
systemctl is-active zenbook-duo-fnkeys     # active; journal shows "watching /dev/hidrawN"
hyprctl devices | grep rayd        # both touchscreens present
hyprctl getoption cursor:no_hardware_cursors   # int: 1
journalctl -k -b | grep -i ghost   # "ignoring unattached firmware ghost" (pre-7.2 kernels)
```

Power on with the keyboard off the laptop and dock it only once the
unlock prompt is on both screens (section 2b). Then:

- Dock the keyboard: the bottom screen blanks within ~2 s and returns when
  undocked, with no `PHY B` lines in `journalctl -k -b`.
- Undock and press a key: it types over Bluetooth within a few seconds (if
  not, section 6b).
- Brightness, keyboard backlight and mic mute keys work docked and detached
  (section 6c).
- Touch each screen: the cursor reacts on the screen you touched.
- Change brightness: both panels follow.
- Reboot and shutdown complete without hanging at the splash, and the
  splash is upright on both panels.

## License

MIT (see `LICENSE`). The exception is `audio/zenbook-duo-sof-sdw-3.0.0/`,
which is a modified copy of a GPL-2.0 Linux kernel module and stays under
that license; see its own sources for attribution.
