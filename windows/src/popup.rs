//! Suggestion list and mode badge: one borderless popup per UI thread, painted with GDI.
//! The badge sits under the caret, yellow, faint and click-through; bright for a moment after a toggle,
//! hidden while typing and back once typing pauses.
//! Rounded corners on Windows 11; light/dark follows the system app theme.
use std::cell::RefCell;

use windows::core::*;
use windows::Win32::Foundation::*;
use windows::Win32::Graphics::Dwm::*;
use windows::Win32::Graphics::Gdi::*;
use windows::Win32::System::Registry::*;
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::WindowsAndMessaging::*;

#[derive(Default)]
struct Popup {
    hwnd: HWND,
    items: Vec<String>,
    selected: Option<usize>, // None: mode badge
    rest: Option<(String, RECT)>, // badge to show when timer 2 fires
}

thread_local! {
    static P: RefCell<Popup> = RefCell::default();
}

// sizes in 96-dpi pixels
const ROW: i32 = 36;
const PAD: i32 = 5;
const NUM_W: i32 = 28;
const MIN_W: i32 = 180;
const BADGE_MS: u32 = 800;
const FAINT: u8 = 190; // badge opacity at rest, of 255
const REST_MS: u32 = 1000; // typing pause before the badge comes back

pub fn show(items: &[String], selected: usize, caret: RECT) {
    if items.is_empty() {
        return hide();
    }
    place(items.to_vec(), Some(selected), caret, 255);
}

pub fn select(i: usize) {
    P.with(|p| {
        let mut p = p.borrow_mut();
        p.selected = Some(i);
        unsafe {
            let _ = InvalidateRect(p.hwnd, None, TRUE);
        }
    });
}

/// Just toggled: bright, then faint (timer 1).
pub fn badge(text: &str) {
    let hwnd = place(vec![text.to_string()], None, system_caret().unwrap_or_else(mouse), 255);
    unsafe { SetTimer(hwnd, 1, BADGE_MS, None) };
}

/// After a key or focus change: hidden now, faint at `caret` (from TSF) or the system caret once
/// typing pauses (timer 2); stays hidden if neither.
pub fn follow(text: &str, caret: Option<RECT>) {
    hide();
    if let Some(rc) = caret.or_else(system_caret) {
        let hwnd = window();
        P.with(|p| p.borrow_mut().rest = Some((text.to_string(), rc)));
        unsafe { SetTimer(hwnd, 2, REST_MS, None) };
    }
}

pub fn hide() {
    P.with(|p| unsafe {
        let hwnd = p.borrow().hwnd;
        let _ = KillTimer(hwnd, 2);
        let _ = ShowWindow(hwnd, SW_HIDE);
    });
}

fn place(items: Vec<String>, selected: Option<usize>, caret: RECT, alpha: u8) -> HWND {
    let hwnd = window();
    unsafe {
        let _ = KillTimer(hwnd, 1);
        let _ = KillTimer(hwnd, 2); // anything shown now beats a badge waiting for a pause
        let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), alpha, LWA_ALPHA);
        let px = scale(hwnd);
        // measure the widest suggestion
        let dc = GetDC(hwnd);
        let font = font(px(22), w!("Khmer UI"));
        let old = SelectObject(dc, font);
        let mut text_w = 0;
        for it in &items {
            let mut sz = SIZE::default();
            let _ = GetTextExtentPoint32W(dc, &crate::wide(it), &mut sz);
            text_w = text_w.max(sz.cx);
        }
        SelectObject(dc, old);
        let _ = DeleteObject(font);
        ReleaseDC(hwnd, dc);
        let (w, h) = match selected {
            Some(_) => ((text_w + px(2 * PAD + 10 + NUM_W + 16)).max(px(MIN_W)), px(ROW) * items.len() as i32 + px(2 * PAD)),
            None => (text_w + px(28), px(ROW)),
        };
        P.with(|p| {
            let mut p = p.borrow_mut();
            p.items = items;
            p.selected = selected;
        });
        // under the caret; above it when there's no room below
        let mut mi = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
        let mon = MonitorFromPoint(POINT { x: caret.left, y: caret.bottom }, MONITOR_DEFAULTTONEAREST);
        let _ = GetMonitorInfoW(mon, &mut mi);
        let work = mi.rcWork;
        let mut y = caret.bottom + px(6);
        if y + h > work.bottom {
            y = caret.top - h - px(6);
        }
        // badge sits behind the caret (right edge on it); the list starts at it
        let left = if selected.is_none() { caret.left - w } else { caret.left };
        let x = left.min(work.right - w).max(work.left);
        let _ = SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        let _ = InvalidateRect(hwnd, None, TRUE);
    }
    hwnd
}

