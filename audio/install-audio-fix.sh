#!/usr/bin/env bash
# Install the ghost-RT722 DKMS overlay for the ASUS Zenbook Duo UX8407AA.
# Interim fix until the Arch kernel ships the upstream soundwire DMI quirk
# (in Linus' tree for UX8407AA; expected in 7.2+).
set -euo pipefail

SRC="$(dirname "$(readlink -f "$0")")/zenbook-duo-sof-sdw-3.0.0"
NAME=zenbook-duo-sof-sdw
VER=3.0.0

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
[[ -f $SRC/dkms.conf ]] || { echo "staged source missing: $SRC" >&2; exit 1; }
grep -q UX8407AA /sys/class/dmi/id/board_name || { echo "not a UX8407AA" >&2; exit 1; }

# The upstream quirk embeds the board name in the soundwire_bus module; if the
# running kernel already has it, this overlay is unnecessary.
if modinfo -n soundwire_bus 2>/dev/null | xargs zstdcat 2>/dev/null | strings | grep -qF UX8407AA; then
  echo "Running kernel already contains the upstream UX8407AA quirk; not installing."
  exit 0
fi

pacman -S --needed --noconfirm dkms "$(</lib/modules/"$(uname -r)"/pkgbase)-headers"

# Clear any prior (failed) registration so the refreshed source is used
if dkms status -m "$NAME" -v "$VER" 2>/dev/null | grep -q .; then
  dkms remove -m "$NAME" -v "$VER" --all || true
fi
rm -rf "/usr/src/${NAME}-${VER}"
cp -a "$SRC" "/usr/src/${NAME}-${VER}"
dkms install -m "$NAME" -v "$VER"

# sof_sdw can be baked into the initramfs; regenerate so the overlay is used at boot
limine-mkinitcpio

echo
echo "Done. Reboot, then check: wpctl status   (expect a real sink, not Dummy Output)"
