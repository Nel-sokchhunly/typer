//! typer "knhom tov sala rean"     one phrase
//! typer                           REPL, one phrase per line
//! typer eval eval/test.tsv        top-1 / top-3 accuracy on "typed<TAB>expected" lines
use std::io::{self, BufRead, Write};
use std::path::Path;
use std::time::Instant;
use typer::Engine;

fn main() {
    let dir = std::env::var("TYPER_DATA").unwrap_or_else(|_| "data/out".into());
    let t0 = Instant::now();
    let engine = Engine::load(Path::new(&dir)).unwrap_or_else(|e| {
        eprintln!("cannot load {dir}: {e} (run python3 data/build.py)");
        std::process::exit(1)
    });
    eprintln!("loaded in {:?}", t0.elapsed());
    let args: Vec<String> = std::env::args().skip(1).collect();

    if args.first().map(String::as_str) == Some("eval") {
        let path = args.get(1).map(String::as_str).unwrap_or("eval/test.tsv");
        let (mut n, mut top1, mut top3) = (0, 0, 0);
        for line in std::fs::read_to_string(path).expect("read eval file").lines() {
            let Some((typed, want)) = line.split_once('\t') else { continue };
            let got = engine.suggest(typed, 3);
            n += 1;
            if got.first().map(String::as_str) == Some(want) {
                top1 += 1;
            } else {
                println!("MISS {typed}\twant {want}\tgot {}", got.join(" | "));
            }
            top3 += got.iter().any(|g| g == want) as usize;
        }
        let pct = |x: usize| 100.0 * x as f32 / n.max(1) as f32;
        println!("n={n} top1={:.1}% top3={:.1}%", pct(top1), pct(top3));
        return;
    }

    let show = |input: &str| {
        let t = Instant::now();
        let out = engine.suggest(input, 5);
        println!("{input} ({:?})", t.elapsed());
        for (i, s) in out.iter().enumerate() {
            println!("  {}. {s}", i + 1);
        }
    };
    if !args.is_empty() {
        return show(&args.join(" "));
    }
    let stdin = io::stdin();
    print!("> ");
    io::stdout().flush().ok();
    for line in stdin.lock().lines().map_while(Result::ok) {
        if !line.trim().is_empty() {
            show(&line);
        }
        print!("> ");
        io::stdout().flush().ok();
    }
}