/// Converts 96-dpi pixels to this window's monitor.
fn scale(hwnd: HWND) -> impl Fn(i32) -> i32 {
    let dpi = unsafe { GetDpiForWindow(hwnd) }.max(96) as i32;
    move |v| v * dpi / 96
}

fn font(height: i32, face: PCWSTR) -> HFONT {
    unsafe {
        CreateFontW(
            -height,
            0,
            0,
            0,
            FW_NORMAL.0 as i32,
            0,
            0,
            0,
            DEFAULT_CHARSET.0 as u32,
            OUT_DEFAULT_PRECIS.0 as u32,
            CLIP_DEFAULT_PRECIS.0 as u32,
            CLEARTYPE_QUALITY.0 as u32,
            0,
            face,
        )
    }
}

/// Caret of the focused window, for apps that use the system caret.
fn system_caret() -> Option<RECT> {
    unsafe {
        let mut gui = GUITHREADINFO { cbSize: std::mem::size_of::<GUITHREADINFO>() as u32, ..Default::default() };
        if GetGUIThreadInfo(0, &mut gui).is_ok() && !gui.hwndCaret.is_invalid() {
            let mut pts = [
                POINT { x: gui.rcCaret.left, y: gui.rcCaret.top },
                POINT { x: gui.rcCaret.right, y: gui.rcCaret.bottom },
            ];
            MapWindowPoints(gui.hwndCaret, None, &mut pts);
            return Some(RECT { left: pts[0].x, top: pts[0].y, right: pts[1].x, bottom: pts[1].y });
        }
        None
    }
}

fn mouse() -> RECT {
    unsafe {
        let mut p = POINT::default();
        let _ = GetCursorPos(&mut p);
        RECT { left: p.x, top: p.y, right: p.x, bottom: p.y + 16 }
    }
}

fn window() -> HWND {
    let existing = P.with(|p| p.borrow().hwnd);
    if !existing.is_invalid() {
        return existing;
    }
    unsafe {
        let inst: HINSTANCE = crate::dll().into();
        let class = w!("TyperPopup");
        let wc = WNDCLASSW {
            lpfnWndProc: Some(wndproc),
            hInstance: inst,
            lpszClassName: class,
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            ..Default::default()
        };
        RegisterClassW(&wc); // fails harmlessly when another thread already registered it
        let hwnd = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
            class,
            w!(""),
            WS_POPUP,
            0,
            0,
            0,
            0,
            None,
            None,
            inst,
            None,
        )
        .unwrap_or_default();
        let round = DWMWCP_ROUND; // Windows 11; ignored on 10
        let _ = DwmSetWindowAttribute(
            hwnd,
            DWMWA_WINDOW_CORNER_PREFERENCE,
            &round as *const _ as *const _,
            std::mem::size_of_val(&round) as u32,
        );
        P.with(|p| p.borrow_mut().hwnd = hwnd);
        hwnd
    }
}

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, w: WPARAM, l: LPARAM) -> LRESULT {
    match msg {
        WM_PAINT => {
            paint(hwnd);
            LRESULT(0)
        }
        WM_MOUSEACTIVATE => LRESULT(MA_NOACTIVATE as isize),
        // badge: clicks fall through to the text under it
        WM_NCHITTEST if P.with(|p| p.try_borrow().is_ok_and(|p| p.selected.is_none())) => LRESULT(-1), // HTTRANSPARENT
        WM_TIMER => {
            let _ = KillTimer(hwnd, w.0);
            if w.0 == 2 {
                if let Some((text, rc)) = P.with(|p| p.borrow_mut().rest.take()) {
                    place(vec![text], None, rc, FAINT);
                }
            } else {
                let _ = SetLayeredWindowAttributes(hwnd, COLORREF(0), FAINT, LWA_ALPHA);
            }
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, w, l),
    }
}

