-- Zenbook Duo: the top panel is mounted upside down. The kernel rotates it
-- (video=eDP-1:panel_orientation=upside_down, see boot/) and Hyprland picks
-- that up, so the transforms below are relative to that already-upright
-- picture; without the kernel parameter you would need transform = 2 on
-- eDP-1 instead. The bottom panel sits physically below the top one.
-- zenbook-duo-screen-watch disables eDP-2 while the pogo-pin keyboard is docked.
--
-- Auto-rotation: zenbook-duo-rotate-watch writes the device orientation
-- (normal, bottom-up, left-up, right-up, as iio-sensor-proxy names it, or
-- sharing when the hinge is opened flat) to
-- ~/.local/state/zenbook/rotation and reloads Hyprland. Reading it here
-- keeps the layout across every reload, including the dock watcher's.
-- Keep these after Omarchy's catch-all hl.monitor({ output = "" ... }) rule.
local zenbook_duo_scale = omarchy_monitor_scale or 2
local zenbook_h = math.floor(1800 / zenbook_duo_scale) -- panel height; also the width once rotated
local zenbook_orientation = "normal"
local zenbook_state = io.open(os.getenv("HOME") .. "/.local/state/zenbook/rotation", "r")
if zenbook_state then
  zenbook_orientation = (zenbook_state:read("*l") or "normal"):match("^%s*(.-)%s*$")
  zenbook_state:close()
end
-- { eDP-1 (top) transform, position, eDP-2 (bottom) transform, position }
-- "sharing" (opened flat, from the hinge sensor) turns only the top panel
-- around, so someone across the table can read it.
local zenbook_layouts = {
  ["normal"]    = { 0, "0x0", 0, "0x" .. zenbook_h },
  ["bottom-up"] = { 2, "0x" .. zenbook_h, 2, "0x0" },
  ["left-up"]   = { 1, zenbook_h .. "x0", 1, "0x0" },
  ["right-up"]  = { 3, "0x0", 3, zenbook_h .. "x0" },
  ["sharing"]   = { 2, "0x0", 0, "0x" .. zenbook_h },
}
local zenbook_layout = zenbook_layouts[zenbook_orientation] or zenbook_layouts["normal"]
-- Globals so input.lua (loaded after this file) can rotate each touchscreen to match.
zenbook_duo_transform_top, zenbook_duo_transform_bottom = zenbook_layout[1], zenbook_layout[3]
hl.monitor({ output = "eDP-1", mode = "preferred", position = zenbook_layout[2], scale = zenbook_duo_scale, transform = zenbook_layout[1] })
hl.monitor({ output = "eDP-2", mode = "preferred", position = zenbook_layout[4], scale = zenbook_duo_scale, transform = zenbook_layout[3] })
