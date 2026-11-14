//! Sing Khmer engine: space-separated romanized tokens -> ranked Khmer phrases.
//!
//! score(phrase) = sum over tokens of [ LM(word | prev two words) - SPELL_WEIGHT * dist(typed, spelling) ]
//! - dist: weighted edit distance with cheap vowel/h drops and similar-sound swaps, plus prefix completion.
//! - LM: stupid backoff over 1-3 gram counts (data/out/ngrams.tsv) plus the user's own picks (user.tsv).
//! - English: a token that is an English word (data/out/english.tsv) may stay English, scored as
//!   P(<oth> | prev words) * P(word in English), so common chat spellings (mean = មាន) keep their Khmer;
//!   right after another English word, by English bigrams instead ("thank you").
//! - Negation frame: after អត់/មិន/... the closing ទេ gets a bonus, however far back the negation is.
//! - Punctuation typed in the phrase stays as typed: "knhom, tov te?" -> ខ្ញុំ, ទៅទេ?
//! - Settings: on/off switches in `user_dir/settings.txt` (SETTINGS), re-read when the file changes.
//!   user.tsv too: deleting it (or the folder) resets learning without a restart.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;

pub mod ffi;

// ponytail: hand-tuned costs; learn them from spelling pairs once eval/test.tsv is big enough.
const SPELL_WEIGHT: f32 = 8.0; // log-prob units per edit-distance unit
const MAX_DIST: f32 = 2.5;
const TAIL_COST: f32 = 0.3; // per unspelled char when typed is a prefix ("kn" -> knhom)
const CANDIDATES_PER_TOKEN: usize = 15;
const BEAM: usize = 30;
const BACKOFF: f32 = 0.4_f32;
const LM_WEIGHT: f32 = 0.5; // <1 flattens the news-register LM so exact chat spellings can win
const EXACT_BONUS: f32 = 2.0;
const RAW_PENALTY: f32 = -20.0; // keep the typed latin token when nothing fits
const USER_BOOST: f32 = 100.0; // one pick counts like 100 corpus occurrences
const MAX_JOIN: usize = 3; // one Khmer word may be typed as up to 3 latin tokens ("pirn ng" -> ប៉ុណ្ណឹង)
const JOIN_MAX_DIST: f32 = 1.5; // joined tokens must spell the word closely
const JOIN_PENALTY: f32 = 2.0; // offsets the LM term a one-word path saves over a two-word path
// ponytail: one hand rule for the commonest long-range pattern; more frames want a real sentence model
const NEGATIONS: [&str; 5] = ["អត់", "មិន", "គ្មាន", "ពុំ", "កុំ"];
const NEG_CLOSE: &str = "ទេ";
const NEG_BONUS: f32 = 1.0; // ទេ after an open negation ("ot mean te" -> អត់មានទេ, not អត់មានតែ)
const EN_SWITCH: f32 = 1.0; // cost of switching from Khmer into English; raise if English steals Khmer phrases

fn is_vowel(c: u8) -> bool {
    matches!(c, b'a' | b'e' | b'i' | b'o' | b'u' | b'y')
}

/// Cost of the user skipping spelling char `c` (knhom vs khnhoam). `prev` is the spelling char before it.
fn del_cost(c: u8, prev: u8) -> f32 {
    // r after a vowel only marks vowel length (pirn, terng, krerng), so it's often dropped: pin ng
    if is_vowel(c) || c == b'h' || (c == b'r' && is_vowel(prev)) { 0.4 } else { 1.2 }
}

/// Cost of the user typing extra char `c` not in the spelling.
fn ins_cost(c: u8) -> f32 {
    if is_vowel(c) || c == b'h' { 0.5 } else { 1.2 }
}

fn sub_cost(a: u8, b: u8) -> f32 {
    if a == b {
        return 0.0;
    }
    const SIMILAR: [&[u8]; 7] = [b"kg", b"cjx", b"pb", b"td", b"ou", b"eiy", b"ae"];
    if SIMILAR.iter().any(|g| g.contains(&a) && g.contains(&b)) {
        0.4
    } else if is_vowel(a) && is_vowel(b) {
        0.6
    } else {
        1.5
    }
}

