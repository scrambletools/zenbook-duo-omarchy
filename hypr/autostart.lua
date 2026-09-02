-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Zenbook Duo: toggle bottom screen when the pogo-pin keyboard docks/undocks.
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-screen-watch")
-- Zenbook Duo: keep bottom panel brightness in sync with the top panel.
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-brightness-sync")
