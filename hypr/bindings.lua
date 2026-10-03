-- Super + display-brightness-down (F5): drop the auto-brightness offset learned from manual changes.
o.bind("SUPER + XF86MonBrightnessDown", "Auto-brightness: back to default curve", os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-auto-brightness reset")
-- On-screen keyboard and touchpad on the bottom screen (toggle).
o.bind("SUPER + CTRL + K", "On-screen keyboard", os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-osk toggle")
