Filed as https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196 on 2026-09-08.
Title and description as revised on 2026-09-08 (the follow-up in followup-2026-09-08.md was folded in).

Title: xe/PTL: eDP-2 on DDI B ends up in a state where any enable fails ("PHY B failed to request refclk"), persisting across reboots until a full power reset

## Hardware / software

- ASUS Zenbook Duo UX8407AA (2026), BIOS UX8407AA.305
- Intel Panther Lake, device ID b0a0, display version 30.00 stepping B0, DMC i915/xe3lpd_dmc.bin v2.36, GuC 70.72.1
- Two internal eDP OLED panels, both BOE NB140B9M 2880x1800: eDP-1 (DDI A / PHY A, top) and eDP-2 (DDI B / PHY B, bottom, covered by a detachable keyboard when docked; the firmware lights it at power-on only when the keyboard is off)
- Kernel 7.1.9-arch1-2 (Arch), mesa 26.2.1, Hyprland 0.56.2 / aquamarine 0.14.0 (atomic modesetting)
- Command line: `xe.enable_panel_replay=0 video=eDP-1:panel_orientation=upside_down xe.enable_dpcd_backlight=1 xe.enable_psr=0`

## Summary

The bottom panel's port can get into a state where every enable of eDP-2 fails at the C20 PHY bring-up and the pipe is unusable. The state persists across warm reboots and quick power-offs and is only cleared by a full power reset.

Failing enable (compositor re-enabling eDP-2 after it had been disabled):

```
[   83.821137] usb 3-6: USB disconnect, device number 2        <- keyboard undocked, compositor re-enables eDP-2
[   85.847105] xe 0000:00:02.0: [drm] PHY B failed to request refclk
[   85.850088] xe 0000:00:02.0: [drm] PHY B failed to change powerdown state
[   85.865049] xe 0000:00:02.0: [drm] PHY B failed to bring out of lane reset
[   85.867018] xe 0000:00:02.0: [drm] PHY B failed to change powerdown state
[   85.870073] xe 0000:00:02.0: [drm] *ERROR* Failed to bring PHY B to idle.
[   85.875048] xe 0000:00:02.0: [drm] *ERROR* PHY B Read 0d00 failed after 3 retries.
[   85.883017] xe 0000:00:02.0: [drm] *ERROR* PHY B Write 0c03 failed after 3 retries.
[   86.565061] xe 0000:00:02.0: [drm] Port B PLL not locked
[   92.170236] xe 0000:00:02.0: [drm] *ERROR* Timeout waiting for DDI BUF B to get active
[   95.795071] xe 0000:00:02.0: [drm] *ERROR* [CONNECTOR:521:eDP-2][ENCODER:520:DDI B/PHY B][DPRX] Failed to enable link training
[   96.477068] xe 0000:00:02.0: [drm] *ERROR* Timed out waiting for DP idle patterns
[  107.171145] xe 0000:00:02.0: [drm] *ERROR* [CRTC:270:pipe B] flip_done timed out
```

From then on every atomic commit that includes pipe B waits out the 10 s flip_done timeout ("commit wait timed out", "pipe state doesn't match!", "DPLL 1: pll hw state mismatch", AUX writes to the panel return -110). The compositor stalls for each timeout, and shutdown takes about a minute because the fbcon restore hits the same timeouts. Disabling and re-enabling the connector does not recover it.

## What puts the port into this state

1. A boot with the keyboard docked at power-on. The firmware leaves the covered panel dark, and the driver's first enable of eDP-2 fails as above. Deterministic (9 of 9 boots).
2. An eDP-2 modeset interrupted by a shutdown: undocking while the machine was rebooting produced the same failure from a healthy boot.

Docking or undocking at other times does not: a healthy boot survives any number of disable/enable cycles.

## The state persists

After a boot that ended in this state, a warm reboot and a quick power-off (charger connected, back on within a minute) both carry it forward. The next boot fails by itself about two seconds after the main system starts (Plymouth re-attaching to DRM), with the firmware having lit the panel normally at the unlock prompt and no keyboard involved (verified with the disk password typed on an external USB keyboard):

```
xe … *ERROR* AUX B/DDI B/PHY B: Failed to write aux backlight level: -110
xe … vblank wait timed out on crtc 1
xe … *ERROR* [CRTC:270:pipe B] flip_done timed out
xe … pipe_off wait timed out
xe … *ERROR* Failed to bring PHY B to idle.
xe … PHY B failed to change powerdown state
```

It is cleared by a full power reset (shutdown, charger unplugged, power button held ~15 s, a minute off) and by loading firmware setup defaults. After either, the same kernel and parameters boot clean and eDP-2 disable/enable cycles work again.

## Ruled out

`xe.enable_dc=0`, `xe.enable_panel_replay=0` (needed for an unrelated boot hang with a burst of "Timed out waiting for PSR Idle for re-enable" on pipe A; no effect on this), `video=eDP-2:d` to keep the kernel off the connector during boot, AC vs battery, BIOS version, package changes.

## Attachments

- `dmesg-failing-boot-docked-at-poweron.txt`: docked power-on, undock at 83.8 s, failure at 85.8 s.
- `dmesg-clean-boot-keyboard-off-at-poweron.txt`: keyboard off at power-on after a healthy boot, undock at 112.4 s, no display messages.

Happy to test patches or provide a `drm.debug=0x1e` log of a wedged boot or of the failing enable.
