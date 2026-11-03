//! Typer for Windows: a TSF keyboard text service (COM DLL) over the shared engine.
//!
//! Same keys as macOS: letters and spaces build a latin phrase (the composition); the popup lists Khmer.
//! ↓/↑: move highlight. Enter / 1-9: insert. Tab or Esc: insert the latin as typed. Backspace: edit.
//! Punctuation or shortcuts: insert top suggestion, then the key goes on to the app.
//! Tap Shift alone with nothing typed: toggle English passthrough.
#![allow(non_snake_case)]

mod popup;

use std::cell::RefCell;
use std::ffi::c_void;
use std::mem::ManuallyDrop;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicPtr, Ordering::Relaxed};
use std::sync::Mutex;

use typer::Engine;
use windows::core::*;
use windows::Win32::Foundation::*;
use windows::Win32::System::Com::*;
use windows::Win32::System::LibraryLoader::GetModuleFileNameW;
use windows::Win32::System::Registry::*;
use windows::Win32::System::SystemServices::DLL_PROCESS_ATTACH;
use windows::Win32::UI::Input::KeyboardAndMouse::*;
use windows::Win32::UI::TextServices::*;

// Also hard-coded in installer.iss.
const CLSID_TYPER: GUID = GUID::from_u128(0xbfd22721_7c69_45bb_b43c_57dec56e4e58);
const PROFILE: GUID = GUID::from_u128(0xf7873286_5e67_4bef_8a3e_41cefd0ffc7f);
const LANG_KHMER: u16 = 0x0453; // km-KH
const US_LAYOUT: usize = 0x0409_0409; // keys the app sees (punctuation, English mode) stay US, not Khmer

static DLL: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());
static ENGLISH: AtomicBool = AtomicBool::new(false); // shared by all apps, like Caps Lock
static ENGINE: Mutex<Option<Engine>> = Mutex::new(None);

fn dll() -> HMODULE {
    HMODULE(DLL.load(Relaxed))
}

fn dll_path() -> PathBuf {
    let mut buf = [0u16; 1024];
    let n = unsafe { GetModuleFileNameW(dll(), &mut buf) } as usize;
    PathBuf::from(String::from_utf16_lossy(&buf[..n]))
}

