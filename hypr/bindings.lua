-- Keyboard backlight keys: Omarchy's omarchy-brightness-keyboard drives the
-- asus::kbd_backlight LED, which kernel 7.2+ no longer provides for this
-- keyboard (README section 3c). Rebind to the hidraw tool.
hl.unbind("XF86KbdBrightnessUp")
hl.unbind("XF86KbdBrightnessDown")
hl.unbind("XF86KbdLightOnOff")
local zenbook_kbd = os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-kbd-backlight"
o.bind("XF86KbdBrightnessUp", "Keyboard brightness up", zenbook_kbd .. " up", { locked = true, repeating = true })
o.bind("XF86KbdBrightnessDown", "Keyboard brightness down", zenbook_kbd .. " down", { locked = true, repeating = true })
o.bind("XF86KbdLightOnOff", "Keyboard backlight cycle", zenbook_kbd .. " cycle", { locked = true })
