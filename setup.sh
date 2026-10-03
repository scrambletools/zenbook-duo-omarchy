#!/usr/bin/env bash
# ASUS Zenbook Duo UX8407AA on Omarchy: install the hardware fixes in this
# package. Safe to re-run; it asks before appending anything to your Hyprland
# config. See README.md for what each piece does.
#
# Run as your normal user (root steps use pkexec, which pops up Omarchy's
# password dialog):   bash setup.sh
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"

echo "==> Installing script dependencies (brightnessctl, inotify-tools, iio-sensor-proxy)"
pkexec pacman -S --needed --noconfirm brightnessctl inotify-tools iio-sensor-proxy libarchive

echo "==> Keyboard: hid-asus rebind and the Fn-key bridge (section 8)"
# The rm cleans up an older version of this package, which also shipped an
# F-key remap (hwdb) and a hidraw backlight tool; hid-asus makes both redundant.
pkexec bash -c "rm -f /etc/udev/hwdb.d/61-zenbook-duo-keyboard.hwdb \
    /etc/udev/rules.d/70-zenbook-kbd-backlight.rules && \
  install -D -m 0644 '$HERE/udev/61-zenbook-duo-keyboard.rules' \
  /etc/udev/rules.d/61-zenbook-duo-keyboard.rules && \
  install -D -m 0755 '$HERE/scripts/zenbook-duo-hid-asus' /usr/local/bin/zenbook-duo-hid-asus && \
  install -D -m 0755 '$HERE/scripts/zenbook-duo-fnkeys' /usr/local/bin/zenbook-duo-fnkeys && \
  install -D -m 0644 '$HERE/udev/zenbook-duo-fnkeys.service' /etc/systemd/system/zenbook-duo-fnkeys.service && \
  systemd-hwdb update && udevadm control --reload && systemctl daemon-reload && \
  systemctl enable --now zenbook-duo-fnkeys.service"
rm -f "$HOME/.config/zenbook/zenbook-duo-kbd-backlight" "$HOME/.config/zenbook/kbd-backlight-level"

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
install -D -m 0755 "$HERE/scripts/zenbook-duo-rotate-watch" \
  "$HOME/.config/zenbook/zenbook-duo-rotate-watch"
install -D -m 0755 "$HERE/scripts/zenbook-duo-auto-brightness" \
  "$HOME/.config/zenbook/zenbook-duo-auto-brightness"

echo "==> On-screen keyboard (Rust): building keyboard/, adding its bar button"
if command -v cargo >/dev/null; then
  (cd "$HERE/keyboard" && cargo build --release --locked) &&
    install -D -m 0755 "$HERE/keyboard/target/release/zenbook-duo-keyboard" \
      "$HOME/.config/zenbook/zenbook-duo-keyboard" &&
    mkdir -p "$HOME/.config/omarchy/plugins" &&
    ln -sfn "$HERE/omarchy-plugin" \
      "$HOME/.config/omarchy/plugins/io.github.scrambletools.zenbook-duo-keyboard" &&
    omarchy bar put io.github.scrambletools.zenbook-duo-keyboard
else
  echo "    cargo not found; install Rust (e.g. mise use rust@stable) and re-run to get it"
fi

echo "==> Sensors: ASUS sensor-hub firmware (auto-rotation and auto-brightness)"
bash "$HERE/scripts/zenbook-duo-sensor-firmware" || echo "    sensor firmware failed; auto-rotation will stay off"

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
  [bindings]='zenbook-duo-auto-brightness reset'
)
skipped=()
for f in monitors input autostart bindings; do
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
echo "Done. Power off, lift the keyboard off the laptop, and power on (README section 7)."
echo "Verification steps are in README section 14."
if (( ${#skipped[@]} )); then
  echo "Skipped Hyprland blocks, to merge by hand from hypr/: ${skipped[*]}"
fi
