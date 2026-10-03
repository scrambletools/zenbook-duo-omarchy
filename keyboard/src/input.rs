//! Output side: one Wayland connection holding a virtual keyboard
//! (zwp_virtual_keyboard_v1) and a virtual pointer (zwlr_virtual_pointer_v1),
//! fed from a channel so the UI thread never blocks on it.
//!
//! The keyboard gets a standard US keymap once, at start, and every key is
//! sent on its real evdev code (Shift held for shifted characters), exactly
//! like a physical keyboard. That matters: Hyprland matches its key bindings
//! against those codes, so made-up codes would trigger the wrong bindings.

use std::io::Write;
use std::os::fd::AsFd;
use std::sync::mpsc::{self, Sender};
use std::time::Instant;

use wayland_client::globals::{GlobalListContents, registry_queue_init};
use wayland_client::protocol::{wl_keyboard, wl_output, wl_pointer, wl_registry, wl_seat};
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols_misc::zwp_virtual_keyboard_v1::client::{
    zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1, zwp_virtual_keyboard_v1::ZwpVirtualKeyboardV1,
};
use wayland_protocols_wlr::virtual_pointer::v1::client::{
    zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
};

/// Linux input button codes.
pub const BTN_LEFT: u32 = 0x110;
pub const BTN_RIGHT: u32 = 0x111;

/// XKB modifier masks (real modifiers of the "complete" compat set).
pub const MOD_SHIFT: u32 = 1;
pub const MOD_CTRL: u32 = 4;
pub const MOD_ALT: u32 = 8;
pub const MOD_SUPER: u32 = 64;

#[derive(Debug, Clone, Copy)]
pub enum InputCmd {
    /// Tap the key carrying `keysym`, with these modifiers held.
    Key { keysym: &'static str, mods: u32 },
    /// A touchpad gesture begins: pick up where the cursor is now.
    PadStart,
    Motion(f32, f32),
    Scroll(f32),
    Click(u32),
}

/// evdev code of the key carrying `keysym` in a standard US layout.
fn evdev_code(keysym: &str) -> Option<u32> {
    const LETTERS: &[(&str, u32)] = &[
        ("q", 16), ("w", 17), ("e", 18), ("r", 19), ("t", 20), ("y", 21), ("u", 22), ("i", 23), ("o", 24),
        ("p", 25), ("a", 30), ("s", 31), ("d", 32), ("f", 33), ("g", 34), ("h", 35), ("j", 36), ("k", 37),
        ("l", 38), ("z", 44), ("x", 45), ("c", 46), ("v", 47), ("b", 48), ("n", 49), ("m", 50),
    ];
    if let Some((_, code)) = LETTERS.iter().find(|(l, _)| *l == keysym) {
        return Some(*code);
    }
    Some(match keysym {
        "1" => 2, "2" => 3, "3" => 4, "4" => 5, "5" => 6, "6" => 7, "7" => 8, "8" => 9, "9" => 10, "0" => 11,
        "minus" => 12, "equal" => 13, "BackSpace" => 14, "Tab" => 15, "bracketleft" => 26,
        "bracketright" => 27, "Return" => 28, "semicolon" => 39, "apostrophe" => 40, "grave" => 41,
        "backslash" => 43, "comma" => 51, "period" => 52, "slash" => 53, "space" => 57, "Escape" => 1,
        "F1" => 59, "F2" => 60, "F3" => 61, "F4" => 62, "F5" => 63, "F6" => 64, "F7" => 65, "F8" => 66,
        "F9" => 67, "F10" => 68, "F11" => 87, "F12" => 88, "F23" => 193, "Print" => 99,
        "Home" => 102, "Up" => 103, "Prior" => 104, "Left" => 105, "Right" => 106, "End" => 107,
        "Down" => 108, "Next" => 109, "Insert" => 110, "Delete" => 111,
        "XF86AudioMute" => 113, "XF86AudioLowerVolume" => 114, "XF86AudioRaiseVolume" => 115,
        "XF86MonBrightnessDown" => 224, "XF86MonBrightnessUp" => 225, "XF86Display" => 227,
        "XF86KbdLightOnOff" => 228, "XF86AudioMicMute" => 248,
        _ => return None,
    })
}

/// Base keysym and Shift for typing `c` (used by the --type test hook).
pub fn char_key(c: char) -> (&'static str, u32) {
    const SHIFTED: &[(char, &str)] = &[
        ('~', "grave"), ('!', "1"), ('@', "2"), ('#', "3"), ('$', "4"), ('%', "5"), ('^', "6"), ('&', "7"),
        ('*', "8"), ('(', "9"), (')', "0"), ('_', "minus"), ('+', "equal"), ('{', "bracketleft"),
        ('}', "bracketright"), ('|', "backslash"), (':', "semicolon"), ('"', "apostrophe"), ('<', "comma"),
        ('>', "period"), ('?', "slash"),
    ];
    const PLAIN: &[(char, &str)] = &[
        ('`', "grave"), ('-', "minus"), ('=', "equal"), ('[', "bracketleft"), (']', "bracketright"),
        ('\\', "backslash"), (';', "semicolon"), ('\'', "apostrophe"), (',', "comma"), ('.', "period"),
        ('/', "slash"), (' ', "space"), ('\n', "Return"), ('1', "1"), ('2', "2"), ('3', "3"), ('4', "4"),
        ('5', "5"), ('6', "6"), ('7', "7"), ('8', "8"), ('9', "9"), ('0', "0"),
    ];
    if let Some((_, s)) = SHIFTED.iter().find(|(x, _)| *x == c) {
        return (s, MOD_SHIFT);
    }
    if let Some((_, s)) = PLAIN.iter().find(|(x, _)| *x == c) {
        return (s, 0);
    }
    const LOWER: &str = "abcdefghijklmnopqrstuvwxyz";
    let lower = c.to_ascii_lowercase();
    match LOWER.find(lower) {
        Some(i) => (&LOWER[i..i + 1], if c.is_ascii_uppercase() { MOD_SHIFT } else { 0 }),
        None => ("space", 0),
    }
}

const KEYMAP: &str = "xkb_keymap {\n\
    xkb_keycodes { include \"evdev+aliases(qwerty)\" };\n\
    xkb_types { include \"complete\" };\n\
    xkb_compat { include \"complete\" };\n\
    xkb_symbols { include \"pc+us+inet(evdev)\" };\n\
};\n";

/// The keymap has to be passed as a file descriptor.
fn keymap_file() -> std::io::Result<(std::fs::File, u32)> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into());
    let path = std::path::Path::new(&dir).join(format!("zenbook-duo-keyboard-{}.xkb", std::process::id()));
    let mut f = std::fs::OpenOptions::new().read(true).write(true).create(true).truncate(true).open(&path)?;
    let _ = std::fs::remove_file(&path);
    let mut text = KEYMAP.as_bytes().to_vec();
    text.push(0);
    f.write_all(&text)?;
    f.flush()?;
    Ok((f, text.len() as u32))
}