/// Weighted edit distance from typed `t` to spelling `s`, allowing `t` to stop early (autocomplete).
pub fn dist(t: &[u8], s: &[u8]) -> f32 {
    let mut prev: Vec<f32> = Vec::with_capacity(s.len() + 1);
    prev.push(0.0);
    let before = |j: usize| if j == 0 { 0 } else { s[j - 1] };
    for j in 0..s.len() {
        prev.push(prev[j] + del_cost(s[j], before(j)));
    }
    let mut cur = vec![0.0; s.len() + 1];
    for i in 0..t.len() {
        cur[0] = prev[0] + ins_cost(t[i]);
        let mut row_min = cur[0];
        for j in 0..s.len() {
            cur[j + 1] = (prev[j] + sub_cost(t[i], s[j]))
                .min(prev[j + 1] + ins_cost(t[i]))
                .min(cur[j] + del_cost(s[j], before(j)));
            row_min = row_min.min(cur[j + 1]);
        }
        if row_min > MAX_DIST {
            return f32::INFINITY;
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    let m = s.len();
    (0..=m).map(|j| prev[j] + TAIL_COST * (m - j) as f32).fold(f32::INFINITY, f32::min)
}

fn is_word_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '\''
}

/// A typed latin token (not Khmer, not a marker like <s>).
fn is_latin(w: &str) -> bool {
    w.chars().all(is_word_char)
}

/// A typed symbol run like "," or "?!" (Khmer words and markers have no ASCII punctuation).
fn is_punct(w: &str) -> bool {
    !w.is_empty() && w.chars().all(|c| c.is_ascii_punctuation() && c != '\'')
}

/// LM context for a word: latin tokens look like the corpus's "foreign word here" marker;
/// punctuation starts over like a new sentence.
fn ctx(w: &str) -> &str {
    if is_latin(w) {
        "<oth>"
    } else if is_punct(w) {
        "<s>"
    } else {
        w
    }
}

/// Space-separated words, with each run of punctuation as its own token: "te?" -> ["te", "?"].
pub fn tokens(input: &str) -> Vec<&str> {
    let mut out = Vec::new();
    for chunk in input.split_whitespace() {
        let mut start = 0;
        for (i, c) in chunk.char_indices().skip(1) {
            let prev = chunk[..i].chars().next_back().unwrap();
            if is_word_char(c) != is_word_char(prev) {
                out.push(&chunk[start..i]);
                start = i;
            }
        }
        out.push(&chunk[start..]);
    }
    out
}

pub fn normalize(token: &str) -> String {
    token.to_lowercase().chars().filter(|c| c.is_ascii_alphanumeric()).collect()
}

type Counts = [HashMap<String, u64>; 3]; // n-gram key "w1 w2" -> count, by n-1

/// User switches, all on by default. "badge" is read by the frontends (the ខ/EN mode badge).
pub const SETTINGS: [&str; 4] = ["generated", "english", "learn", "badge"];

/// Names switched off in `dir/settings.txt` ("name=off" lines; anything else counts as on).
pub fn read_settings(dir: &Path) -> HashSet<String> {
    let text = fs::read_to_string(dir.join("settings.txt")).unwrap_or_default();
    text.lines()
        .filter_map(|l| l.split_once('='))
        .filter(|(_, v)| v.trim() == "off")
        .map(|(k, _)| k.trim().to_string())
        .collect()
}

/// Switch `name` on or off in `dir/settings.txt`; running engines pick it up on their next keystroke.
pub fn write_setting(dir: &Path, name: &str, on: bool) -> std::io::Result<()> {
    let mut off = read_settings(dir);
    if on {
        off.remove(name);
    } else {
        off.insert(name.to_string());
    }
    fs::create_dir_all(dir)?;
    let text: String = SETTINGS.iter().map(|k| format!("{k}={}\n", if off.contains(*k) { "off" } else { "on" })).collect();
    fs::write(dir.join("settings.txt"), text)
}

// The Windows frontend keeps the Engine in a static Mutex, so it must stay Send; this fails the build on every platform if not.
const _: fn() = || {
    fn send<T: Send>() {}
    send::<Engine>();
};

pub struct Engine {
    words: Vec<String>,
    first_generated: usize, // words from here on have rule-generated spellings (generated.tsv)
    spellings: Vec<(Vec<u8>, u32)>, // (roman, word id)
    by_roman: Vec<u32>, // indices into `spellings`, sorted by roman: neighbours share prefixes
    counts: Counts,
    user: RefCell<Counts>,
    user_seen: Cell<Option<(SystemTime, u64)>>, // user.tsv mtime + length that `user` matches
    user_dir: Option<PathBuf>,
    total: f32,
    english: HashMap<String, f32>, // normalized English word or "w1 w2" -> count
    en_total: f32,                 // unigrams only
    // typed text -> candidates; while typing only the last token changes, so the rest are hits
    cache: RefCell<HashMap<String, Vec<(String, f32)>>>,
    settings: RefCell<(Option<SystemTime>, HashSet<String>)>, // settings.txt mtime, names switched off
    // beam columns of the last phrase; typing only edits the end, so the start is reused.
    // Dropped (and `epoch` bumped) whenever anything that ranks paths changes, like `cache`.
    memo: RefCell<Memo>,
    epoch: Cell<u32>,
}

#[derive(Default)]
struct Memo {
    toks: Vec<String>,
    beams: Vec<Vec<Path_>>, // beams[i] = unsorted paths that consumed the first i tokens
}

#[derive(Clone, Debug, PartialEq)]
pub struct Suggestion {
    pub text: String,
    pub words: Vec<String>,
}

/// Sum "n<TAB>w1 w2<TAB>count" lines into `counts`; a missing file is empty.
fn read_counts(path: &Path, counts: &mut Counts) {
    let Ok(text) = fs::read_to_string(path) else { return };
    for line in text.lines() {
        let mut it = line.split('\t');
        let (Some(n), Some(ws), Some(c)) = (it.next(), it.next(), it.next()) else { continue };
        let (Ok(n), Ok(c)) = (n.parse::<usize>(), c.parse::<u64>()) else { continue };
        if (1..=3).contains(&n) {
            *counts[n - 1].entry(ws.to_string()).or_default() += c;
        }
    }
}

/// mtime + length of `dir/user.tsv`, None if missing. Length catches appends within one mtime tick.
fn user_stamp(dir: &Path) -> Option<(SystemTime, u64)> {
    let m = fs::metadata(dir.join("user.tsv")).ok()?;
    Some((m.modified().ok()?, m.len()))
}

/// Words of a path as a shared linked list (newest first), so extending a path copies nothing.
struct Node {
    word: String, // Khmer word, or raw latin token
    prev: Option<Arc<Node>>,
}

#[derive(Clone)]
struct Path_ {
    last: Arc<Node>,
    score: f32,
    neg: bool, // a negation is waiting for its ទេ
}

impl Engine {
    /// `dir` holds lexicon.tsv + ngrams.tsv; `user_dir` (created on first pick) holds user.tsv + picks.tsv.
    pub fn load(dir: &Path, user_dir: Option<&Path>) -> std::io::Result<Engine> {
        let mut words = Vec::new();
        let mut spellings = Vec::new();
        let lexicon = fs::read_to_string(dir.join("lexicon.tsv"))?;
        let generated = fs::read_to_string(dir.join("generated.tsv")).unwrap_or_default(); // optional
        let mut first_generated = 0;
        for (i, text) in [lexicon, generated].iter().enumerate() {
            if i == 1 {
                first_generated = words.len();
            }
            for line in text.lines() {
                let Some((word, romans)) = line.split_once('\t') else { continue };
                for r in romans.split(',') {
                    spellings.push((r.as_bytes().to_vec(), words.len() as u32));
                }
                words.push(word.to_string());
            }
        }
        let ngrams = dir.join("ngrams.tsv");
        fs::metadata(&ngrams)?; // fail loudly if data is missing; user.tsv may not exist yet
        let (mut counts, mut user) = (Counts::default(), Counts::default());
        read_counts(&ngrams, &mut counts);
        let user_seen = user_dir.and_then(user_stamp); // before reading: a write in between re-reads
        if let Some(u) = user_dir {
            read_counts(&u.join("user.tsv"), &mut user);
        }
        let total = counts[0].values().sum::<u64>() as f32;
        let english: HashMap<String, f32> = fs::read_to_string(dir.join("english.tsv"))
            .unwrap_or_default() // optional: without it, English words fall back to raw latin
            .lines()
            .filter_map(|l| l.split_once('\t'))
            .filter_map(|(w, c)| Some((w.to_string(), c.parse().ok()?)))
            .collect();
        let en_total = english.iter().filter(|(w, _)| !w.contains(' ')).map(|(_, c)| c).sum();
        let mut by_roman: Vec<u32> = (0..spellings.len() as u32).collect();
        by_roman.sort_by(|&a, &b| spellings[a as usize].0.cmp(&spellings[b as usize].0));
        Ok(Engine {
            words,
            by_roman,
            first_generated,
            spellings,
            counts,
            user: RefCell::new(user),
            user_seen: Cell::new(user_seen),
            user_dir: user_dir.map(Path::to_path_buf),
            total,
            english,
            en_total,
            cache: RefCell::default(),
            settings: RefCell::default(),
            memo: RefCell::default(),
            epoch: Cell::new(0),
        })
    }

    /// Whether switch `name` (one of SETTINGS) is on. Re-reads settings.txt when it changed.
    pub fn setting(&self, name: &str) -> bool {
        let Some(dir) = &self.user_dir else { return true };
        let mtime = fs::metadata(dir.join("settings.txt")).and_then(|m| m.modified()).ok();
        let mut s = self.settings.borrow_mut();
        if s.0 != mtime {
            *s = (mtime, read_settings(dir));
            self.invalidate(); // candidates depend on "generated", paths on "english"
        }
        !s.1.contains(name)
    }

    /// Re-reads user.tsv when it changed on disk: deleted to reset learning, or another process picked.
    fn sync_user(&self) {
        let Some(dir) = &self.user_dir else { return };
        let seen = user_stamp(dir);
        if self.user_seen.get() != seen {
            let mut user = Counts::default();
            read_counts(&dir.join("user.tsv"), &mut user);
            *self.user.borrow_mut() = user;
            self.user_seen.set(seen);
            self.invalidate(); // pre-ranking and path scores use the counts
        }
    }

    fn invalidate(&self) {
        self.cache.borrow_mut().clear();
        *self.memo.borrow_mut() = Memo::default();
        self.epoch.set(self.epoch.get().wrapping_add(1));
    }

    fn count(&self, key: &str) -> f32 {
        let n = key.split(' ').count();
        let get = |c: &Counts| c[n - 1].get(key).copied().unwrap_or(0) as f32;
        get(&self.counts) + USER_BOOST * get(&self.user.borrow())
    }

    /// Remember that `typed` produced suggestion `s`: its 1-3 grams get user counts,
    /// appended to user.tsv; the pick is logged to picks.tsv (future eval / training data).
    pub fn learn(&mut self, typed: &str, s: &Suggestion) -> std::io::Result<()> {
        if !self.setting("learn") {
            return Ok(());
        }
        self.sync_user(); // add to what is on disk now, not to the counts of a deleted file
        let mut padded = vec!["<s>".to_string(), "<s>".to_string()];
        padded.extend(s.words.iter().cloned());
        let mut lines = String::new();
        for i in 2..padded.len() {
            for n in 1..=3 {
                let mut key: Vec<&str> = padded[i + 1 - n..i].iter().map(|w| ctx(w)).collect();
                key.push(&padded[i]); // context as the LM sees it, the word itself as picked
                let key = key.join(" ");
                *self.user.get_mut()[n - 1].entry(key.clone()).or_default() += 1;
                lines += &format!("{n}\t{key}\t1\n");
            }
        }
        self.invalidate(); // pre-ranking and path scores use counts that just changed
        let Some(dir) = &self.user_dir else { return Ok(()) };
        fs::create_dir_all(dir)?;
        let append = |name: &str, text: &str| -> std::io::Result<()> {
            OpenOptions::new().create(true).append(true).open(dir.join(name))?.write_all(text.as_bytes())
        };
        let wrote = append("user.tsv", &lines);
        // only our lines were added: `user` already matches, no re-read. Anything else (another
        // process appended in between, a failed write) leaves the stamp stale so the next sync re-reads.
        let want = self.user_seen.get().map_or(0, |s| s.1) + lines.len() as u64;
        self.user_seen.set(user_stamp(dir).filter(|s| s.1 == want));
        wrote?;
        append("picks.tsv", &format!("{}\t{}\n", typed.trim(), s.text))
    }

    /// Learn the `index`-th suggestion for `input` (same order `suggest` returned).
    pub fn pick(&mut self, input: &str, index: usize) -> std::io::Result<()> {
        match self.suggest(input, index + 1).get(index).cloned() {
            Some(s) => self.learn(input, &s),
            None => Ok(()),
        }
    }

    /// Stupid backoff log-score of `w` after context (u, v).
    fn lm(&self, u: &str, v: &str, w: &str) -> f32 {
        let (tri, uv) = (self.count(&format!("{u} {v} {w}")), self.count(&format!("{u} {v}")));
        if tri > 0.0 && uv > 0.0 {
            return (tri / uv).ln();
        }
        let (bi, cv) = (self.count(&format!("{v} {w}")), self.count(v));
        if bi > 0.0 && cv > 0.0 {
            return BACKOFF.ln() + (bi / cv).ln();
        }
        2.0 * BACKOFF.ln() + (self.count(w).max(0.5) / self.total).ln()
    }

    fn is_english(&self, w: &str) -> bool {
        is_latin(w) && self.english.contains_key(&normalize(w))
    }

    /// English word `w` after (u, v): Khmer LM's "foreign word here" times English frequency
    /// (English bigram if `v` is English too), or the user's own picks of `w`, whichever is higher.
    fn lm_english(&self, u: &str, v: &str, w: &str) -> f32 {
        let (vn, wn) = (normalize(v), normalize(w));
        let uni = (self.english[&wn] / self.en_total).ln();
        let english = match (self.is_english(v), self.english.get(&format!("{vn} {wn}"))) {
            (true, Some(bi)) => (bi / self.english[&vn]).ln(),
            (true, None) => BACKOFF.ln() + uni,
            (false, _) => self.lm(ctx(u), ctx(v), "<oth>") + uni,
        };
        english.max(self.lm(ctx(u), ctx(v), w))
    }

    /// Word id -> closest spelling distance (<= `max_dist`) to `t`. Walks the spellings in sorted
    /// order, keeping the edit-distance columns of the shared prefix, and stops extending a spelling
    /// once its column cannot get back under `max_dist`. Same distances as `dist`.
    fn scan(&self, t: &str, max_dist: f32, generated_on: bool) -> HashMap<u32, f32> {
        let (t, h) = (t.as_bytes(), t.len() + 1);
        let mut best: HashMap<u32, f32> = HashMap::new();
        // col[j*h + i] = cost of typed t[..i] against spelling prefix s[..j]
        let mut col: Vec<f32> = (0..h).scan(0.0, |acc, i| {
            let v = *acc;
            *acc += if i < t.len() { ins_cost(t[i]) } else { 0.0 };
            Some(v)
        }).collect();
        let mut min = vec![0.0_f32]; // column minimums
        let (mut prev, mut reached): (&[u8], usize) = (&[], 0); // levels valid for `prev`
        for &si in &self.by_roman {
            let (s, id) = &self.spellings[si as usize];
            if !generated_on && *id as usize >= self.first_generated {
                continue;
            }
            let mut j = prev.iter().zip(s).take_while(|(a, b)| a == b).count().min(reached);
            col.resize(col.len().max((s.len() + 1) * h), 0.0);
            min.resize(min.len().max(s.len() + 1), 0.0);
            while j < s.len() && min[j] <= max_dist {
                let (before, c) = (if j == 0 { 0 } else { s[j - 1] }, s[j]);
                let del = del_cost(c, before);
                col[(j + 1) * h] = col[j * h] + del;
                let mut m = col[(j + 1) * h];
                for i in 0..t.len() {
                    let v = (col[j * h + i] + sub_cost(t[i], c))
                        .min(col[(j + 1) * h + i] + ins_cost(t[i]))
                        .min(col[j * h + i + 1] + del);
                    col[(j + 1) * h + i + 1] = v;
                    m = m.min(v);
                }
                min[j + 1] = m;
                j += 1;
            }
            (prev, reached) = (s, j);
            let m = s.len();
            let d = (0..=j).map(|k| col[k * h + t.len()] + TAIL_COST * (m - k) as f32).fold(f32::INFINITY, f32::min);
            if d <= max_dist {
                let e = best.entry(*id).or_insert(f32::INFINITY);
                *e = e.min(d);
            }
        }
        best
    }

    /// Top Khmer words for one typed token, scored without context: (word, -SPELL_WEIGHT*dist).
    /// `max_dist` is MAX_DIST for one typed token, JOIN_MAX_DIST for several tokens typed as one word.
    pub fn candidates(&self, token: &str, max_dist: f32) -> Vec<(String, f32)> {
        let t = normalize(token);
        if t.is_empty() {
            return vec![];
        }
        let generated_on = self.setting("generated"); // before the cache: a change clears it
        self.sync_user(); // same
        let key = format!("{max_dist}\t{t}");
        if let Some(hit) = self.cache.borrow().get(&key) {
            return hit.clone();
        }
        let best = self.scan(&t, max_dist, generated_on);
        let mut out: Vec<(String, f32)> = best
            .into_iter()
            .map(|(id, d)| (self.words[id as usize].clone(), if d == 0.0 { EXACT_BONUS } else { -SPELL_WEIGHT * d }))
            .collect();
        // pre-rank by spelling + unigram so the beam sees plausible words first; exact spellings
        // always survive the cut, so a rare word (count 1, e.g. rule-generated) typed exactly isn't
        // crowded out by common near-misses
        out.sort_by(|a, b| {
            let sa = a.1 + (self.count(&a.0).max(0.5) / self.total).ln();
            let sb = b.1 + (self.count(&b.0).max(0.5) / self.total).ln();
            (b.1 == EXACT_BONUS).cmp(&(a.1 == EXACT_BONUS)).then(sb.total_cmp(&sa)).then_with(|| a.0.cmp(&b.0))
        });
        out.truncate(CANDIDATES_PER_TOKEN);
        let mut cache = self.cache.borrow_mut();
        if cache.len() > 2000 {
            cache.clear();
        }
        cache.insert(key, out.clone());
        out
    }

    /// Top `k` Khmer renderings of a space-separated romanized phrase.
    pub fn suggest(&self, input: &str, k: usize) -> Vec<Suggestion> {
        let toks = tokens(input);
        let n = toks.len();
        let english_on = self.setting("english"); // before the memo: a change drops it
        self.sync_user(); // same
        let epoch = self.epoch.get();
        // beams[i] = paths that consumed the first i tokens; a word may consume 1..=MAX_JOIN tokens.
        // beams[i] only depends on toks[..i], so those of an unchanged start are kept as they were.
        let Memo { toks: old, mut beams } = std::mem::take(&mut *self.memo.borrow_mut());
        let keep = old.iter().zip(&toks).take_while(|(a, b)| a == b).count();
        beams.truncate(keep + 1);
        beams.resize(n + 1, Vec::new());
        if keep == 0 {
            let node = |w: &str, prev| Arc::new(Node { word: w.into(), prev });
            beams[0] = vec![Path_ { last: node("<s>", Some(node("<s>", None))), score: 0.0, neg: false }];
        }
        for i in 0..n {
            if i + MAX_JOIN <= keep {
                continue; // everything it feeds is kept
            }
            let mut here = beams[i].clone();
            here.sort_by(|a, b| b.score.total_cmp(&a.score));
            here.truncate(BEAM);
            for len in 1..=MAX_JOIN.min(n - i) {
                if len > 1 && toks[i..i + len].iter().any(|t| is_punct(t)) {
                    break; // a word never spans punctuation
                }
                if i + len <= keep {
                    continue;
                }
                let cands = if is_punct(toks[i]) {
                    vec![(toks[i].to_string(), 0.0)] // kept as typed
                } else if len == 1 {
                    let mut c = self.candidates(toks[i], MAX_DIST);
                    let english = english_on && self.english.contains_key(&normalize(toks[i]));
                    c.push((toks[i].to_string(), if english { 0.0 } else { RAW_PENALTY })); // English: exact spelling
                    c
                } else {
                    let mut c = self.candidates(&toks[i..i + len].concat(), JOIN_MAX_DIST);
                    c.iter_mut().for_each(|(_, s)| *s -= JOIN_PENALTY);
                    c
                };
                for p in &here {
                    let v = &p.last.word;
                    let u = &p.last.prev.as_ref().expect("two <s> start").word;
                    for (w, spell) in &cands {
                        let lm = if *spell == RAW_PENALTY || is_punct(w) {
                            0.0
                        } else if is_latin(w) {
                            let switch = if self.is_english(v) { 0.0 } else { EN_SWITCH };
                            LM_WEIGHT * self.lm_english(u, v, w) - switch
                        } else {
                            LM_WEIGHT * self.lm(ctx(u), ctx(v), w)
                        };
                        let closes = p.neg && w == NEG_CLOSE;
                        let neg = (p.neg || NEGATIONS.contains(&w.as_str())) && !closes && !is_punct(w);
                        let bonus = if closes { NEG_BONUS } else { 0.0 };
                        let last = Arc::new(Node { word: w.clone(), prev: Some(p.last.clone()) });
                        beams[i + len].push(Path_ { last, score: p.score + lm + spell + bonus, neg });
                    }
                }
            }
        }
        let mut beam = beams[n].clone();
        if self.epoch.get() == epoch {
            *self.memo.borrow_mut() = Memo { toks: toks.iter().map(|t| t.to_string()).collect(), beams };
        }
        beam.sort_by(|a, b| b.score.total_cmp(&a.score));
        let mut out: Vec<Suggestion> = Vec::new();
        for p in beam {
            let mut words = Vec::new();
            let mut node = Some(&p.last);
            while let Some(nd) = node {
                words.push(nd.word.clone());
                node = nd.prev.as_ref();
            }
            words.truncate(words.len() - 2); // the two <s>
            words.reverse();
            let text = join(&words);
            if !text.is_empty() && !out.iter().any(|s| s.text == text) {
                out.push(Suggestion { text, words });
            }
            if out.len() == k {
                break;
            }
        }
        out
    }
}

/// Khmer words join without spaces; latin tokens keep spaces around them;
/// punctuation sticks to the word before it and has a space after.
fn join(words: &[String]) -> String {
    let mut s = String::new();
    for (i, w) in words.iter().enumerate() {
        if i > 0 && !is_punct(w) && (is_latin(w) || is_latin(&words[i - 1]) || is_punct(&words[i - 1])) {
            s.push(' ');
        }
        s.push_str(w);
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spelling_distance() {
        assert_eq!(dist(b"knhom", b"knhom"), 0.0);
        assert!(dist(b"knhom", b"khnhoam") < 1.0); // dropped h + a
        assert!(dist(b"kn", b"knhom") < 1.0); // prefix completion
        assert!(dist(b"jea", b"chea") < 1.5); // j/c swap + dropped h
        assert!(dist(b"pinng", b"pirnng") < 0.5); // vowel-length r dropped
        assert!(dist(b"xyz", b"knhom").is_infinite());
    }

    #[test]
    fn phrase_with_real_data() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/out");
        let Ok(e) = Engine::load(&dir, None) else { return }; // run data/build.py first
        assert_eq!(e.suggest("knhom tov sala rean", 1)[0].text, "ខ្ញុំទៅសាលារៀន");
        // one Khmer word typed as two tokens
        assert!(e.suggest("pin ng ot loy tt man", 1)[0].text.starts_with("ប៉ុណ្ណឹង"));
        // English words stay English unless a common chat spelling reads better as Khmer
        assert_eq!(e.suggest("thank you bong", 1)[0].text, "thank you បង");
        assert_eq!(e.suggest("mean", 1)[0].text, "មាន");
        assert!(e.suggest("mean", 9).iter().any(|s| s.text == "mean")); // IMEs show 9
        // rare words (count 1: hand-added or rule-generated spellings) typed exactly still show up
        for (typed, want) in [("zin", "ហ្សីន"), ("fesbuk", "ហ្វេសប៊ុក")] {
            assert!(e.suggest(typed, 9).iter().any(|s| s.text == want), "{typed} buried");
        }
        // punctuation stays as typed and doesn't break the words around it
        assert_eq!(tokens("knhom, tov te?!"), ["knhom", ",", "tov", "te", "?!"]);
        assert_eq!(e.suggest("knhom, tov sala rean?", 1)[0].text, "ខ្ញុំ, ទៅសាលារៀន?");
        // negation frame closes with ទេ, however far back the negation is; plain តែ stays
        assert_eq!(e.suggest("ot mean luy te", 1)[0].text, "អត់មានលុយទេ");
        assert_eq!(e.suggest("knhom mean te muoy", 1)[0].text, "ខ្ញុំមានតែមួយ");
    }

    #[test]
    fn settings_switch_features_live() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/out");
        let user = std::env::temp_dir().join(format!("typer-settings-{}", std::process::id()));
        let _ = fs::remove_dir_all(&user);
        let Ok(mut e) = Engine::load(&dir, Some(&user)) else { return };
        let has = |e: &Engine, typed: &str, want: &str| e.suggest(typed, 9).iter().any(|s| s.text == want);
        assert!(SETTINGS.iter().all(|k| e.setting(k))); // no settings.txt: all on
        assert!(has(&e, "fesbuk", "ហ្វេសប៊ុក") && has(&e, "thank you bong", "thank you បង"));

        write_setting(&user, "generated", false).unwrap();
        write_setting(&user, "english", false).unwrap();
        write_setting(&user, "learn", false).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(20)); // distinct mtime
        assert!(!has(&e, "fesbuk", "ហ្វេសប៊ុក"), "generated words switched off");
        assert!(!has(&e, "thank you bong", "thank you បង"), "English switched off");
        e.pick("ah ach", 0).unwrap();
        assert!(!user.join("picks.tsv").exists(), "learning switched off");
        assert!(e.setting("badge"));

        write_setting(&user, "generated", true).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(20));
        assert!(has(&e, "fesbuk", "ហ្វេសប៊ុក"));
        fs::remove_dir_all(&user).unwrap();
    }

    #[test]
    fn learning_flips_ranking_and_persists() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/out");
        let user = std::env::temp_dir().join(format!("typer-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&user);
        let Ok(mut e) = Engine::load(&dir, Some(&user)) else { return };
        let before = e.suggest("ah ach", 9); // IMEs show 9
        assert_ne!(before[0].text, "អាអាចម៍");
        let want = before.iter().find(|s| s.text == "អាអាចម៍").expect("in top 9").clone();
        e.learn("ah ach", &want).unwrap();
        assert_eq!(e.suggest("ah ach", 1)[0].text, "អាអាចម៍");
        let reloaded = Engine::load(&dir, Some(&user)).unwrap();
        assert_eq!(reloaded.suggest("ah ach", 1)[0].text, "អាអាចម៍");
        assert!(fs::read_to_string(user.join("picks.tsv")).unwrap().contains("ah ach\tអាអាចម៍"));
        fs::remove_dir_all(&user).unwrap();
    }

    fn learned(e: &Engine) -> Counts {
        e.user.borrow().clone()
    }

    #[test]
    fn learning_follows_user_tsv_live() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/out");
        let user = std::env::temp_dir().join(format!("typer-live-{}", std::process::id()));
        let _ = fs::remove_dir_all(&user);
        let Ok(mut e) = Engine::load(&dir, Some(&user)) else { return };
        let fresh = || Engine::load(&dir, Some(&user)).unwrap();
        let before = e.suggest("ah ach", 9);
        let want = before.iter().find(|s| s.text == "អាអាចម៍").expect("in top 9").clone();
        // own pick, then suggest: counts match the file, not doubled by re-reading our own append
        e.learn("ah ach", &want).unwrap();
        assert_eq!(e.user_seen.get(), user_stamp(&user), "own append needs no re-read");
        assert_eq!(e.suggest("ah ach", 1)[0].text, "អាអាចម៍");
        assert_eq!(learned(&e), learned(&fresh()));

        // folder deleted (the README's reset): same engine forgets, no restart
        fs::remove_dir_all(&user).unwrap();
        assert_eq!(e.suggest("ah ach", 9), before);
        assert!(learned(&e).iter().all(HashMap::is_empty));

        // a pick after the reset counts once and persists, without the forgotten one
        e.learn("ah ach", &want).unwrap();
        assert_eq!(e.suggest("ah ach", 1)[0].text, "អាអាចម៍");
        assert_eq!(learned(&e), learned(&fresh()));
        assert_eq!(fresh().suggest("ah ach", 1)[0].text, "អាអាចម៍");

        // another process picks: seen on the next suggest, and our next pick keeps it
        let mut other = fresh();
        let s = other.suggest("knhom tov", 9)[1].clone();
        other.learn("knhom tov", &s).unwrap();
        e.suggest("knhom tov", 1);
        assert_eq!(learned(&e), learned(&fresh()));
        assert!(learned(&e)[1].keys().any(|k| k.ends_with(&s.words[1])));
        e.learn("ah ach", &want).unwrap(); // `other` is now behind, then appends again
        other.learn("knhom tov", &s).unwrap();
        e.suggest("ah ach", 1);
        assert_eq!(learned(&e), learned(&fresh()));

        // user.tsv replaced (emptied) by another process
        fs::write(user.join("user.tsv"), "").unwrap();
        assert_eq!(e.suggest("ah ach", 9), before);
        assert!(learned(&e).iter().all(HashMap::is_empty));
        fs::remove_dir_all(&user).unwrap();
    }

    fn engine() -> Option<Engine> {
        Engine::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/out"), None).ok() // run data/build.py first
    }

    #[test]
    fn prefix_scan_matches_brute_force() {
        let Some(e) = engine() else { return };
        for t in ["kn", "pinng", "ach", "a", "knhom", "jea", "xyz", "sala", "thank", "pirnng", "ot", "muoy"] {
            for (max, generated) in [(MAX_DIST, true), (JOIN_MAX_DIST, true), (MAX_DIST, false)] {
                let mut want: HashMap<u32, f32> = HashMap::new();
                for (s, id) in &e.spellings {
                    let d = dist(t.as_bytes(), s);
                    if d <= max && (generated || (*id as usize) < e.first_generated) {
                        let x = want.entry(*id).or_insert(f32::INFINITY);
                        *x = x.min(d);
                    }
                }
                let got = e.scan(t, max, generated);
                let bad: Vec<_> = want.keys().chain(got.keys()).filter(|k| got.get(k) != want.get(k)).take(4).collect();
                let show: Vec<_> = bad.iter().map(|k| (got.get(k), want.get(k))).collect();
                assert!(bad.is_empty(), "{t} {max} {generated}: (got, want) {show:?}");
            }
        }
    }

    #[test]
    fn reusing_the_beam_gives_the_same_suggestions() {
        let (Some(e), Some(fresh)) = (engine(), engine()) else { return };
        let phrases = [
            "knhom tov sala rean nov phnom penh jea muoy mit",
            "ot mean luy te, bong?",
            "thank you bong, pin ng ot loy tt man",
            "knhom mean te muoy",
            "hello world fesbuk zin 123",
            "pin ng ot",
        ];
        let mut inputs: Vec<String> = Vec::new();
        for p in phrases {
            let ends: Vec<usize> = p.char_indices().map(|(i, c)| i + c.len_utf8()).collect();
            inputs.extend(ends.iter().map(|&end| p[..end].to_string())); // typing
            inputs.extend(ends.iter().rev().map(|&end| p[..end].to_string())); // backspacing into earlier tokens
            inputs.push(p.replace(' ', "  ")); // extra spaces
            inputs.push(p.split(' ').rev().collect::<Vec<_>>().join(" ")); // completely different
        }
        inputs.push(String::new());
        for input in &inputs {
            fresh.invalidate(); // from scratch
            for k in [1, 9] {
                assert_eq!(e.suggest(input, k), fresh.suggest(input, k), "{input:?}");
            }
        }
    }
}
