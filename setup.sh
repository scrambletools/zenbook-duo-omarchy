#!/usr/bin/env bash
# ASUS Zenbook Duo UX8407AA on Omarchy: install the hardware fixes in this
# package. Safe to re-run. See README.md for what each piece does.
#
# Run as your normal user (root steps use pkexec, which pops up Omarchy's
# password dialog):   bash setup.sh
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"

echo "==> Installing script dependencies (brightnessctl, inotify-tools)"
pkexec pacman -S --needed --noconfirm brightnessctl inotify-tools

echo "==> Keyboard: Fn-key remap (hwdb), and hid-asus for the keyboard backlight"
pkexec bash -c "install -D -m 0644 '$HERE/udev/61-zenbook-duo-keyboard.hwdb' \
  /etc/udev/hwdb.d/61-zenbook-duo-keyboard.hwdb && \
  install -D -m 0644 '$HERE/udev/61-zenbook-duo-keyboard.rules' \
  /etc/udev/rules.d/61-zenbook-duo-keyboard.rules && \
  install -D -m 0755 '$HERE/scripts/zenbook-duo-hid-asus' /usr/local/bin/zenbook-duo-hid-asus && \
  install -D -m 0755 '$HERE/scripts/zenbook-duo-fnkeys' /usr/local/bin/zenbook-duo-fnkeys && \
  install -D -m 0644 '$HERE/udev/zenbook-duo-fnkeys.service' /etc/systemd/system/zenbook-duo-fnkeys.service && \
  systemd-hwdb update && udevadm control --reload && systemctl daemon-reload && \
  systemctl enable --now zenbook-duo-fnkeys.service"

echo "==> Touchscreen: blacklisting raydium_i2c_ts (also fixes shutdown hang)"
pkexec install -D -m 0644 "$HERE/touchscreen/zenbook-duo-touchscreen.conf" \
  /etc/modprobe.d/zenbook-duo-touchscreen.conf

echo "==> Boot: kernel parameters (panel orientation, DPCD backlight, Panel Replay off)"
pkexec bash -c "install -D -m 0644 '$HERE/boot/zenbook-duo-panel-orientation.conf' \
  /etc/limine-entry-tool.d/zenbook-duo-panel-orientation.conf && \
  install -D -m 0644 '$HERE/boot/zenbook-duo-dpcd-backlight.conf' \
  /etc/limine-entry-tool.d/zenbook-duo-dpcd-backlight.conf && \
  install -D -m 0644 '$HERE/boot/zenbook-duo-panel-replay.conf' \
  /etc/limine-entry-tool.d/zenbook-duo-panel-replay.conf && limine-update"

echo "==> Helper scripts -> ~/.config/zenbook/"
install -D -m 0755 "$HERE/scripts/zenbook-duo-screen-watch" \
  "$HOME/.config/zenbook/zenbook-duo-screen-watch"
install -D -m 0755 "$HERE/scripts/zenbook-duo-brightness-sync" \
  "$HOME/.config/zenbook/zenbook-duo-brightness-sync"
install -D -m 0755 "$HERE/scripts/zenbook-duo-keyboard-pair" \
  "$HOME/.config/zenbook/zenbook-duo-keyboard-pair"

echo "==> Audio: ghost-RT722 DKMS overlay (skips itself on fixed kernels)"
pkexec bash "$HERE/audio/install-audio-fix.sh"

cat <<'EOF'

Almost done. The Hyprland pieces are NOT copied automatically because
~/.config/hypr/*.lua are your own configs. Merge the marked "Zenbook Duo"
blocks from this package into yours:

  hypr/monitors.lua   -> ~/.config/hypr/monitors.lua   (orientation/layout)
  hypr/input.lua      -> ~/.config/hypr/input.lua      (touch->panel mapping)
  hypr/autostart.lua  -> ~/.config/hypr/autostart.lua  (start the two helpers)

(On a fresh Omarchy install you can simply copy all three files over.)

Then reboot. Verify afterwards with:
  wpctl status            # real Speaker sink, not "Dummy Output"
  hyprctl monitors        # eDP-1 transform 0 at 0x0 (kernel rotates it), eDP-2 at 0x900
  cat /proc/cmdline       # contains video=eDP-1:panel_orientation=upside_down xe.enable_dpcd_backlight=1 xe.enable_panel_replay=0
  brightnessctl set 30%   # top screen visibly dims (OLED brightness goes over DPCD)
EOF
