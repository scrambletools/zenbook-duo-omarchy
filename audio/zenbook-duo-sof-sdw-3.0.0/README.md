# Zenbook Duo UX8407AA SOF SoundWire DKMS overlay

Builds only the upstream `snd-soc-sof-sdw` machine driver with one
board-scoped workaround: on an ASUS UX8407AA, discard the firmware-described
RT722 endpoint (manufacturer `0x025d`, part `0x0722`) when the SoundWire core
reports that peripheral as `SDW_SLAVE_UNATTACHED`. Without it the driver
builds a DAI link for a codec that is not fitted and the whole card fails to
probe.

Adapted from [burakgon/asus-expertbook-linux](https://github.com/burakgon/asus-expertbook-linux)
(same bug on the ExpertBook B9406CAA): the DMI match was changed to
`UX8407AA`, and `LLVM=1` was dropped from `dkms.conf` because the stock Arch
kernel is GCC-built.

The driver sources are derived from Linux `sound/soc/intel/boards/` and
remain GPL-2.0-only; header copies keep their original SPDX and copyright
notices. `../install-audio-fix.sh` registers this tree with DKMS, which
rebuilds the module whenever a kernel package is installed. Unnecessary on
kernels that carry the upstream `ghost_realtek` DMI quirk for this board
(expected in Linux 7.2+); the install script detects those and does nothing.
