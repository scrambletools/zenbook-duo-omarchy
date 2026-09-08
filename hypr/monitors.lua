local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Zenbook Duo: the top panel is mounted upside down. The kernel rotates it
-- (video=eDP-1:panel_orientation=upside_down, see boot/) and Hyprland picks
-- that up, so no transform here; without the kernel parameter you would need
-- transform = 2 on eDP-1 instead. The bottom panel sits physically below the
-- top one (logical size 1440x900 at scale 2). zenbook-duo-screen-watch
-- disables eDP-2 while the pogo-pin keyboard is docked.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = omarchy_monitor_scale })
hl.monitor({ output = "eDP-2", mode = "preferred", position = "0x900", scale = omarchy_monitor_scale })
