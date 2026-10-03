#!/usr/bin/env bash
# Install the ghost-RT722 DKMS overlay for the ASUS Zenbook Duo UX8407AA.
# Interim fix until the kernel ships the upstream soundwire DMI quirk
# (in Linus' tree for UX8407AA; still missing from Arch 7.2.3 and from
# linux-omarchy 7.2.5).
#
# The overlay is a patched copy of the kernel's own sof_sdw.c, so it must
# match the kernel it is built for:
#   3.0.0  stock Arch kernel (linux)
#   3.1.0  Omarchy kernel (linux-omarchy 7.2.5, which carries newer ASoC
#          sound patches that change the sof_sdw/soc_sdw_utils API)
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
NAME=zenbook-duo-sof-sdw
KVER="$(uname -r)"
PKGBASE="$(</lib/modules/"$KVER"/pkgbase)"
case $PKGBASE in
  linux-omarchy) VER=3.1.0 ;;
  *)             VER=3.0.0 ;;
esac
SRC="$HERE/${NAME}-${VER}"

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
[[ -f $SRC/dkms.conf ]] || { echo "staged source missing: $SRC" >&2; exit 1; }
grep -q UX8407AA /sys/class/dmi/id/board_name || { echo "not a UX8407AA" >&2; exit 1; }

# The upstream quirk embeds the board name in the soundwire_bus module; if the
# running kernel already has it, this overlay is unnecessary.
if modinfo -n soundwire_bus 2>/dev/null | xargs zstdcat 2>/dev/null | strings | grep -qF UX8407AA; then
  echo "Running kernel already contains the upstream UX8407AA quirk; not installing."
  exit 0
fi

pacman -S --needed --noconfirm dkms "${PKGBASE}-headers"

# Clear any prior (failed) registration so the refreshed source is used
if dkms status -m "$NAME" -v "$VER" 2>/dev/null | grep -q .; then
  dkms remove -m "$NAME" -v "$VER" --all || true
fi
rm -rf "/usr/src/${NAME}-${VER}"
cp -a "$SRC" "/usr/src/${NAME}-${VER}"
dkms install -m "$NAME" -v "$VER" -k "$KVER"

# sof_sdw can be baked into the initramfs; regenerate so the overlay is used at boot
limine-mkinitcpio

echo
echo "Done. Reboot, then check: wpctl status   (expect a real sink, not Dummy Output)"
