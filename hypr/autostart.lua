-- Zenbook Duo: toggle the bottom screen when the pogo-pin keyboard docks/undocks.
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-screen-watch")
-- Zenbook Duo: keep the bottom panel's brightness in sync with the top panel.
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-brightness-sync")
