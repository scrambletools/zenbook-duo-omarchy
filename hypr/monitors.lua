-- Zenbook Duo: the top panel is mounted upside down. The kernel rotates it
-- (video=eDP-1:panel_orientation=upside_down, see boot/) and Hyprland picks
-- that up, so no transform here; without the kernel parameter you would need
-- transform = 2 on eDP-1 instead. The bottom panel sits physically below the
-- top one (logical size 1440x900 at scale 2). zenbook-duo-screen-watch
-- disables eDP-2 while the pogo-pin keyboard is docked.
-- Keep these after Omarchy's catch-all hl.monitor({ output = "" ... }) rule.
local zenbook_duo_scale = omarchy_monitor_scale or 2
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = zenbook_duo_scale })
hl.monitor({ output = "eDP-2", mode = "preferred", position = "0x900", scale = zenbook_duo_scale })
