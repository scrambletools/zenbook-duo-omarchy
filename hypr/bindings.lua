-- Super + display-brightness-down (F5): drop the auto-brightness offset learned from manual changes.
o.bind("SUPER + XF86MonBrightnessDown", "Auto-brightness: back to default curve", os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-auto-brightness reset")
