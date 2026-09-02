-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Zenbook Duo: two identical internal touchscreens confuse Hyprland's
-- auto-mapping, so bind each touch device to its own panel explicitly.
-- Bottom panel touchscreen + stylus (i2c-hid, RAYD0002).
hl.device({ name = "rayd0002:00-2386:8c06", output = "eDP-2" })
hl.device({ name = "rayd0002:00-2386:8c06-stylus", output = "eDP-2" })
-- Top panel touchscreen + stylus (i2c-hid, RAYD0001; native raydium_i2c_ts
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

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
-- hl.config({
--   input = {
--     -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt.
--     kb_layout = "us,dk,eu",
--     kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
--
--     -- Use a specific keyboard variant if needed (e.g. intl for international keyboards).
--     kb_variant = "intl",
--
--     -- Change speed of keyboard repeat.
--     repeat_rate = 40,
--     repeat_delay = 250,
--
--     -- Start with numlock on by default.
--     numlock_by_default = true,
--
--     -- Increase sensitivity for mouse/trackpad (default: 0).
--     sensitivity = 0.35,
--
--     -- Turn off mouse acceleration (default: adaptive).
--     accel_profile = "flat",
--
--     touchpad = {
--       -- Use natural (inverse) scrolling.
--       natural_scroll = true,
--
--       -- Use two-finger clicks for right-click instead of lower-right corner.
--       clickfinger_behavior = true,
--
--       -- Control the speed of your scrolling.
--       scroll_factor = 0.4,
--
--       -- Enable the touchpad while typing.
--       disable_while_typing = false,
--
--       -- Left-click-and-drag with three fingers.
--       drag_3fg = 1,
--     },
--   },
-- })

-- App-specific touchpad scroll speeds.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })
