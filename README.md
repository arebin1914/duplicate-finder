# dupfind

Fast duplicate file finder written in Rust, using BLAKE3 hashing.

## Install

**One-liner:**
```sh
curl -fsSL https://raw.githubusercontent.com/arebin1914/duplicate-finder/master/install.sh | bash
```

The script auto-installs Rust and git if missing, with interactive prompts.

**Update:** Re-run the same command to update to the latest version.

**Uninstall:**
```sh
curl -fsSL https://raw.githubusercontent.com/arebin1914/duplicate-finder/master/install.sh | bash -s -- --uninstall
```

**Or manually:**
```sh
git clone git@github.com:arebin1914/duplicate-finder.git
cd duplicate-finder
cargo install --path .
```

## Usage

```
dupfind [directory] [options]
```

By default, prompts for a minimum file size filter:

```
Filter by minimum file size:
  [1] Everything (no size limit)
  [2] Larger than 10 MB
  [3] Larger than 50 MB
  [4] Larger than 100 MB
  [5] Custom size
```

### Options

| Flag | Description |
|------|-------------|
| `-m, --min-size SIZE` | Skip prompt, set minimum size (e.g. `1K`, `5M`, `1G`) |
| `-i, --interactive` | Force interactive size prompt |
| `-x, --exclude DIR` | Exclude directories (repeatable) |
| `--delete` | Interactively delete duplicates (keeps first) |
| `--json` | JSON output |
| `--no-size` | Hide file sizes in output |
| `--follow-symlinks` | Follow symbolic links |
| `-h, --help` | Show help |

### Examples

```sh
# Scan current directory with prompt
dupfind

# Scan specific directory, files >= 50MB
dupfind ~/Downloads -m 50M

# Exclude .git and node_modules, output JSON
dupfind . -x /path/to/.git /path/to/node_modules --json

# Find and delete duplicates interactively
dupfind ~/Photos --delete
```

## Features

- BLAKE3 hashing for fast, secure comparison
- Progress spinner during scan and hash phases
- Groups duplicates by size first, then hash
- Interactive size prompt
- Interactive deletion mode
- JSON output for scripting
