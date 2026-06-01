use std::collections::BTreeMap;
use std::ffi::OsStr;
use std::fs;
use std::io::{self, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use jwalk::WalkDir;
use rayon::prelude::*;

const CHUNK_SIZE: usize = 256 * 1024;

fn format_size(size: u64) -> String {
    const UNITS: &[&str] = &["B", "K", "M", "G", "T"];
    let mut s = size as f64;
    for unit in UNITS {
        if s < 1024.0 {
            return format!("{:.1}{}", s, unit);
        }
        s /= 1024.0;
    }
    format!("{:.1}P", s)
}

fn file_hash(path: &Path) -> io::Result<String> {
    let f = fs::File::open(path)?;
    let mut reader = BufReader::with_capacity(CHUNK_SIZE, f);
    let mut hasher = blake3::Hasher::new();
    let mut buf = vec![0u8; CHUNK_SIZE];
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().to_hex().to_string())
}

fn scan_files(
    root: &Path,
    exclude: &[PathBuf],
    min_size: u64,
    follow_links: bool,
    scanned: &AtomicU64,
) -> BTreeMap<u64, Vec<PathBuf>> {
    let entries: Vec<_> = WalkDir::new(root)
        .follow_links(follow_links)
        .skip_hidden(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.file_type().is_file()
                && !exclude.iter().any(|x| e.path() == *x)
        })
        .collect();

    let size_map: BTreeMap<u64, Vec<PathBuf>> = entries
        .par_iter()
        .filter_map(|entry| {
            let meta = match entry.metadata() {
                Ok(m) => m,
                Err(_) => return None,
            };
            if meta.len() < min_size {
                return None;
            }
            scanned.fetch_add(1, Ordering::Relaxed);
            Some((meta.len(), entry.path()))
        })
        .fold(BTreeMap::<u64, Vec<PathBuf>>::new, |mut acc, (size, path)| {
            acc.entry(size).or_default().push(path);
            acc
        })
        .reduce(BTreeMap::<u64, Vec<PathBuf>>::new, |mut a, b| {
            for (k, v) in b {
                a.entry(k).or_default().extend(v);
            }
            a
        });

    size_map
}

fn spinner_frame(phase: &str, count: u64, elapsed: f64) -> String {
    let spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    let idx = (elapsed * 10.0) as usize % spinner.len();
    format!("\r {}  {} ... {} files", spinner[idx], phase, count)
}

fn run_spinner(
    label: &'static str,
    count: Arc<AtomicU64>,
    running: Arc<std::sync::atomic::AtomicBool>,
) {
    let start = Instant::now();
    while running.load(Ordering::Relaxed) {
        let elapsed = start.elapsed().as_secs_f64();
        let msg = spinner_frame(label, count.load(Ordering::Relaxed), elapsed);
        let _ = io::stderr().write(msg.as_bytes());
        let _ = io::stderr().flush();
        std::thread::sleep(Duration::from_millis(80));
    }
    let _ = io::stderr().write(b"\r\x1b[K");
    let _ = io::stderr().flush();
}

fn prompt_min_size() -> u64 {
    let options: [(&str, u64); 5] = [
        ("Everything (no size limit)", 0),
        ("Larger than 10 MB", 10 * 1024 * 1024),
        ("Larger than 50 MB", 50 * 1024 * 1024),
        ("Larger than 100 MB", 100 * 1024 * 1024),
        ("Custom size", u64::MAX),
    ];

    eprintln!("Filter by minimum file size:");
    for (i, (label, _)) in options.iter().enumerate() {
        eprintln!("  [{}] {}", i + 1, label);
    }
    eprint!("Choose [1-{}]: ", options.len());
    io::stderr().flush().ok();

    let mut input = String::new();
    io::stdin().read_line(&mut input).ok();
    let choice = input.trim().parse::<usize>().unwrap_or(1);

    if choice == 0 || choice > options.len() {
        return 0;
    }

    let (_, size) = options[choice - 1];
    if size != u64::MAX {
        return size;
    }

    eprint!("Enter minimum size (e.g. 10M, 1G, 500K): ");
    io::stderr().flush().ok();
    input.clear();
    io::stdin().read_line(&mut input).ok();
    let s = input.trim();
    if let Some(s) = s.strip_suffix(|c: char| c == 'K' || c == 'k') {
        (s.parse::<f64>().unwrap_or(0.0) * 1024.0) as u64
    } else if let Some(s) = s.strip_suffix(|c: char| c == 'M' || c == 'm') {
        (s.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0) as u64
    } else if let Some(s) = s.strip_suffix(|c: char| c == 'G' || c == 'g') {
        (s.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0 * 1024.0) as u64
    } else if let Some(s) = s.strip_suffix(|c: char| c == 'T' || c == 't') {
        (s.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0 * 1024.0 * 1024.0) as u64
    } else {
        s.parse::<u64>().unwrap_or(0)
    }
}

const VERSION: &str = env!("BUILD_GIT_VERSION");

