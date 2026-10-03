#!/usr/bin/env bash
# ASUS Zenbook Duo UX8407AA on Omarchy: install the hardware fixes in this
# package. Safe to re-run; it asks before appending anything to your Hyprland
# config. See README.md for what each piece does.
#
# Run as your normal user (root steps use pkexec, which pops up Omarchy's
# password dialog):   bash setup.sh
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"

echo "==> Installing script dependencies (brightnessctl, inotify-tools, iio-sensor-proxy, jq)"
pkexec pacman -S --needed --noconfirm brightnessctl inotify-tools iio-sensor-proxy libarchive jq

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
install -D -m 0755 "$HERE/scripts/zenbook-duo-osk" \
  "$HOME/.config/zenbook/zenbook-duo-osk"

echo "==> On-screen keyboard (Rust): building keyboard/, adding its bar button"
# keyboard/mise.toml pins the toolchain for mise users; any stable cargo works.
if command -v cargo >/dev/null; then
  if (cd "$HERE/keyboard" && cargo build --release --locked); then
    install -D -m 0755 "$HERE/keyboard/target/release/zenbook-duo-keyboard" \
      "$HOME/.config/zenbook/zenbook-duo-keyboard"
    mkdir -p "$HOME/.config/omarchy/plugins"
    ln -sfn "$HERE/omarchy-plugin" \
      "$HOME/.config/omarchy/plugins/io.github.scrambletools.zenbook-duo-keyboard"
    omarchy bar put io.github.scrambletools.zenbook-duo-keyboard
    # A running shell can keep an edited plugin's old code; restart to load it.
    omarchy restart shell >/dev/null 2>&1 || true
  else
    echo "    build failed; the on-screen keyboard is not installed (see the cargo output above)"
  fi
else
  echo "    cargo not found; install Rust (pacman -S rust, or mise use -g rust@stable) and re-run"
fi

echo "==> Sensors: ASUS sensor-hub firmware (auto-rotation and auto-brightness)"
bash "$HERE/scripts/zenbook-duo-sensor-firmware" || echo "    sensor firmware failed; auto-rotation will stay off"

echo "==> Audio: ghost-RT722 DKMS overlay (skips itself on fixed kernels)"
pkexec bash "$HERE/audio/install-audio-fix.sh"

echo "==> Hyprland config: Zenbook Duo blocks for ~/.config/hypr/ (asks before touching each file)"
# Each block lives between marker comments. A missing block is appended (at
# the end, which also keeps the eDP rules after Omarchy's catch-all monitor
# rule, so they win); a block between markers that differs from hypr/ is
# replaced in place. A block merged by hand without markers is left alone,
# with a note if it lacks something the current version needs.
MARK_BEGIN="-- >>> zenbook-duo-omarchy >>>"
MARK_END="-- <<< zenbook-duo-omarchy <<<"
# A line identifying a hand-merged block, and one the current block contains.
declare -A KEY_LINE=(
  [monitors]='output = "eDP-2"'
  [input]='rayd0002:00-2386:8c06'
  [autostart]='zenbook-duo-screen-watch'
  [bindings]='zenbook-duo-auto-brightness reset'
)
declare -A CURRENT=(
  [monitors]='osk.pid'
  [input]='hide_on_touch'
  [autostart]='zenbook-duo-auto-brightness'
  [bindings]='zenbook-duo-osk'
)
ask() {
  local answer
  if ! read -r -p "$1 [y/N] " answer </dev/tty 2>/dev/null; then
    echo "    (no terminal to ask on)"
    return 1
  fi
  [[ $answer == [yY]* ]]
}
skipped=()
for f in monitors input autostart bindings; do
  src="$HERE/hypr/$f.lua"
  dst="$HOME/.config/hypr/$f.lua"
  if [[ -f $dst ]] && grep -qxF -e "$MARK_BEGIN" "$dst"; then
    current=$(awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==e{inside=0} inside{print} $0==b{inside=1}' "$dst")
    if [[ $current == "$(cat "$src")" ]]; then
      echo "    $f.lua: Zenbook Duo block up to date"
      continue
    fi
    echo
    echo "----- changes to the Zenbook Duo block in $dst -----"
    diff <(printf '%s\n' "$current") "$src" || true
    echo "-----"
    if ask "Replace the block in $dst?"; then
      tmp=$(mktemp)
      awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v src="$src" '
        $0==b { print; while ((getline line < src) > 0) print line; skip=1; next }
        $0==e { skip=0 }
        !skip' "$dst" >"$tmp" && cat "$tmp" >"$dst"
      rm -f "$tmp"
      echo "    replaced"
    else
      skipped+=("$f")
    fi
    continue
  fi
  if [[ -f $dst ]] && grep -qF "${KEY_LINE[$f]}" "$dst"; then
    if grep -qF "${CURRENT[$f]}" "$dst"; then
      echo "    $f.lua: Zenbook Duo settings merged by hand, current"
    else
      echo "    $f.lua: Zenbook Duo settings merged by hand, but older than hypr/$f.lua; merge it by hand"
      skipped+=("$f")
    fi
    continue
  fi
  echo
  echo "----- to append to $dst -----"
  cat "$src"
  echo "-----"
  if ask "Append this block to $dst?"; then
    mkdir -p "$(dirname "$dst")"
    { [[ -s $dst ]] && printf '\n'; printf '%s\n' "$MARK_BEGIN"; cat "$src"; printf '%s\n' "$MARK_END"; } >>"$dst"
    echo "    appended"
  else
    skipped+=("$f")
  fi
done
hyprctl reload >/dev/null 2>&1 || true

echo
echo "Done. Power off, lift the keyboard off the laptop, and power on (README section 7)."
echo "Verification steps are in README section 14."
if (( ${#skipped[@]} )); then
  echo "Hyprland blocks not installed or not current, to merge by hand from hypr/: ${skipped[*]}"
fi
