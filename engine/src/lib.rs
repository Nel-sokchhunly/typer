//! Sing Khmer engine: space-separated romanized tokens -> ranked Khmer phrases.
//!
//! score(phrase) = sum over tokens of [ LM(word | prev two words) - SPELL_WEIGHT * dist(typed, spelling) ]
//! - dist: weighted edit distance with cheap vowel/h drops and similar-sound swaps, plus prefix completion.
//! - LM: stupid backoff over 1-3 gram counts (data/out/ngrams.tsv) plus the user's own picks (user.tsv).

use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

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

fn is_vowel(c: u8) -> bool {
    matches!(c, b'a' | b'e' | b'i' | b'o' | b'u' | b'y')
}

/// Cost of the user skipping spelling char `c` (knhom vs khnhoam).
fn del_cost(c: u8) -> f32 {
    if is_vowel(c) || c == b'h' { 0.4 } else { 1.2 }
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
    for j in 0..s.len() {
        prev.push(prev[j] + del_cost(s[j]));
    }
    let mut cur = vec![0.0; s.len() + 1];
    for i in 0..t.len() {
        cur[0] = prev[0] + ins_cost(t[i]);
        let mut row_min = cur[0];
        for j in 0..s.len() {
            cur[j + 1] = (prev[j] + sub_cost(t[i], s[j]))
                .min(prev[j + 1] + ins_cost(t[i]))
                .min(cur[j] + del_cost(s[j]));
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

pub fn normalize(token: &str) -> String {
    token.to_lowercase().chars().filter(|c| c.is_ascii_alphanumeric()).collect()
}

type Counts = [HashMap<String, u64>; 3]; // n-gram key "w1 w2" -> count, by n-1

pub struct Engine {
    words: Vec<String>,
    spellings: Vec<(Vec<u8>, u32)>, // (roman, word id)
    counts: Counts,
    user: Counts,
    user_dir: Option<PathBuf>,
    total: f32,
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

#[derive(Clone)]
struct Path_ {
    words: Vec<String>, // Khmer word, or raw latin token
    score: f32,
}

impl Engine {
    /// `dir` holds lexicon.tsv + ngrams.tsv; `user_dir` (created on first pick) holds user.tsv + picks.tsv.
    pub fn load(dir: &Path, user_dir: Option<&Path>) -> std::io::Result<Engine> {
        let mut words = Vec::new();
        let mut spellings = Vec::new();
        for line in fs::read_to_string(dir.join("lexicon.tsv"))?.lines() {
            let Some((word, romans)) = line.split_once('\t') else { continue };
            for r in romans.split(',') {
                spellings.push((r.as_bytes().to_vec(), words.len() as u32));
            }
            words.push(word.to_string());
        }
        let ngrams = dir.join("ngrams.tsv");
        fs::metadata(&ngrams)?; // fail loudly if data is missing; user.tsv may not exist yet
        let (mut counts, mut user) = (Counts::default(), Counts::default());
        read_counts(&ngrams, &mut counts);
        if let Some(u) = user_dir {
            read_counts(&u.join("user.tsv"), &mut user);
        }
        let total = counts[0].values().sum::<u64>() as f32;
        Ok(Engine { words, spellings, counts, user, user_dir: user_dir.map(Path::to_path_buf), total })
    }

    fn count(&self, key: &str) -> f32 {
        let n = key.split(' ').count();
        let get = |c: &Counts| c[n - 1].get(key).copied().unwrap_or(0) as f32;
        get(&self.counts) + USER_BOOST * get(&self.user)
    }

    /// Remember that `typed` produced suggestion `s`: its 1-3 grams get user counts,
    /// appended to user.tsv; the pick is logged to picks.tsv (future eval / training data).
    pub fn learn(&mut self, typed: &str, s: &Suggestion) -> std::io::Result<()> {
        let mut padded = vec!["<s>".to_string(), "<s>".to_string()];
        padded.extend(s.words.iter().cloned());
        let mut lines = String::new();
        for i in 2..padded.len() {
            for n in 1..=3 {
                let key = padded[i + 1 - n..=i].join(" ");
                *self.user[n - 1].entry(key.clone()).or_default() += 1;
                lines += &format!("{n}\t{key}\t1\n");
            }
        }
        let Some(dir) = &self.user_dir else { return Ok(()) };
        fs::create_dir_all(dir)?;
        let append = |name: &str, text: &str| -> std::io::Result<()> {
            OpenOptions::new().create(true).append(true).open(dir.join(name))?.write_all(text.as_bytes())
        };
        append("user.tsv", &lines)?;
        append("picks.tsv", &format!("{}\t{}\n", typed.trim(), s.text))
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

    /// Top Khmer words for one typed token, scored without context: (word, -SPELL_WEIGHT*dist).
    pub fn candidates(&self, token: &str) -> Vec<(String, f32)> {
        let t = normalize(token);
        if t.is_empty() {
            return vec![];
        }
        let mut best: HashMap<u32, f32> = HashMap::new();
        // ponytail: linear scan, redone for every token on every keystroke; cache per token if typing lags of ~38k spellings per token (~ms); index by first consonant if it gets slow
        for (s, id) in &self.spellings {
            let d = dist(t.as_bytes(), s);
            if d <= MAX_DIST {
                let e = best.entry(*id).or_insert(f32::INFINITY);
                *e = e.min(d);
            }
        }
        let mut out: Vec<(String, f32)> = best
            .into_iter()
            .map(|(id, d)| (self.words[id as usize].clone(), if d == 0.0 { EXACT_BONUS } else { -SPELL_WEIGHT * d }))
            .collect();
        // pre-rank by spelling + unigram so the beam sees plausible words first
        out.sort_by(|a, b| {
            let sa = a.1 + (self.count(&a.0).max(0.5) / self.total).ln();
            let sb = b.1 + (self.count(&b.0).max(0.5) / self.total).ln();
            sb.total_cmp(&sa)
        });
        out.truncate(CANDIDATES_PER_TOKEN);
        out
    }

    /// Top `k` Khmer renderings of a space-separated romanized phrase.
    pub fn suggest(&self, input: &str, k: usize) -> Vec<Suggestion> {
        let mut beam = vec![Path_ { words: vec!["<s>".into(), "<s>".into()], score: 0.0 }];
        for token in input.split_whitespace() {
            let mut cands = self.candidates(token);
            cands.push((token.to_string(), RAW_PENALTY));
            let mut next = Vec::with_capacity(beam.len() * cands.len());
            for p in &beam {
                let (u, v) = (&p.words[p.words.len() - 2], &p.words[p.words.len() - 1]);
                for (w, spell) in &cands {
                    let lm = if *spell == RAW_PENALTY { 0.0 } else { LM_WEIGHT * self.lm(u, v, w) };
                    let mut words = p.words.clone();
                    words.push(w.clone());
                    next.push(Path_ { words, score: p.score + lm + spell });
                }
            }
            next.sort_by(|a, b| b.score.total_cmp(&a.score));
            next.truncate(BEAM);
            beam = next;
        }
        let mut out: Vec<Suggestion> = Vec::new();
        for p in beam {
            let text = join(&p.words[2..]);
            if !text.is_empty() && !out.iter().any(|s| s.text == text) {
                out.push(Suggestion { text, words: p.words[2..].to_vec() });
            }
            if out.len() == k {
                break;
            }
        }
        out
    }
}

/// Khmer words join without spaces; latin tokens keep spaces around them.
fn join(words: &[String]) -> String {
    let mut s = String::new();
    for (i, w) in words.iter().enumerate() {
        let latin = |x: &String| x.is_ascii();
        if i > 0 && (latin(w) || latin(&words[i - 1])) {
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
        assert!(dist(b"xyz", b"knhom").is_infinite());
    }

    #[test]
    fn phrase_with_real_data() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/out");
        let Ok(e) = Engine::load(&dir, None) else { return }; // run data/build.py first
        assert_eq!(e.suggest("knhom tov sala rean", 1)[0].text, "ខ្ញុំទៅសាលារៀន");
    }

    #[test]
    fn learning_flips_ranking_and_persists() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../data/out");
        let user = std::env::temp_dir().join(format!("typer-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&user);
        let Ok(mut e) = Engine::load(&dir, Some(&user)) else { return };
        let before = e.suggest("ah ach", 5);
        assert_ne!(before[0].text, "អាអាចម៍");
        let want = before.iter().find(|s| s.text == "អាអាចម៍").expect("in top 5").clone();
        e.learn("ah ach", &want).unwrap();
        assert_eq!(e.suggest("ah ach", 1)[0].text, "អាអាចម៍");
        let reloaded = Engine::load(&dir, Some(&user)).unwrap();
        assert_eq!(reloaded.suggest("ah ach", 1)[0].text, "អាអាចម៍");
        assert!(fs::read_to_string(user.join("picks.tsv")).unwrap().contains("ah ach\tអាអាចម៍"));
        fs::remove_dir_all(&user).unwrap();
    }
}
