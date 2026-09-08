#!/usr/bin/env bash
# ASUS Zenbook Duo UX8407AA on Omarchy: install the hardware fixes in this
# package. Safe to re-run; it asks before appending anything to your Hyprland
# config. See README.md for what each piece does.
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

echo "==> Hyprland config: Zenbook Duo blocks for ~/.config/hypr/ (asks before touching each file)"
# Each block is appended once, between marker comments. A file that already
# has the block (marker or the block's key line, from an earlier manual merge)
# is left alone. Appending at the end also keeps the eDP rules after Omarchy's
# catch-all monitor rule, so they win.
MARK_BEGIN="-- >>> zenbook-duo-omarchy >>>"
MARK_END="-- <<< zenbook-duo-omarchy <<<"
declare -A KEY_LINE=(
  [monitors]='output = "eDP-2"'
  [input]='rayd0002:00-2386:8c06'
  [autostart]='zenbook-duo-screen-watch'
)
skipped=()
for f in monitors input autostart; do
  src="$HERE/hypr/$f.lua"
  dst="$HOME/.config/hypr/$f.lua"
  if [[ -f $dst ]] && grep -qF -e "$MARK_BEGIN" -e "${KEY_LINE[$f]}" "$dst"; then
    echo "    $f.lua already has the Zenbook Duo block, leaving it alone"
    continue
  fi
  echo
  echo "----- to append to $dst -----"
  cat "$src"
  echo "-----"
  if ! read -r -p "Append this block to $dst? [y/N] " answer </dev/tty 2>/dev/null; then
    echo "    (no terminal to ask on)"
    skipped+=("$f"); continue
  fi
  if [[ $answer == [yY]* ]]; then
    mkdir -p "$(dirname "$dst")"
    { [[ -s $dst ]] && printf '\n'; printf '%s\n' "$MARK_BEGIN"; cat "$src"; printf '%s\n' "$MARK_END"; } >>"$dst"
    echo "    appended"
  else
    echo "    skipped"
    skipped+=("$f")
  fi
done

echo
echo "Done. Power off, lift the keyboard off the laptop, and power on (README section 2a)."
echo "Verification steps are in README section 8."
if (( ${#skipped[@]} )); then
  echo "Skipped Hyprland blocks, to merge by hand from hypr/: ${skipped[*]}"
fi
