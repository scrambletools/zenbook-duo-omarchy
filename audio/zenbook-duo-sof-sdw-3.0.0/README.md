# B9406CAA SOF SoundWire DKMS overlay

This builds only the upstream `snd-soc-sof-sdw` machine driver and adds one
board-scoped workaround: on an ASUS B9406CAA, discard the firmware-described
RT722 endpoint when the SoundWire core reports that exact peripheral as
`SDW_SLAVE_UNATTACHED`.

The driver sources are derived from Linux `sound/soc/intel/boards/` at the
Linux 7.2 API level and remain GPL-2.0-only. Header copies retain their
original SPDX and copyright notices. `module.sh` registers this tree with
DKMS, which rebuilds the overlay whenever a kernel package is installed.
