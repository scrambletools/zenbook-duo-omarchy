Filed as https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9196 on 2026-09-08.

Title: xe/PTL: eDP on DDI B cannot be enabled after being disabled unless the firmware lit the panel at power-on ("PHY B failed to request refclk")

## Hardware / software

- ASUS Zenbook Duo UX8407AA (2026), BIOS UX8407AA.305
- Intel Panther Lake, device ID b0a0, display version 30.00 stepping B0, DMC i915/xe3lpd_dmc.bin v2.36, GuC 70.72.1
- Two internal eDP OLED panels, both BOE NB140B9M 2880x1800: eDP-1 (DDI A / PHY A, top) and eDP-2 (DDI B / PHY B, bottom, covered by a detachable keyboard when docked)
- Kernel 7.1.9-arch1-2 (Arch), mesa 26.2.1, Hyprland 0.56.2 / aquamarine 0.14.0 (atomic modesetting)
- Command line: `xe.enable_panel_replay=0 video=eDP-1:panel_orientation=upside_down xe.enable_dpcd_backlight=1 xe.enable_psr=0` (plus the usual root/resume parameters). The failure is the same without the panel_replay and psr parameters.

## Summary

If the machine is powered on with the keyboard docked, the firmware does not light the covered bottom panel (eDP-2). The kernel still probes it (AUX and EDID work, it is reported connected, fbcon puts a framebuffer on it without errors). The compositor then disables eDP-2 at login. The first time eDP-2 is re-enabled afterwards, the C20 PHY bring-up for PHY B fails and the port is unusable for the rest of the boot:

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

From then on every atomic commit that includes pipe B waits out the 10 s flip_done timeout ("commit wait timed out", "pipe state doesn't match!", "DPLL 1: pll hw state mismatch", AUX writes to the panel return -110). The compositor stalls for the length of each timeout, and shutdown takes about a minute because fbcon restore hits the same timeouts. Disabling and re-enabling the connector again does not recover it; nor does a warm reboot, because the firmware skips the panel again while the keyboard is docked. Only a full power-off with the keyboard removed gets the panel back.

If the machine is instead powered on with the keyboard off (the firmware lights both panels at the disk-unlock prompt), the same compositor, same kernel and same dock/undock sequence work indefinitely with no display errors at all.

## Steps to reproduce

1. Power on with the detachable keyboard docked (bottom panel covered and left dark by the firmware).
2. Log into a Wayland compositor that disables eDP-2 (Hyprland `monitor = eDP-2, disable`, or `wlr-randr --output eDP-2 --off`).
3. Re-enable eDP-2 (`monitor = eDP-2, preferred, auto, 2` / `wlr-randr --output eDP-2 --on`).
4. PHY B bring-up fails as above; eDP-2 stays black, the log fills with flip_done timeouts.

Control: power on with the keyboard detached so both panels show the firmware/unlock screen, then repeat steps 2 and 3: works every time.

## Evidence

Thirteen boots on 2026-09-07, identical software:

| Keyboard at power-on | Boots | First re-enable of eDP-2 |
|---|---|---|
| docked (panel not lit by firmware) | 9, cold and warm, before and after a BIOS "load defaults" | PHY B failure every time |
| detached (panel lit by firmware) | 4 | clean, no xe messages, repeated disable/enable cycles fine |

Ruled out: warm reboot versus full power-off (both fail if docked at power-on), AC versus battery, `xe.enable_dc=0`, `xe.enable_panel_replay=0`, `xe.enable_psr=0`, BIOS version, package changes.

So the driver appears to depend on PHY B initialisation state left by the firmware. When the firmware never enabled the port, xe can drive it once at boot (fbcon on eDP-2 produces no errors) but cannot bring the PHY back after `intel_ddi_post_disable`; `intel_cx0_phy_lane_reset` fails at the first handshake ("failed to request refclk"), and nothing after that succeeds.

## Attachments

- `dmesg-failing-boot-docked-at-poweron.txt`: full kernel log of a docked power-on, undock at 83.8 s, failure at 85.8 s.
- `dmesg-clean-boot-keyboard-off-at-poweron.txt`: full kernel log of a detached power-on, undock at 112.4 s, no display messages.

Happy to test patches or collect `drm.debug=0x1e` logs and `/sys/kernel/debug/dri/0/i915_display_info` / `i915_power_domain_info` dumps from either state on request.
