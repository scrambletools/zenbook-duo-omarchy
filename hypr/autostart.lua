-- Zenbook Duo: toggle the bottom screen when the pogo-pin keyboard docks/undocks.
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-screen-watch")
-- Zenbook Duo: keep the bottom panel's brightness in sync with the top panel.
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-brightness-sync")
-- Zenbook Duo: rotate both screens with the device (needs iio-sensor-proxy and the
-- ASUS sensor-hub firmware from scripts/zenbook-duo-sensor-firmware).
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-rotate-watch")
-- Zenbook Duo: screen brightness follows the ambient light sensor (same firmware).
o.launch_on_start(os.getenv("HOME") .. "/.config/zenbook/zenbook-duo-auto-brightness")