/// The touchpad keeps the cursor on this output: while the on-screen
/// keyboard is up, the bottom screen is all keyboard.
const POINTER_OUTPUT: &str = "eDP-1";

#[derive(Default)]
struct State {
    outputs: Vec<(wl_output::WlOutput, String)>,
}

impl Dispatch<wl_output::WlOutput, ()> for State {
    fn event(state: &mut Self, output: &wl_output::WlOutput, event: wl_output::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let wl_output::Event::Name { name } = event {
            state.outputs.push((output.clone(), name));
        }
    }
}

/// Cursor position and size of POINTER_OUTPUT, in its own logical pixels,
/// from Hyprland. The cursor is pulled onto the output if it is elsewhere.
fn cursor_on_output() -> Option<(f64, f64, f64, f64)> {
    let run = |args: &[&str]| {
        std::process::Command::new("hyprctl").args(args).output().ok().map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
    };
    let pos = run(&["cursorpos"])?;
    let (cx, cy) = pos.trim().split_once(", ")?;
    let (cx, cy): (f64, f64) = (cx.parse().ok()?, cy.parse().ok()?);
    // `hyprctl monitors` text: "Monitor eDP-1 (ID 0):" then "<w>x<h>@<hz> at <x>x<y>",
    // and "scale:"/"transform:" lines.
    let text = run(&["monitors"])?;
    let block = text.split("Monitor ").find(|b| b.starts_with(&format!("{POINTER_OUTPUT} ")))?;
    let mut lines = block.lines().skip(1);
    let geo = lines.next()?.trim();
    let (mode, at) = geo.split_once(" at ")?;
    let (w, rest) = mode.split_once('x')?;
    let h = rest.split('@').next()?;
    let (x, y) = at.split_once('x')?;
    let field = |key: &str| block.lines().find_map(|l| l.trim().strip_prefix(key).map(|v| v.trim().to_string()));
    let scale: f64 = field("scale:")?.parse().ok()?;
    let transform: u32 = field("transform:")?.parse().ok()?;
    let (mut lw, mut lh) = (w.parse::<f64>().ok()? / scale, h.parse::<f64>().ok()? / scale);
    if transform % 2 == 1 {
        std::mem::swap(&mut lw, &mut lh);
    }
    let (ox, oy): (f64, f64) = (x.parse().ok()?, y.parse().ok()?);
    Some(((cx - ox).clamp(0.0, lw - 1.0), (cy - oy).clamp(0.0, lh - 1.0), lw, lh))
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<wl_seat::WlSeat, ()> for State {
    fn event(_: &mut Self, _: &wl_seat::WlSeat, _: wl_seat::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
macro_rules! ignore_events {
    ($($t:ty),*) => {$(
        impl Dispatch<$t, ()> for State {
            fn event(_: &mut Self, _: &$t, _: <$t as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
        }
    )*};
}
ignore_events!(ZwlrVirtualPointerManagerV1, ZwlrVirtualPointerV1, ZwpVirtualKeyboardManagerV1, ZwpVirtualKeyboardV1);

/// Start the input thread. Without compositor support for a protocol, the
/// matching commands are dropped.
pub fn spawn() -> Sender<InputCmd> {
    let (tx, rx) = mpsc::channel::<InputCmd>();
    std::thread::spawn(move || {
        let Ok(conn) = Connection::connect_to_env() else { return };
        let Ok((globals, mut queue)) = registry_queue_init::<State>(&conn) else { return };
        let qh = queue.handle();
        let Ok(seat) = globals.bind::<wl_seat::WlSeat, _, _>(&qh, 1..=7, ()) else { return };

        let mut state = State::default();
        for g in globals.contents().clone_list() {
            if g.interface == "wl_output" {
                globals.registry().bind::<wl_output::WlOutput, _, _>(g.name, g.version.min(4), &qh, ());
            }
        }
        let _ = queue.roundtrip(&mut state);
        let output = state.outputs.iter().find(|(_, n)| n == POINTER_OUTPUT).map(|(o, _)| o.clone());
        let pointer = globals.bind::<ZwlrVirtualPointerManagerV1, _, _>(&qh, 1..=2, ()).ok().map(|m| match &output {
            Some(o) if m.version() >= 2 => m.create_virtual_pointer_with_output(Some(&seat), Some(o), &qh, ()),
            _ => m.create_virtual_pointer(Some(&seat), &qh, ()),
        });
        // Touchpad position on POINTER_OUTPUT: x, y, width, height.
        let mut pad: Option<(f64, f64, f64, f64)> = None;

        // Keep the keymap file alive as long as the keyboard.
        let mut _keymap = None;
        let keyboard = globals.bind::<ZwpVirtualKeyboardManagerV1, _, _>(&qh, 1..=1, ()).ok().and_then(|m| {
            let (file, size) = keymap_file().ok()?;
            let kb = m.create_virtual_keyboard(&seat, &qh, ());
            kb.keymap(wl_keyboard::KeymapFormat::XkbV1.into(), file.as_fd(), size);
            _keymap = Some(file);
            Some(kb)
        });
        let _ = queue.roundtrip(&mut state);

        let start = Instant::now();
        let now = || start.elapsed().as_millis() as u32;
        for cmd in rx {
            match cmd {
                InputCmd::Key { keysym, mods } => {
                    let (Some(kb), Some(code)) = (&keyboard, evdev_code(keysym)) else { continue };
                    kb.modifiers(mods, 0, 0, 0);
                    kb.key(now(), code, wl_keyboard::KeyState::Pressed.into());
                    kb.key(now(), code, wl_keyboard::KeyState::Released.into());
                    kb.modifiers(0, 0, 0, 0);
                }
                InputCmd::PadStart => pad = if output.is_some() { cursor_on_output() } else { None },
                InputCmd::Motion(dx, dy) => {
                    let Some(p) = &pointer else { continue };
                    match &mut pad {
                        // Absolute, clamped to the output: the cursor cannot
                        // leave it. Extents in 1/10 px keep sub-pixel steps.
                        Some((x, y, w, h)) => {
                            *x = (*x + dx as f64).clamp(0.0, *w - 1.0);
                            *y = (*y + dy as f64).clamp(0.0, *h - 1.0);
                            let (ex, ey) = ((*w * 10.0) as u32, (*h * 10.0) as u32);
                            p.motion_absolute(now(), (*x * 10.0) as u32, (*y * 10.0) as u32, ex, ey);
                        }
                        None => p.motion(now(), dx as f64, dy as f64),
                    }
                    p.frame();
                }
                InputCmd::Scroll(dy) => {
                    let Some(p) = &pointer else { continue };
                    p.axis_source(wl_pointer::AxisSource::Finger);
                    p.axis(now(), wl_pointer::Axis::VerticalScroll, dy as f64);
                    p.frame();
                }
                InputCmd::Click(button) => {
                    let Some(p) = &pointer else { continue };
                    p.button(now(), button, wl_pointer::ButtonState::Pressed);
                    p.frame();
                    p.button(now(), button, wl_pointer::ButtonState::Released);
                    p.frame();
                }
            }
            if conn.flush().is_err() {
                return;
            }
        }
    });
    tx
}