fn check_update() {
    let url = "https://api.github.com/repos/arebin1914/duplicate-finder/tags?per_page=1";
    let agent = ureq::Agent::new_with_defaults();
    let resp = match agent.get(url)
        .header("User-Agent", "dupfind")
        .header("Accept", "application/json")
        .call()
    {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Update check failed: {}", e);
            return;
        }
    };
    let body = match resp.into_body().read_to_string() {
        Ok(b) => b,
        Err(_) => {
            eprintln!("Could not read update response.");
            return;
        }
    };
    let latest_tag = match body.split("\"name\":\"")
        .nth(1)
        .and_then(|s| s.split('"').next())
    {
        Some(t) => t.to_string(),
        None => {
            eprintln!("No releases found on GitHub.");
            return;
        }
    };

    let local = VERSION.trim_start_matches('v');
    let remote = latest_tag.trim_start_matches('v');

    if local == remote || local.starts_with(remote) {
        println!("dupfind {} is up to date.", VERSION);
    } else {
        println!("Update available: {} → {} (latest)", local, latest_tag);
        println!("Reinstall: curl -fsSL https://raw.githubusercontent.com/arebin1914/duplicate-finder/master/install.sh | bash");
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut root = ".".to_string();
    let mut min_size_str: Option<String> = None;
    let mut exclude_dirs: Vec<PathBuf> = Vec::new();
    let mut delete_mode = false;
    let mut json_mode = false;
    let mut no_size = false;
    let mut follow_links = false;
    let mut interactive = false;

    if args.iter().any(|a| a == "--version" || a == "-V") {
        println!("dupfind {}", VERSION);
        return;
    }
    if args.iter().any(|a| a == "--check-update") {
        check_update();
        return;
    }

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-m" | "--min-size" => {
                i += 1;
                min_size_str = args.get(i).cloned();
            }
            "-i" | "--interactive" => interactive = true,
            "-x" | "--exclude" => {
                i += 1;
                while i < args.len() && !args[i].starts_with('-') {
                    exclude_dirs.push(PathBuf::from(&args[i]));
                    i += 1;
                }
                continue;
            }
            "--delete" => delete_mode = true,
            "--json" => json_mode = true,
            "--no-size" => no_size = true,
            "--follow-symlinks" => follow_links = true,
            "-h" | "--help" => {
                println!("Usage: dupfind [directory] [options]");
                println!();
                println!("Options:");
                println!("  -i, --interactive     Prompt for minimum file size interactively");
                println!("  -m, --min-size SIZE   Minimum file size (e.g. 1K, 5M, 1G)");
                println!("  -x, --exclude DIR     Exclude directories (can be repeated)");
                println!("  --delete              Interactively delete duplicates");
                println!("  --json                Output as JSON");
                println!("  --no-size             Hide file sizes");
                println!("  --follow-symlinks     Follow symbolic links");
                println!("  --check-update       Check for newer version on GitHub");
                println!("  -V, --version         Show version");
                println!("  -h, --help            Show this help");
                return;
            }
            _ => {
                if !args[i].starts_with('-') {
                    root = args[i].clone();
                }
            }
        }
        i += 1;
    }

    let root_path = PathBuf::from(&root);
    if !root_path.is_dir() {
        eprintln!("Error: '{}' is not a directory", root);
        std::process::exit(1);
    }

    let root_abs = fs::canonicalize(&root_path).unwrap_or(root_path);

    let min_size = if interactive || min_size_str.is_none() {
        prompt_min_size()
    } else {
        let s = min_size_str.as_ref().unwrap();
        if let Some(s) = s.strip_suffix(|c: char| c == 'K' || c == 'k') {
            (s.parse::<f64>().unwrap_or(0.0) * 1024.0) as u64
        } else if let Some(s) = s.strip_suffix(|c: char| c == 'M' || c == 'm') {
            (s.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0) as u64
        } else if let Some(s) = s.strip_suffix(|c: char| c == 'G' || c == 'g') {
            (s.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0 * 1024.0) as u64
        } else if let Some(s) = s.strip_suffix(|c: char| c == 'T' || c == 't') {
            (s.parse::<f64>().unwrap_or(0.0) * 1024.0 * 1024.0 * 1024.0 * 1024.0) as u64
        } else {
            s.parse::<f64>().unwrap_or(0.0) as u64
        }
    };

    let exclude_abs: Vec<PathBuf> = exclude_dirs
        .into_iter()
        .map(|d| fs::canonicalize(&d).unwrap_or(d))
        .collect();

    let start = Instant::now();

    // Phase 1: Scan
    let scanned = Arc::new(AtomicU64::new(0));
    let running = Arc::new(std::sync::atomic::AtomicBool::new(true));

    let spinner_handle = if !json_mode {
        let s = scanned.clone();
        let r = running.clone();
        Some(std::thread::spawn(move || run_spinner("Scanning", s, r)))
    } else {
        None
    };

    let size_map = scan_files(&root_abs, &exclude_abs, min_size, follow_links, &scanned);

    running.store(false, Ordering::Relaxed);
    if let Some(h) = spinner_handle {
        let _ = h.join();
    }

    let total_files = scanned.load(Ordering::Relaxed);

    // Phase 2: Hash
    let hashed = Arc::new(AtomicU64::new(0));
    let running2 = Arc::new(std::sync::atomic::AtomicBool::new(true));

    let spinner_handle2 = if !json_mode {
        let s = hashed.clone();
        let r = running2.clone();
        Some(std::thread::spawn(move || run_spinner("Hashing", s, r)))
    } else {
        None
    };

    let mut hash_map: BTreeMap<(u64, String), Vec<PathBuf>> = BTreeMap::new();

    let candidates: Vec<(u64, PathBuf)> = size_map
        .iter()
        .filter(|(_, paths)| paths.len() >= 2)
        .flat_map(|(size, paths)| paths.iter().map(move |p| (*size, p.clone())))
        .collect();

    let results: Vec<((u64, String), PathBuf)> = candidates
        .par_iter()
        .filter_map(|(size, path)| {
            file_hash(path).ok().map(|h| {
                hashed.fetch_add(1, Ordering::Relaxed);
                ((*size, h), path.clone())
            })
        })
        .collect();

    for ((size, hash), path) in results {
        hash_map.entry((size, hash)).or_default().push(path);
    }

    running2.store(false, Ordering::Relaxed);
    if let Some(h) = spinner_handle2 {
        let _ = h.join();
    }

    let duplicates: Vec<((u64, String), Vec<PathBuf>)> = hash_map
        .into_iter()
        .filter(|(_, paths)| paths.len() > 1)
        .collect();

    let elapsed = start.elapsed();

    if json_mode {
        let mut json_output = String::from("{\n");
        json_output.push_str("  \"duplicates\": {\n");
        for (i, ((size, hash), paths)) in duplicates.iter().enumerate() {
            json_output.push_str(&format!("    \"{}_{}\": [\n", size, hash));
            for (j, p) in paths.iter().enumerate() {
                let comma = if j < paths.len() - 1 { "," } else { "" };
                json_output.push_str(&format!("      \"{}\"{}", p.display(), comma));
                json_output.push('\n');
            }
            let comma = if i < duplicates.len() - 1 { "," } else { "" };
            json_output.push_str(&format!("    ]{}\n", comma));
        }
        json_output.push_str("  },\n");
        json_output.push_str(&format!("  \"total_files\": {},\n", total_files));
        json_output.push_str(&format!("  \"hashed_candidates\": {}\n", hashed.load(Ordering::Relaxed)));
        json_output.push('}');
        println!("{}", json_output);
        return;
    }

    if duplicates.is_empty() {
        println!("No duplicate files found.");
    } else {
        let mut wasted_bytes = 0u64;
        for (i, ((size, hash), paths)) in duplicates.iter().enumerate() {
            wasted_bytes += size * (paths.len() as u64 - 1);
            println!();
            println!("{}", "=".repeat(60));
            let size_label = if no_size {
                String::new()
            } else {
                format!("  |  {}", format_size(*size))
            };
            println!(
                "Group {} — {} copies{}  |  {}...",
                i + 1,
                paths.len(),
                size_label,
                &hash[..16]
            );
            println!("{}", "=".repeat(60));
            for p in paths {
                println!("  {}", p.display());
            }
        }

        println!();
        println!("{}", "=".repeat(60));
        println!(
            "Summary: {} duplicate group(s), {} in duplicates",
            duplicates.len(),
            format_size(duplicates.iter().map(|((s, _), p)| s * p.len() as u64).sum::<u64>())
        );
        println!("Wasted space: {} (reclaimable)", format_size(wasted_bytes));
        println!("{}", "=".repeat(60));
    }

    println!();
    println!(
        "Scanned: {} files, hashed {} candidates in {:?}",
        total_files,
        hashed.load(Ordering::Relaxed),
        elapsed
    );

    // Interactive delete mode
    if delete_mode && !duplicates.is_empty() {
        for ((size, hash), paths) in &duplicates {
            println!("\nGroup (size={}, hash={}):", size, hash);
            for (i, p) in paths.iter().enumerate() {
                println!("  [{}] {}", i, p.display());
            }
            for i in 1..paths.len() {
                let fname = paths[i].file_name().unwrap_or(OsStr::new("?")).to_string_lossy().to_string();
                print!("  Delete [{}] {}? [y/N/q] ", i, fname);
                io::stdout().flush().ok();
                let mut input = String::new();
                io::stdin().read_line(&mut input).ok();
                let answer = input.trim().to_lowercase();
                if answer == "q" {
                    println!("Stopping deletion.");
                    return;
                }
                if answer == "y" {
                    match fs::remove_file(&paths[i]) {
                        Ok(_) => println!("    Deleted: {}", paths[i].display()),
                        Err(e) => eprintln!("    Error: {}", e),
                    }
                }
            }
        }
    }
}
