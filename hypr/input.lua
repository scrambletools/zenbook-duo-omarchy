-- Zenbook Duo: two identical internal touchscreens confuse Hyprland's
-- auto-mapping, so bind each touch device to its own panel explicitly.
-- Bottom panel touchscreen + stylus (i2c-hid, RAYD0002).
hl.device({ name = "rayd0002:00-2386:8c06", output = "eDP-2" })
hl.device({ name = "rayd0002:00-2386:8c06-stylus", output = "eDP-2" })
-- Top panel touchscreen + stylus (i2c-hid, RAYD0001; the native raydium_i2c_ts
-- driver is blacklisted in /etc/modprobe.d/zenbook-duo-touchscreen.conf).
hl.device({ name = "rayd0001:00-2386:8c05", output = "eDP-1" })
hl.device({ name = "rayd0001:00-2386:8c05-stylus", output = "eDP-1" })

-- Zenbook Duo: the kernel rotates eDP-1 (video=eDP-1:panel_orientation=upside_down).
-- Hyprland rotates the rendered frame but places the hardware cursor plane in
-- unrotated coordinates, so the pointer moves mirrored on the top panel.
-- Software cursors are composited into the frame and rotate with it.
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})
