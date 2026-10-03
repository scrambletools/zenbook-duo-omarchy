//! Touchpad output: a zwlr virtual pointer on its own Wayland connection,
//! fed from a channel so the UI thread never blocks on it.

use std::sync::mpsc::{self, Sender};
use std::time::Instant;

use wayland_client::globals::{GlobalListContents, registry_queue_init};
use wayland_client::protocol::{wl_pointer, wl_registry};
use wayland_client::{Connection, Dispatch, QueueHandle};
use wayland_protocols_wlr::virtual_pointer::v1::client::{
    zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
};

/// Linux input button codes.
pub const BTN_LEFT: u32 = 0x110;
pub const BTN_RIGHT: u32 = 0x111;

#[derive(Debug, Clone, Copy)]
pub enum PointerCmd {
    Motion(f32, f32),
    Scroll(f32),
    Click(u32),
}

struct State;

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwlrVirtualPointerManagerV1, ()> for State {
    fn event(_: &mut Self, _: &ZwlrVirtualPointerManagerV1, _: <ZwlrVirtualPointerManagerV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwlrVirtualPointerV1, ()> for State {
    fn event(_: &mut Self, _: &ZwlrVirtualPointerV1, _: <ZwlrVirtualPointerV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

/// Start the pointer thread. If the compositor has no virtual-pointer
/// support, the touchpad simply does nothing.
pub fn spawn() -> Sender<PointerCmd> {
    let (tx, rx) = mpsc::channel::<PointerCmd>();
    std::thread::spawn(move || {
        let Ok(conn) = Connection::connect_to_env() else { return };
        let Ok((globals, queue)) = registry_queue_init::<State>(&conn) else { return };
        let qh = queue.handle();
        let Ok(manager) = globals.bind::<ZwlrVirtualPointerManagerV1, _, _>(&qh, 1..=2, ()) else { return };
        let ptr = manager.create_virtual_pointer(None, &qh, ());
        let start = Instant::now();
        let now = || start.elapsed().as_millis() as u32;
        for cmd in rx {
            match cmd {
                PointerCmd::Motion(dx, dy) => ptr.motion(now(), dx as f64, dy as f64),
                PointerCmd::Scroll(dy) => {
                    ptr.axis_source(wl_pointer::AxisSource::Finger);
                    ptr.axis(now(), wl_pointer::Axis::VerticalScroll, dy as f64);
                }
                PointerCmd::Click(button) => {
                    ptr.button(now(), button, wl_pointer::ButtonState::Pressed);
                    ptr.frame();
                    ptr.button(now(), button, wl_pointer::ButtonState::Released);
                }
            }
            ptr.frame();
            if conn.flush().is_err() {
                return;
            }
        }
    });
    tx
}
