-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- Zenbook Duo: the top panel is mounted upside down. Its rotation is handled by
-- the kernel (video=eDP-1:panel_orientation=upside_down, see boot/), which
-- Hyprland picks up automatically, so no transform here. Without that kernel
-- parameter you would need transform = 2 on eDP-1 instead.
-- Bottom panel sits physically below the top one (logical size 1440x900 at scale 2).
-- zenbook-duo-screen-watch disables eDP-2 while the pogo-pin keyboard is docked.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })
hl.monitor({ output = "eDP-2", mode = "preferred", position = "0x900", scale = omarchy_monitor_scale })
