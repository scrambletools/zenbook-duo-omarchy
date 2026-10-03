//! On-screen keyboard and touchpad for the Zenbook Duo's bottom screen,
//! drawn after the detachable keyboard (key positions are measured from a
//! photo of it, in that photo's pixels).
//!
//! It is a wlr layer-shell surface filling eDP-2: it gets touch and pointer
//! input but never keyboard focus, so keys type into the window you were
//! using. Keys are sent with `wtype` (virtual keyboard protocol, handles
//! modifiers); the touchpad drives a zwlr virtual pointer. No root needed.

mod pointer;

use std::collections::HashMap;
use std::process::Command;
use std::sync::mpsc::{self, Sender};
use std::time::Instant;

use iced::alignment::Vertical;
use iced::mouse;
use iced::touch;
use iced::widget::canvas::{self, Frame, Path, Text};
use iced::widget::text::Alignment;
use iced::{Color, Element, Event, Font, Length, Pixels, Point, Rectangle, Size, Theme};
use iced_layershell::reexport::{Anchor, KeyboardInteractivity, Layer};
use iced_layershell::settings::{LayerShellSettings, Settings, StartMode};
use iced_layershell::to_layer_message;

use pointer::PointerCmd;

const OUTPUT: &str = "eDP-2";
const ICONS: Font = Font::with_name("JetBrainsMono Nerd Font");

// --- Layout ---------------------------------------------------------------

