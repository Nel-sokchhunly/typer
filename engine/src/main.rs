//! typer "knhom tov sala rean"     one phrase
//! typer                           REPL, one phrase per line; a number after it picks (learns) that suggestion
//! typer eval eval/test.tsv        top-1 / top-3 accuracy on "typed<TAB>expected" lines
use std::io::{self, BufRead, Write};
use std::path::Path;
use std::time::Instant;
use typer::{Engine, Suggestion};

fn main() {
    let dir = std::env::var("TYPER_DATA").unwrap_or_else(|_| "data/out".into());
    let t0 = Instant::now();
    let user = std::env::var("TYPER_USER").unwrap_or_else(|_| "data/user".into());
    let mut engine = Engine::load(Path::new(&dir), Some(Path::new(&user))).unwrap_or_else(|e| {
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
            let got: Vec<String> = got.into_iter().map(|s| s.text).collect();
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

    let show = |engine: &Engine, input: &str| -> Vec<Suggestion> {
        let t = Instant::now();
        let out = engine.suggest(input, 5);
        println!("{input} ({:?})", t.elapsed());
        for (i, s) in out.iter().enumerate() {
            println!("  {}. {}", i + 1, s.text);
        }
        out
    };
    if !args.is_empty() {
        show(&engine, &args.join(" "));
        return;
    }
    let (mut last_input, mut last) = (String::new(), Vec::new());
    print!("> ");
    io::stdout().flush().ok();
    for line in io::stdin().lock().lines().map_while(Result::ok) {
        let line = line.trim();
        if let Some(s) = line.parse::<usize>().ok().and_then(|i| last.get(i.wrapping_sub(1))) {
            match engine.learn(&last_input, s) {
                Ok(()) => println!("  learned {}", s.text),
                Err(e) => println!("  learn failed: {e}"),
            }
        } else if !line.is_empty() {
            last = show(&engine, line);
            last_input = line.to_string();
        }
        print!("> ");
        io::stdout().flush().ok();
    }
}