/// Run `f` on the engine, loading it on first use: data next to the DLL, learning in %APPDATA%\Typer.
fn with_engine<T>(f: impl FnOnce(&mut Engine) -> T) -> Option<T> {
    let mut g = ENGINE.lock().ok()?;
    if g.is_none() {
        let data = dll_path().parent()?.join("data");
        let user = std::env::var_os("APPDATA").map(|a| PathBuf::from(a).join("Typer"));
        *g = Engine::load(&data, user.as_deref()).ok();
    }
    g.as_mut().map(f)
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

// ---- COM entry points ----

#[no_mangle]
extern "system" fn DllMain(dll: HMODULE, reason: u32, _: *mut c_void) -> BOOL {
    if reason == DLL_PROCESS_ATTACH {
        DLL.store(dll.0, Relaxed);
    }
    TRUE
}

#[no_mangle]
unsafe extern "system" fn DllGetClassObject(clsid: *const GUID, iid: *const GUID, out: *mut *mut c_void) -> HRESULT {
    if *clsid != CLSID_TYPER {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    let factory: IClassFactory = Factory.into();
    factory.query(iid, out)
}

#[no_mangle]
extern "system" fn DllCanUnloadNow() -> HRESULT {
    S_FALSE // ponytail: stay loaded for the process lifetime instead of counting live objects
}

#[no_mangle]
extern "system" fn DllRegisterServer() -> HRESULT {
    match register() {
        Ok(()) => S_OK,
        Err(e) => e.code(),
    }
}

#[no_mangle]
extern "system" fn DllUnregisterServer() -> HRESULT {
    unregister();
    S_OK
}

const CATEGORIES: [GUID; 3] =
    [GUID_TFCAT_TIP_KEYBOARD, GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT, GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT];

fn clsid_key() -> String {
    format!("CLSID\\{{{CLSID_TYPER:?}}}")
}

fn register() -> Result<()> {
    let dll = dll_path();
    let key = clsid_key();
    reg_set(&key, None, "Typer សរសេរ")?;
    reg_set(&format!("{key}\\InprocServer32"), None, &dll.to_string_lossy())?;
    reg_set(&format!("{key}\\InprocServer32"), Some("ThreadingModel"), "Apartment")?;
    let icon = wide(&dll.with_file_name("typer.ico").to_string_lossy());
    unsafe {
        let profiles: ITfInputProcessorProfileMgr =
            CoCreateInstance(&CLSID_TF_InputProcessorProfiles, None, CLSCTX_INPROC_SERVER)?;
        profiles.RegisterProfile(
            &CLSID_TYPER,
            LANG_KHMER,
            &PROFILE,
            &wide("Typer សរសេរ"),
            &icon,
            0,
            HKL(US_LAYOUT as *mut c_void),
            0,
            TRUE,
            0,
        )?;
        let cats: ITfCategoryMgr = CoCreateInstance(&CLSID_TF_CategoryMgr, None, CLSCTX_INPROC_SERVER)?;
        for c in &CATEGORIES {
            cats.RegisterCategory(&CLSID_TYPER, c, &CLSID_TYPER)?;
        }
    }
    Ok(())
}

fn unregister() {
    unsafe {
        if let Ok(p) =
            CoCreateInstance::<_, ITfInputProcessorProfileMgr>(&CLSID_TF_InputProcessorProfiles, None, CLSCTX_INPROC_SERVER)
        {
            let _ = p.UnregisterProfile(&CLSID_TYPER, LANG_KHMER, &PROFILE, 0);
        }
        if let Ok(c) = CoCreateInstance::<_, ITfCategoryMgr>(&CLSID_TF_CategoryMgr, None, CLSCTX_INPROC_SERVER) {
            for cat in &CATEGORIES {
                let _ = c.UnregisterCategory(&CLSID_TYPER, cat, &CLSID_TYPER);
            }
        }
        let _ = RegDeleteTreeW(HKEY_CLASSES_ROOT, &HSTRING::from(clsid_key()));
    }
}

/// Set a string value under HKEY_CLASSES_ROOT (the 32-bit DLL lands in WOW6432Node, as COM expects).
fn reg_set(key: &str, name: Option<&str>, value: &str) -> Result<()> {
    let mut hk = HKEY::default();
    unsafe {
        RegCreateKeyExW(
            HKEY_CLASSES_ROOT,
            &HSTRING::from(key),
            0,
            PCWSTR::null(),
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            None,
            &mut hk,
            None,
        )
        .ok()?;
        let data: Vec<u16> = value.encode_utf16().chain([0]).collect();
        let bytes = std::slice::from_raw_parts(data.as_ptr().cast::<u8>(), data.len() * 2);
        let name = name.map(HSTRING::from).unwrap_or_default();
        let r = RegSetValueExW(hk, &name, 0, REG_SZ, Some(bytes)).ok();
        let _ = RegCloseKey(hk);
        r
    }
}

#[implement(IClassFactory)]
struct Factory;

impl IClassFactory_Impl for Factory_Impl {
    fn CreateInstance(&self, outer: Option<&IUnknown>, iid: *const GUID, out: *mut *mut c_void) -> Result<()> {
        if outer.is_some() {
            return Err(CLASS_E_NOAGGREGATION.into());
        }
        let tip: ITfTextInputProcessorEx = TextService::default().into();
        unsafe { tip.query(iid, out).ok() }
    }

    fn LockServer(&self, _: BOOL) -> Result<()> {
        Ok(())
    }
}

// ---- the text service ----

#[derive(Default)]
struct State {
    thread_mgr: Option<ITfThreadMgr>,
    client: u32,
    composition: Option<ITfComposition>,
    buffer: String,
    suggestions: Vec<String>,
    selected: usize,
    shift_alone: bool, // Shift pressed with no other key since
}

#[implement(ITfTextInputProcessorEx, ITfKeyEventSink, ITfCompositionSink)]
#[derive(Default)]
struct TextService {
    s: RefCell<State>,
}

/// What a key does. CommitPass: insert the top suggestion, then let the app have the key.
#[derive(PartialEq)]
enum Act {
    Pass,
    Eat,
    CommitPass,
}

impl ITfTextInputProcessor_Impl for TextService_Impl {
    fn Activate(&self, ptim: Option<&ITfThreadMgr>, tid: u32) -> Result<()> {
        self.ActivateEx(ptim, tid, 0)
    }

    fn Deactivate(&self) -> Result<()> {
        let (tm, client) = {
            let mut s = self.s.borrow_mut();
            s.buffer.clear();
            s.suggestions.clear();
            s.composition = None;
            (s.thread_mgr.take(), s.client)
        };
        popup::hide();
        if let Some(tm) = tm {
            unsafe { tm.cast::<ITfKeystrokeMgr>()?.UnadviseKeyEventSink(client)? };
        }
        Ok(())
    }
}

impl ITfTextInputProcessorEx_Impl for TextService_Impl {
    fn ActivateEx(&self, ptim: Option<&ITfThreadMgr>, tid: u32, _flags: u32) -> Result<()> {
        let tm = ptim.ok_or_else(|| Error::from(E_INVALIDARG))?.clone();
        let sink: ITfKeyEventSink = self.to_interface();
        unsafe { tm.cast::<ITfKeystrokeMgr>()?.AdviseKeyEventSink(tid, &sink, TRUE)? };
        let mut s = self.s.borrow_mut();
        s.thread_mgr = Some(tm);
        s.client = tid;
        Ok(())
    }
}

impl ITfKeyEventSink_Impl for TextService_Impl {
    fn OnSetFocus(&self, _: BOOL) -> Result<()> {
        Ok(())
    }

    // TSF asks first (Test), then calls OnKeyDown only for keys we claimed. OnKeyDown returning
    // FALSE after acting sends the key on to the app (CommitPass).
    fn OnTestKeyDown(&self, _: Option<&ITfContext>, w: WPARAM, _: LPARAM) -> Result<BOOL> {
        Ok((self.key(None, w) != Act::Pass).into())
    }

    fn OnKeyDown(&self, ctx: Option<&ITfContext>, w: WPARAM, _: LPARAM) -> Result<BOOL> {
        Ok(match ctx {
            Some(ctx) => (self.key(Some(ctx), w) == Act::Eat).into(),
            None => FALSE,
        })
    }

    fn OnTestKeyUp(&self, _: Option<&ITfContext>, w: WPARAM, _: LPARAM) -> Result<BOOL> {
        let mut s = self.s.borrow_mut();
        let tap = VIRTUAL_KEY(w.0 as u16) == VK_SHIFT && std::mem::take(&mut s.shift_alone);
        if tap && s.buffer.is_empty() {
            drop(s);
            let english = !ENGLISH.fetch_xor(true, Relaxed);
            popup::badge(if english { "EN" } else { "ខ" });
        }
        Ok(FALSE)
    }

    fn OnKeyUp(&self, _: Option<&ITfContext>, _: WPARAM, _: LPARAM) -> Result<BOOL> {
        Ok(FALSE)
    }

    fn OnPreservedKey(&self, _: Option<&ITfContext>, _: *const GUID) -> Result<BOOL> {
        Ok(FALSE)
    }
}

impl ITfCompositionSink_Impl for TextService_Impl {
    /// The app ended our composition (focus moved, clicked elsewhere): keep the latin, don't guess.
    fn OnCompositionTerminated(&self, _: u32, _: Option<&ITfComposition>) -> Result<()> {
        let mut s = self.s.borrow_mut();
        s.composition = None;
        s.buffer.clear();
        s.suggestions.clear();
        popup::hide();
        Ok(())
    }
}

/// Letter, apostrophe, space or digit from a virtual key, read straight from the key code
/// (the Khmer keyboard layout would translate letters into Khmer script).
fn typed_char(vk: VIRTUAL_KEY, shift: bool) -> Option<char> {
    let caps = unsafe { GetKeyState(VK_CAPITAL.0 as i32) } & 1 == 1;
    match vk.0 {
        0x41..=0x5A => {
            let c = char::from(vk.0 as u8);
            Some(if shift != caps { c } else { c.to_ascii_lowercase() })
        }
        0x30..=0x39 if !shift => Some(char::from(vk.0 as u8)),
        _ if vk == VK_OEM_7 && !shift => Some('\''),
        _ if vk == VK_SPACE => Some(' '),
        _ => None,
    }
}

impl TextService_Impl {
    /// Decide what `w` does; with `ctx` (OnKeyDown) also do it. Mirrors macos/InputController.swift.
    fn key(&self, ctx: Option<&ITfContext>, w: WPARAM) -> Act {
        let vk = VIRTUAL_KEY(w.0 as u16);
        self.s.borrow_mut().shift_alone = vk == VK_SHIFT; // any other key: Shift was a modifier
        if vk == VK_SHIFT || ENGLISH.load(Relaxed) {
            return Act::Pass;
        }
        let down = |k: VIRTUAL_KEY| unsafe { GetKeyState(k.0 as i32) } < 0;
        let (composing, n) = {
            let s = self.s.borrow();
            (!s.buffer.is_empty(), s.suggestions.len())
        };
        let shortcut = down(VK_CONTROL) || down(VK_MENU) || down(VK_LWIN) || down(VK_RWIN);
        let c = if shortcut { None } else { typed_char(vk, down(VK_SHIFT)) };
        let eat = |f: &dyn Fn(&ITfContext)| {
            if let Some(ctx) = ctx {
                f(ctx);
            }
            Act::Eat
        };
        match (vk, c) {
            _ if shortcut => {}
            (VK_RETURN, _) if composing => {
                return eat(&|ctx| {
                    let i = self.s.borrow().selected;
                    self.commit(ctx, i)
                })
            }
            (VK_DOWN | VK_UP, _) if composing && n > 0 => {
                return eat(&|_| {
                    let mut s = self.s.borrow_mut();
                    s.selected = (s.selected + if vk == VK_UP { n - 1 } else { 1 }) % n;
                    popup::select(s.selected);
                })
            }
            (VK_TAB | VK_ESCAPE, _) if composing => {
                return eat(&|ctx| {
                    let text = self.s.borrow().buffer.clone();
                    self.finish(ctx, text);
                })
            }
            (VK_BACK, _) if composing => {
                return eat(&|ctx| {
                    self.s.borrow_mut().buffer.pop();
                    self.update(ctx);
                })
            }
            (_, Some(ch)) if ch.is_ascii_alphabetic() || ch == '\'' || (ch == ' ' && composing) => {
                return eat(&|ctx| {
                    let mut s = self.s.borrow_mut();
                    if !(ch == ' ' && s.buffer.ends_with(' ')) {
                        s.buffer.push(ch); // space separates words, never commits
                    }
                    drop(s);
                    self.update(ctx);
                })
            }
            (_, Some(d @ '1'..='9')) if composing && (d as usize - '0' as usize) <= n => {
                return eat(&|ctx| self.commit(ctx, d as usize - '1' as usize))
            }
            _ => {}
        }
        if !composing {
            return Act::Pass;
        }
        if let Some(ctx) = ctx {
            self.commit(ctx, 0);
        }
        Act::CommitPass
    }

    fn edit(&self, ctx: &ITfContext, f: impl Fn(u32) -> Result<()> + 'static) {
        let client = self.s.borrow().client;
        let session: ITfEditSession = Session(Box::new(f)).into();
        let _ = unsafe { ctx.RequestEditSession(client, &session, TF_ES_SYNC | TF_ES_READWRITE) };
    }

    /// Show the buffer as the composition and refresh the popup under it.
    fn update(&self, ctx: &ITfContext) {
        let (buffer, comp) = {
            let s = self.s.borrow();
            (s.buffer.clone(), s.composition.clone())
        };
        if buffer.is_empty() {
            return self.finish(ctx, String::new());
        }
        let suggestions: Vec<String> = if buffer.trim().is_empty() {
            vec![]
        } else {
            with_engine(|e| e.suggest(&buffer, 9).into_iter().map(|s| s.text).collect()).unwrap_or_default()
        };
        let sink: ITfCompositionSink = self.to_interface();
        let out: Rc<RefCell<(Option<ITfComposition>, RECT)>> = Rc::default();
        let (c, o) = (ctx.clone(), out.clone());
        self.edit(ctx, move |ec| unsafe {
            let comp = match &comp {
                Some(x) => x.clone(),
                None => {
                    let at = c.cast::<ITfInsertAtSelection>()?.InsertTextAtSelection(ec, TF_IAS_QUERYONLY, &[])?;
                    c.cast::<ITfContextComposition>()?.StartComposition(ec, &at, &sink)?
                }
            };
            let range = comp.GetRange()?;
            range.SetText(ec, 0, &wide(&buffer))?;
            caret_after(&c, ec, &range)?;
            let mut rect = RECT::default();
            let mut clipped = FALSE;
            c.GetActiveView()?.GetTextExt(ec, &range, &mut rect, &mut clipped)?;
            *o.borrow_mut() = (Some(comp), rect);
            Ok(())
        });
        let (comp, rect) = out.take();
        let mut s = self.s.borrow_mut();
        if comp.is_some() {
            s.composition = comp;
        }
        s.suggestions = suggestions;
        s.selected = 0;
        popup::show(&s.suggestions, 0, rect);
    }

    /// Insert suggestion `i` (or the latin if there is none) and learn the pick.
    fn commit(&self, ctx: &ITfContext, i: usize) {
        let (input, text) = {
            let s = self.s.borrow();
            (s.buffer.clone(), s.suggestions.get(i).cloned())
        };
        match text {
            Some(t) => {
                self.finish(ctx, t);
                with_engine(|e| e.pick(&input, i)); // ponytail: learning failure is silent, as on macOS
            }
            None => self.finish(ctx, input),
        }
    }

    /// Replace the composition with `text` and end it.
    fn finish(&self, ctx: &ITfContext, text: String) {
        let comp = {
            let mut s = self.s.borrow_mut();
            s.buffer.clear();
            s.suggestions.clear();
            s.composition.take()
        };
        popup::hide();
        let c = ctx.clone();
        self.edit(ctx, move |ec| unsafe {
            let range = match &comp {
                Some(comp) => {
                    let r = comp.GetRange()?;
                    r.SetText(ec, 0, &wide(&text))?;
                    r
                }
                None => c.cast::<ITfInsertAtSelection>()?.InsertTextAtSelection(
                    ec,
                    INSERT_TEXT_AT_SELECTION_FLAGS(0),
                    &wide(&text),
                )?,
            };
            caret_after(&c, ec, &range)?;
            if let Some(comp) = &comp {
                comp.EndComposition(ec)?;
            }
            Ok(())
        });
    }
}

/// Put the caret right after `range`.
unsafe fn caret_after(ctx: &ITfContext, ec: u32, range: &ITfRange) -> Result<()> {
    let end = range.Clone()?;
    end.Collapse(ec, TF_ANCHOR_END)?;
    let mut sel = TF_SELECTION {
        range: ManuallyDrop::new(Some(end)),
        style: TF_SELECTIONSTYLE { ase: TF_AE_NONE, fInterimChar: FALSE },
    };
    let r = ctx.SetSelection(ec, std::slice::from_ref(&sel));
    ManuallyDrop::drop(&mut sel.range);
    r
}

#[implement(ITfEditSession)]
struct Session(Box<dyn Fn(u32) -> Result<()>>);

impl ITfEditSession_Impl for Session_Impl {
    fn DoEditSession(&self, ec: u32) -> Result<()> {
        (self.0)(ec)
    }
}