/// The keyboard deck in the photo (pixels): everything is drawn relative to it.
const DECK: (f32, f32, f32, f32) = (145.0, 165.0, 1457.0, 995.0);
/// The touchpad, in photo pixels (left, top, right, bottom).
const PAD: (f32, f32, f32, f32) = (530.0, 625.0, 1070.0, 957.0);
/// Space between keys, in photo pixels.
const GAP: f32 = 11.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Action {
    /// Printable key: keysym, plain and shifted character.
    Char(&'static str, char, char),
    /// Non-printable key; with Fn latched it sends the second keysym.
    Key(&'static str, &'static str),
    /// F-row key: media keysym, and the F-key Fn selects.
    FRow(&'static str, &'static str),
    /// Send a fixed chord, e.g. the Copilot key.
    Chord(&'static [&'static str], &'static str),
    Mod(Modifier),
    Caps,
    Fn,
    Hide,
    SwapScreens,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Modifier {
    Shift,
    Ctrl,
    Alt,
    Super,
}

impl Modifier {
    fn wtype_name(self) -> &'static str {
        match self {
            Modifier::Shift => "shift",
            Modifier::Ctrl => "ctrl",
            Modifier::Alt => "alt",
            Modifier::Super => "logo",
        }
    }
}

/// What is printed on a key.
#[derive(Debug, Clone, Copy)]
enum Legend {
    /// One large label (letters).
    Main(&'static str),
    /// Shifted symbol above, plain symbol below (number row, punctuation).
    Dual(&'static str, &'static str),
    /// Small text label (Ctrl, Caps, …).
    Word(&'static str),
    /// An icon, optionally with a small F-key name beside it.
    Icon(char, &'static str),
    Blank,
}

struct KeyDef {
    units: f32,
    legend: Legend,
    action: Action,
}

const fn key(units: f32, legend: Legend, action: Action) -> KeyDef {
    KeyDef { units, legend, action }
}
const fn letter(l: &'static str, sym: &'static str, plain: char, upper: char) -> KeyDef {
    key(1.0, Legend::Main(l), Action::Char(sym, plain, upper))
}
const fn dual(top: &'static str, main: &'static str, sym: &'static str, plain: char, shifted: char) -> KeyDef {
    key(1.0, Legend::Dual(top, main), Action::Char(sym, plain, shifted))
}
const fn frow(icon: char, f: &'static str, media: &'static str) -> KeyDef {
    key(1.0, Legend::Icon(icon, f), Action::FRow(media, f))
}

/// A row: left, right, top, bottom (photo pixels) and its keys. Key widths
/// are in units; the row's width is shared out in proportion.
struct RowDef {
    span: (f32, f32, f32, f32),
    keys: &'static [KeyDef],
}

const ROWS: &[RowDef] = &[
    RowDef {
        span: (230.0, 1368.0, 206.0, 241.0),
        keys: &[
            key(1.0, Legend::Icon('\u{f033e}', "esc"), Action::Key("Escape", "Escape")),
            frow('\u{f0581}', "F1", "XF86AudioMute"),
            frow('\u{f075e}', "F2", "XF86AudioLowerVolume"),
            frow('\u{f075d}', "F3", "XF86AudioRaiseVolume"),
            frow('\u{f0313}', "F4", "XF86KbdLightOnOff"),
            frow('\u{f00de}', "F5", "XF86MonBrightnessDown"),
            frow('\u{f00e0}', "F6", "XF86MonBrightnessUp"),
            frow('\u{f037a}', "F7", "XF86Display"),
            frow('\u{f0e51}', "F8", "Print"),
            key(1.0, Legend::Word("F9"), Action::FRow("F9", "F9")),
            frow('\u{f036d}', "F10", "XF86AudioMicMute"),
            key(1.0, Legend::Word("F11"), Action::FRow("F11", "F11")),
            key(1.0, Legend::Word("/A  F12"), Action::FRow("F12", "F12")),
            key(1.0, Legend::Icon('\u{f030f}', ""), Action::Hide),
            key(1.0, Legend::Icon('\u{f04e1}', ""), Action::SwapScreens),
            key(1.0, Legend::Word("DEL INS"), Action::Key("Delete", "Insert")),
        ],
    },
    RowDef {
        span: (230.0, 1368.0, 250.0, 310.0),
        keys: &[
            dual("~", "`", "grave", '`', '~'),
            dual("!", "1", "1", '1', '!'),
            dual("@", "2", "2", '2', '@'),
            dual("#", "3", "3", '3', '#'),
            dual("$", "4", "4", '4', '$'),
            dual("%", "5", "5", '5', '%'),
            dual("^", "6", "6", '6', '^'),
            dual("&", "7", "7", '7', '&'),
            dual("*", "8", "8", '8', '*'),
            dual("(", "9", "9", '9', '('),
            dual(")", "0", "0", '0', ')'),
            dual("_", "-", "minus", '-', '_'),
            dual("+", "=", "equal", '=', '+'),
            key(1.66, Legend::Main("←"), Action::Key("BackSpace", "BackSpace")),
        ],
    },
    RowDef {
        span: (228.0, 1370.0, 322.0, 385.0),
        keys: &[
            key(1.67, Legend::Icon('\u{f0312}', ""), Action::Key("Tab", "Tab")),
            letter("Q", "q", 'q', 'Q'),
            letter("W", "w", 'w', 'W'),
            letter("E", "e", 'e', 'E'),
            letter("R", "r", 'r', 'R'),
            letter("T", "t", 't', 'T'),
            letter("Y", "y", 'y', 'Y'),
            letter("U", "u", 'u', 'U'),
            letter("I", "i", 'i', 'I'),
            letter("O", "o", 'o', 'O'),
            letter("P", "p", 'p', 'P'),
            dual("{", "[", "bracketleft", '[', '{'),
            dual("}", "]", "bracketright", ']', '}'),
            key(1.15, Legend::Dual("|", "\\"), Action::Char("backslash", '\\', '|')),
        ],
    },
    RowDef {
        span: (226.0, 1372.0, 395.0, 458.0),
        keys: &[
            key(1.9, Legend::Word("CAPS"), Action::Caps),
            letter("A", "a", 'a', 'A'),
            letter("S", "s", 's', 'S'),
            letter("D", "d", 'd', 'D'),
            letter("F", "f", 'f', 'F'),
            letter("G", "g", 'g', 'G'),
            letter("H", "h", 'h', 'H'),
            letter("J", "j", 'j', 'J'),
            letter("K", "k", 'k', 'K'),
            letter("L", "l", 'l', 'L'),
            dual(":", ";", "semicolon", ';', ':'),
            dual("\"", "'", "apostrophe", '\'', '"'),
            key(1.93, Legend::Icon('\u{f0311}', ""), Action::Key("Return", "Return")),
        ],
    },
    RowDef {
        span: (223.0, 1375.0, 470.0, 533.0),
        keys: &[
            key(2.45, Legend::Icon('\u{f0636}', ""), Action::Mod(Modifier::Shift)),
            letter("Z", "z", 'z', 'Z'),
            letter("X", "x", 'x', 'X'),
            letter("C", "c", 'c', 'C'),
            letter("V", "v", 'v', 'V'),
            letter("B", "b", 'b', 'B'),
            letter("N", "n", 'n', 'N'),
            letter("M", "m", 'm', 'M'),
            dual("<", ",", "comma", ',', '<'),
            dual(">", ".", "period", '.', '>'),
            dual("?", "/", "slash", '/', '?'),
            key(2.45, Legend::Icon('\u{f0636}', ""), Action::Mod(Modifier::Shift)),
        ],
    },
];

/// Bottom row, given key by key in photo pixels (left, right) because of
/// the half-height arrow cluster. Top and bottom of the row:
const BOTTOM_ROW: (f32, f32) = (543.0, 607.0);
const BOTTOM_KEYS: &[(f32, f32, KeyDef)] = &[
    (221.0, 321.0, key(0.0, Legend::Word("CTRL"), Action::Mod(Modifier::Ctrl))),
    (332.0, 400.0, key(0.0, Legend::Word("FN"), Action::Fn)),
    (410.0, 480.0, key(0.0, Legend::Icon('\u{f05b3}', ""), Action::Mod(Modifier::Super))),
    (490.0, 558.0, key(0.0, Legend::Word("ALT"), Action::Mod(Modifier::Alt))),
    (568.0, 950.0, key(0.0, Legend::Blank, Action::Char("space", ' ', ' '))),
    (960.0, 1027.0, key(0.0, Legend::Word("ALT"), Action::Mod(Modifier::Alt))),
    (1038.0, 1107.0, key(0.0, Legend::Icon('\u{f0674}', ""), Action::Chord(&["shift", "logo"], "F23"))),
];
/// Arrow cluster: (left, right, top, bottom) in photo pixels.
const ARROWS: &[((f32, f32, f32, f32), KeyDef)] = &[
    ((1118.0, 1192.0, 577.0, 607.0), key(0.0, Legend::Icon('\u{f035e}', ""), Action::Key("Left", "Home"))),
    ((1203.0, 1290.0, 543.0, 573.0), key(0.0, Legend::Icon('\u{f0360}', ""), Action::Key("Up", "Prior"))),
    ((1203.0, 1290.0, 577.0, 607.0), key(0.0, Legend::Icon('\u{f035d}', ""), Action::Key("Down", "Next"))),
    ((1302.0, 1380.0, 577.0, 607.0), key(0.0, Legend::Icon('\u{f035f}', ""), Action::Key("Right", "End"))),
];

/// A key placed on the deck: rectangle in deck fractions (0..1).
struct Placed {
    rect: Rectangle,
    legend: Legend,
    action: Action,
}

fn frac(l: f32, t: f32, r: f32, b: f32) -> Rectangle {
    let (dl, dt, dr, db) = DECK;
    let (w, h) = (dr - dl, db - dt);
    Rectangle {
        x: (l - dl) / w,
        y: (t - dt) / h,
        width: (r - l) / w,
        height: (b - t) / h,
    }
}

fn build_layout() -> Vec<Placed> {
    let mut keys = Vec::new();
    for row in ROWS {
        let (left, right, top, bottom) = row.span;
        let units: f32 = row.keys.iter().map(|k| k.units).sum();
        let unit = (right - left + GAP) / units;
        let mut x = left;
        for k in row.keys {
            let w = k.units * unit - GAP;
            keys.push(Placed { rect: frac(x, top, x + w, bottom), legend: k.legend, action: k.action });
            x += w + GAP;
        }
    }
    for (l, r, k) in BOTTOM_KEYS {
        keys.push(Placed { rect: frac(*l, BOTTOM_ROW.0, *r, BOTTOM_ROW.1), legend: k.legend, action: k.action });
    }
    for ((l, r, t, b), k) in ARROWS {
        keys.push(Placed { rect: frac(*l, *t, *r, *b), legend: k.legend, action: k.action });
    }
    keys
}

// --- State ----------------------------------------------------------------

#[to_layer_message]
#[derive(Debug, Clone)]
enum Message {
    KeyDown(usize),
    KeyUp(usize),
    Pointer(PointerCmd),
}

struct Keyboard {
    keys: Vec<Placed>,
    held: Vec<usize>,
    /// Modifiers latched for the next key (released after it).
    latched: Vec<Modifier>,
    caps: bool,
    fn_lock: bool,
    typist: Sender<Vec<String>>,
    pointer: Sender<PointerCmd>,
}

impl Keyboard {
    fn new() -> Self {
        // One worker runs wtype calls in order, so fast taps never reorder.
        let (typist, jobs) = mpsc::channel::<Vec<String>>();
        std::thread::spawn(move || {
            for args in jobs {
                let _ = Command::new("wtype").args(&args).status();
            }
        });
        Keyboard {
            keys: build_layout(),
            held: Vec::new(),
            latched: Vec::new(),
            caps: false,
            fn_lock: false,
            typist,
            pointer: pointer::spawn(),
        }
    }

    fn update(&mut self, message: Message) -> iced::Task<Message> {
        match message {
            Message::KeyDown(i) => {
                self.held.push(i);
                return self.press(self.keys[i].action);
            }
            Message::KeyUp(i) => self.held.retain(|h| *h != i),
            Message::Pointer(cmd) => {
                let _ = self.pointer.send(cmd);
            }
            _ => {}
        }
        iced::Task::none()
    }

    fn press(&mut self, action: Action) -> iced::Task<Message> {
        match action {
            Action::Mod(m) => {
                if let Some(i) = self.latched.iter().position(|x| *x == m) {
                    self.latched.remove(i);
                } else {
                    self.latched.push(m);
                }
            }
            Action::Caps => self.caps = !self.caps,
            Action::Fn => self.fn_lock = !self.fn_lock,
            Action::Hide => return iced::exit(),
            Action::SwapScreens => {
                let _ = Command::new("hyprctl")
                    .args(["dispatch", "hl.dsp.workspace.swap_monitors({ monitor1 = \"eDP-1\", monitor2 = \"eDP-2\" })"])
                    .spawn();
            }
            Action::Char(sym, plain, shifted) => {
                if self.latched.iter().all(|m| *m == Modifier::Shift) {
                    // Plain typing: send the character itself, so it does not
                    // depend on the active layout's shift level.
                    let shift = self.latched.contains(&Modifier::Shift);
                    let upper = shift ^ (self.caps && plain.is_ascii_alphabetic());
                    let c = if upper { shifted } else { plain };
                    self.send(vec!["--".into(), c.to_string()]);
                } else {
                    self.combo(sym);
                }
                self.latched.clear();
            }
            Action::Key(sym, fn_sym) => {
                self.combo(if self.fn_lock { fn_sym } else { sym });
                self.latched.clear();
            }
            Action::FRow(media, function) => {
                self.combo(if self.fn_lock { function } else { media });
                self.latched.clear();
            }
            Action::Chord(mods, sym) => {
                let mut args: Vec<String> = Vec::new();
                for m in mods {
                    args.extend(["-M".into(), (*m).into()]);
                }
                args.extend(["-k".into(), sym.into()]);
                for m in mods.iter().rev() {
                    args.extend(["-m".into(), (*m).into()]);
                }
                self.send(args);
            }
        }
        iced::Task::none()
    }

    /// Press the latched modifiers, tap `keysym`, release the modifiers.
    fn combo(&self, keysym: &str) {
        let mut args: Vec<String> = Vec::new();
        for m in &self.latched {
            args.extend(["-M".into(), m.wtype_name().into()]);
        }
        args.extend(["-k".into(), keysym.into()]);
        for m in self.latched.iter().rev() {
            args.extend(["-m".into(), m.wtype_name().into()]);
        }
        self.send(args);
    }

    fn send(&self, args: Vec<String>) {
        let _ = self.typist.send(args);
    }

    fn lit(&self, action: Action) -> bool {
        match action {
            Action::Mod(m) => self.latched.contains(&m),
            Action::Caps => self.caps,
            Action::Fn => self.fn_lock,
            _ => false,
        }
    }

    fn view(&self) -> Element<'_, Message> {
        canvas::Canvas::new(Deck { kb: self }).width(Length::Fill).height(Length::Fill).into()
    }
}

// --- Drawing and input ------------------------------------------------------

struct Deck<'a> {
    kb: &'a Keyboard,
}

const MOUSE: u64 = u64::MAX;
const POINTER_SPEED: f32 = 2.2;
const SCROLL_SPEED: f32 = 0.5;
const TAP_MAX_MS: u128 = 220;
const TAP_SLOP: f32 = 8.0;

#[derive(Default)]
struct Fingers {
    keys: HashMap<u64, usize>,
    pad: HashMap<u64, Point>,
    /// Touchpad gesture in progress: start time, most fingers, moved.
    gesture: Option<(Instant, usize, bool)>,
}

fn deck_rect(bounds: Size, r: Rectangle) -> Rectangle {
    Rectangle {
        x: r.x * bounds.width,
        y: r.y * bounds.height,
        width: r.width * bounds.width,
        height: r.height * bounds.height,
    }
}

impl<'a> Deck<'a> {
    fn key_at(&self, size: Size, p: Point) -> Option<usize> {
        self.kb.keys.iter().position(|k| deck_rect(size, k.rect).contains(p))
    }

    fn on_pad(&self, size: Size, p: Point) -> bool {
        deck_rect(size, frac(PAD.0, PAD.1, PAD.2, PAD.3)).contains(p)
    }

    fn down(&self, st: &mut Fingers, size: Size, id: u64, p: Point) -> Option<canvas::Action<Message>> {
        if let Some(i) = self.key_at(size, p) {
            st.keys.insert(id, i);
            return Some(canvas::Action::publish(Message::KeyDown(i)).and_capture());
        }
        if id != MOUSE && self.on_pad(size, p) {
            st.pad.insert(id, p);
            let n = st.pad.len();
            st.gesture = match st.gesture {
                Some((t, most, moved)) => Some((t, most.max(n), moved)),
                None => Some((Instant::now(), n, false)),
            };
            return Some(canvas::Action::capture());
        }
        None
    }

    fn moved(&self, st: &mut Fingers, id: u64, p: Point) -> Option<canvas::Action<Message>> {
        let last = *st.pad.get(&id)?;
        let (dx, dy) = (p.x - last.x, p.y - last.y);
        st.pad.insert(id, p);
        if let Some((t, most, moved)) = st.gesture {
            let far = moved || dx.abs() + dy.abs() > TAP_SLOP;
            st.gesture = Some((t, most, far));
        }
        let cmd = if st.pad.len() >= 2 {
            PointerCmd::Scroll(dy * SCROLL_SPEED * -1.0)
        } else {
            PointerCmd::Motion(dx * POINTER_SPEED, dy * POINTER_SPEED)
        };
        Some(canvas::Action::publish(Message::Pointer(cmd)).and_capture())
    }

    fn up(&self, st: &mut Fingers, id: u64) -> Option<canvas::Action<Message>> {
        if let Some(i) = st.keys.remove(&id) {
            return Some(canvas::Action::publish(Message::KeyUp(i)).and_capture());
        }
        st.pad.remove(&id)?;
        if !st.pad.is_empty() {
            return Some(canvas::Action::capture());
        }
        let (t, most, moved) = st.gesture.take()?;
        if !moved && t.elapsed().as_millis() <= TAP_MAX_MS {
            let button = if most >= 2 { pointer::BTN_RIGHT } else { pointer::BTN_LEFT };
            return Some(canvas::Action::publish(Message::Pointer(PointerCmd::Click(button))).and_capture());
        }
        Some(canvas::Action::capture())
    }
}

impl<'a> canvas::Program<Message> for Deck<'a> {
    type State = Fingers;

    fn update(
        &self,
        st: &mut Fingers,
        event: &Event,
        bounds: Rectangle,
        cursor: mouse::Cursor,
    ) -> Option<canvas::Action<Message>> {
        let size = bounds.size();
        let local = |p: Point| Point::new(p.x - bounds.x, p.y - bounds.y);
        match event {
            Event::Touch(touch::Event::FingerPressed { id, position }) => {
                self.down(st, size, id.0, local(*position))
            }
            Event::Touch(touch::Event::FingerMoved { id, position }) => self.moved(st, id.0, local(*position)),
            Event::Touch(touch::Event::FingerLifted { id, .. } | touch::Event::FingerLost { id, .. }) => {
                self.up(st, id.0)
            }
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                let p = cursor.position_in(bounds)?;
                self.down(st, size, MOUSE, p)
            }
            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => self.up(st, MOUSE),
            _ => None,
        }
    }

    fn draw(
        &self,
        _st: &Fingers,
        renderer: &iced::Renderer,
        _theme: &Theme,
        bounds: Rectangle,
        _cursor: mouse::Cursor,
    ) -> Vec<canvas::Geometry> {
        let size = bounds.size();
        let mut frame = Frame::new(renderer, size);
        frame.fill_rectangle(Point::ORIGIN, size, DECK_COLOR);

        // Touchpad.
        let pad = deck_rect(size, frac(PAD.0, PAD.1, PAD.2, PAD.3));
        let r = 0.012 * size.height;
        frame.fill(&Path::rounded_rectangle(pad.position(), pad.size(), r.into()), PAD_COLOR);

        let unit_h = size.height * (60.0 / (DECK.3 - DECK.1));
        for (i, k) in self.kb.keys.iter().enumerate() {
            let rect = deck_rect(size, k.rect);
            let fill = if self.kb.held.contains(&i) {
                KEY_PRESSED
            } else if self.kb.lit(k.action) {
                KEY_LIT
            } else {
                KEY_COLOR
            };
            let path = Path::rounded_rectangle(rect.position(), rect.size(), (0.1 * unit_h).into());
            frame.fill(&path, fill);
            draw_legend(&mut frame, rect, k, self.kb, unit_h);
        }
        vec![frame.into_geometry()]
    }
}

const DECK_COLOR: Color = Color::from_rgb8(0x56, 0x57, 0x5b);
const PAD_COLOR: Color = Color::from_rgb8(0x4b, 0x4c, 0x50);
const KEY_COLOR: Color = Color::from_rgb8(0x35, 0x36, 0x39);
const KEY_PRESSED: Color = Color::from_rgb8(0x6c, 0x6e, 0x74);
const KEY_LIT: Color = Color::from_rgb8(0x3a, 0x5d, 0xa8);
const LEGEND: Color = Color::from_rgb8(0xd9, 0xda, 0xdc);

fn label(frame: &mut Frame, content: String, at: Point, size: f32, font: Font, align_x: Alignment) {
    frame.fill_text(Text {
        content,
        position: at,
        color: LEGEND,
        size: Pixels(size),
        font,
        align_x,
        align_y: Vertical::Center,
        ..Text::default()
    });
}

fn draw_legend(frame: &mut Frame, rect: Rectangle, k: &Placed, kb: &Keyboard, unit_h: f32) {
    let center = rect.center();
    let main = 0.38 * unit_h;
    let small = 0.22 * unit_h;
    match k.legend {
        Legend::Main(s) => label(frame, s.into(), center, main, Font::DEFAULT, Alignment::Center),
        Legend::Dual(top, bottom) => {
            let left = rect.x + 0.28 * rect.width;
            label(frame, top.into(), Point::new(left, rect.y + 0.28 * rect.height), small, Font::DEFAULT, Alignment::Center);
            label(frame, bottom.into(), Point::new(center.x, rect.y + 0.62 * rect.height), main, Font::DEFAULT, Alignment::Center);
        }
        Legend::Word(s) => {
            let s = match k.action {
                Action::FRow(_, f) if kb.fn_lock => f.to_string(),
                _ => s.to_string(),
            };
            label(frame, s, center, small, Font::DEFAULT, Alignment::Center);
        }
        Legend::Icon(icon, f) if kb.fn_lock && matches!(k.action, Action::FRow(..)) => {
            let _ = icon;
            label(frame, f.into(), center, small * 1.2, Font::DEFAULT, Alignment::Center);
        }
        Legend::Icon(icon, f) => {
            // Icon-only half-height keys (arrows) fill the key; F-row icons
            // leave room for their F-label.
            let size = match (rect.height < 0.7 * unit_h, f.is_empty()) {
                (true, true) => 0.95 * rect.height,
                (true, false) => 0.62 * rect.height,
                _ => main,
            };
            if f.is_empty() {
                label(frame, icon.to_string(), center, size, ICONS, Alignment::Center);
            } else {
                let x = rect.x + 0.36 * rect.width;
                label(frame, icon.to_string(), Point::new(x, center.y), size, ICONS, Alignment::Center);
                let fx = rect.x + 0.74 * rect.width;
                label(frame, f.into(), Point::new(fx, center.y), 0.5 * size, Font::DEFAULT, Alignment::Center);
            }
        }
        Legend::Blank => {}
    }
}

fn namespace() -> String {
    String::from("zenbook-duo-keyboard")
}

fn main() -> Result<(), iced_layershell::Error> {
    // Software rendering: the deck is flat shapes and text, and skipping the
    // GPU renderer keeps start-up quick and memory low.
    if std::env::var_os("ICED_BACKEND").is_none() {
        // SAFETY: no other threads exist yet.
        unsafe { std::env::set_var("ICED_BACKEND", "tiny-skia") };
    }
    iced_layershell::application(Keyboard::new, namespace, Keyboard::update, Keyboard::view)
        .settings(Settings {
            layer_settings: LayerShellSettings {
                anchor: Anchor::Top | Anchor::Bottom | Anchor::Left | Anchor::Right,
                layer: Layer::Top,
                exclusive_zone: -1,
                size: None,
                keyboard_interactivity: KeyboardInteractivity::None,
                start_mode: StartMode::TargetScreen(OUTPUT.to_string()),
                ..Default::default()
            },
            ..Default::default()
        })
        .run()
}