fn dark_mode() -> bool {
    let mut v: u32 = 1;
    let mut size = std::mem::size_of::<u32>() as u32;
    unsafe {
        let _ = RegGetValueW(
            HKEY_CURRENT_USER,
            w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
            w!("AppsUseLightTheme"),
            RRF_RT_REG_DWORD,
            None,
            Some(&mut v as *mut u32 as *mut _),
            Some(&mut size),
        );
    }
    v == 0
}

const fn rgb(r: u8, g: u8, b: u8) -> COLORREF {
    COLORREF(r as u32 | (g as u32) << 8 | (b as u32) << 16)
}

unsafe fn paint(hwnd: HWND) {
    let mut ps = PAINTSTRUCT::default();
    let dc = BeginPaint(hwnd, &mut ps);
    let badge = P.with(|p| p.borrow().selected.is_none());
    let yellow = rgb(0xf5, 0xc8, 0x42);
    let (bg, fg, dim, border) = if badge {
        (yellow, rgb(0x1a, 0x1a, 0x1a), yellow, yellow) // dark on yellow, either theme
    } else if dark_mode() {
        (rgb(0x2c, 0x2c, 0x2c), rgb(0xff, 0xff, 0xff), rgb(0x9d, 0x9d, 0x9d), rgb(0x48, 0x48, 0x48))
    } else {
        (rgb(0xf9, 0xf9, 0xf9), rgb(0x1a, 0x1a, 0x1a), rgb(0x8a, 0x8a, 0x8a), rgb(0xdd, 0xdd, 0xdd))
    };
    let accent = rgb(0x00, 0x67, 0xc0);
    let white = rgb(0xff, 0xff, 0xff);
    let px = scale(hwnd);
    let mut rc = RECT::default();
    let _ = GetClientRect(hwnd, &mut rc);
    let brush = CreateSolidBrush(bg);
    FillRect(dc, &rc, brush);
    let _ = DeleteObject(brush);
    let brush = CreateSolidBrush(border);
    FrameRect(dc, &rc, brush);
    let _ = DeleteObject(brush);

    let khmer = font(px(22), w!("Khmer UI"));
    let num = font(px(14), w!("Segoe UI"));
    SetBkMode(dc, TRANSPARENT);
    P.with(|p| {
        let p = p.borrow();
        let badge = p.selected.is_none();
        for (i, item) in p.items.iter().enumerate() {
            let top = if badge { 0 } else { px(PAD) + px(ROW) * i as i32 };
            let row = if badge { rc } else { RECT { left: px(PAD), top, right: rc.right - px(PAD), bottom: top + px(ROW) } };
            let on = p.selected == Some(i);
            if on {
                let b = CreateSolidBrush(accent);
                let pen = CreatePen(PS_SOLID, 1, accent);
                let (ob, op) = (SelectObject(dc, b), SelectObject(dc, pen));
                let _ = RoundRect(dc, row.left, row.top, row.right, row.bottom, px(8), px(8));
                SelectObject(dc, ob);
                SelectObject(dc, op);
                let _ = DeleteObject(b);
                let _ = DeleteObject(pen);
            }
            let mut text_rc = row;
            let flags = DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX;
            if badge {
                SelectObject(dc, khmer);
                SetTextColor(dc, fg);
                DrawTextW(dc, &mut crate::wide(item), &mut text_rc, flags | DT_CENTER);
                continue;
            }
            SelectObject(dc, num);
            SetTextColor(dc, if on { white } else { dim });
            text_rc.left += px(10);
            DrawTextW(dc, &mut crate::wide(&(i + 1).to_string()), &mut text_rc, flags);
            SelectObject(dc, khmer);
            SetTextColor(dc, if on { white } else { fg });
            text_rc.left += px(NUM_W);
            DrawTextW(dc, &mut crate::wide(item), &mut text_rc, flags);
        }
    });
    let _ = DeleteObject(khmer);
    let _ = DeleteObject(num);
    let _ = EndPaint(hwnd, &ps);
}
