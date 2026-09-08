# Firmware baseline, healthy machine, 2026-09-07

Taken with `scripts/zenbook-duo-firmware-baseline` right after the firmware
defaults reset that fixed the dark bottom panel (README section 2a), with
both panels working. Use it to diff against a snapshot taken while the
panel is misbehaving.

| File | What |
|---|---|
| `efivars-list.txt` | every UEFI variable, size and name (154 entries) |
| `asus-armoury.txt` | firmware attributes the ASUS driver exposes (only `charge_mode` on this model) |
| `AsusEDID.hex` | the firmware's stored display identification block; on this machine a copy of the **top** panel's EDID (BOE NB140B9M-T01, product 0x0d7b) |
| `edid-eDP-1.*`, `edid-eDP-2.*` | the panels' own EDIDs (top T01, bottom T02; they differ only in the model suffix and checksums) |
| `bios-version.txt`, `kernel.txt`, `cmdline.txt` | firmware UX8407AA.305 (02/10/2026), kernel 7.1.9-arch1-2, boot parameters |

Deliberately not included: the contents of the other, undocumented ASUS
variables (`AsusVariable`, `BoardInfoSetup`, `CA1x`), since what they encode
is unknown. The capture script keeps them in your local snapshot.
