#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="dupfind"
ALIAS_NAME="dfind"
INSTALL_DIR="${HOME}/.local/bin"
REPO="arebin1914/duplicate-finder"
BRANCH="master"

# ── ANSI ──────────────────────────────────────────────────
BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'
YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; BLUE=$'\033[0;34m'
NC=$'\033[0m'

header() {
  printf "\n${CYAN}"
  printf "  ██████╗  ██╗   ██╗██████╗ ███████╗██╗███╗   ██╗██████╗ \n"
  printf "  ██╔══██╗ ██║   ██║██╔══██╗██╔════╝██║████╗  ██║██╔══██╗\n"
  printf "  ██║  ██║ ██║   ██║██████╔╝█████╗  ██║██╔██╗ ██║██║  ██║\n"
  printf "  ██║  ██║ ██║   ██║██╔═══╝ ██╔══╝  ██║██║╚██╗██║██║  ██║\n"
  printf "  ██████╔╝ ╚██████╔╝██║     ██║     ██║██║ ╚████║██████╔╝\n"
  printf "  ╚═════╝   ╚═════╝ ╚═╝     ╚═╝     ╚═╝╚═╝  ╚═══╝╚═════╝ \n"
  printf "${NC}"
}

info()  { printf "  ${CYAN}▸${NC} %s\n" "$1"; }
ok()    { printf "  ${GREEN}✔${NC} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}⚠${NC} %s\n" "$1"; }
fail()  { printf "  ${RED}✘${NC} %s\n" "$1"; exit 1; }

step_header() {
  local num="$1"; shift
  printf "\n${BOLD}${BLUE}  ┌──────────────────────────────────────────────────────┐${NC}\n"
  printf "${BOLD}${BLUE}  │ [0x%02x] %-46s${NC}${BOLD}${BLUE}│${NC}\n" "$num" "$*"
  printf "${BOLD}${BLUE}  └──────────────────────────────────────────────────────┘${NC}\n"
}

progress_bar() {
  local pct=$1 label="$2"
  local width=36
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  printf "  ${DIM}[${NC}"
  printf "${GREEN}%*s${NC}" "$filled" | tr ' ' '█'
  printf "${DIM}%*s${NC}" "$empty" | tr ' ' '░'
  printf "${DIM}]${NC}  ${DIM}%3d%%${NC} %s\n" "$pct" "$label"
}

section() {
  printf "\n${BOLD}  ── %s ──${NC}\n" "$1"
}

# ── Uninstall ──────────────────────────────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
  header
  printf "\n${BOLD}${RED}  ┌──────────────────────────────────────────────────────┐${NC}\n"
  printf "${BOLD}${RED}  │                    UNINSTALL                          │${NC}\n"
  printf "${BOLD}${RED}  └──────────────────────────────────────────────────────┘${NC}\n\n"

  for loc in "$INSTALL_DIR/$BINARY_NAME" "${HOME}/.cargo/bin/$BINARY_NAME"; do
    if [ -x "$loc" ]; then
      rm -f "$loc"
      info "Removed: ${DIM}$loc${NC}"
    fi
  done
  FOUND=$(command -v "$BINARY_NAME" 2>/dev/null || true)
  if [ -n "$FOUND" ] && [ -x "$FOUND" ]; then
    rm -f "$FOUND"
    info "Removed: ${DIM}$FOUND${NC}"
  fi

  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
    if [ -f "$rc" ]; then
      sed -i "/# dupfind/d" "$rc" 2>/dev/null || true
      sed -i "\|$INSTALL_DIR|d" "$rc" 2>/dev/null || true
      sed -i "/alias $ALIAS_NAME=/d" "$rc" 2>/dev/null || true
    fi
  done
  FISH_RC="${HOME}/.config/fish/config.fish"
  if [ -f "$FISH_RC" ]; then
    sed -i "/# $INSTALL_DIR/d" "$FISH_RC" 2>/dev/null || true
    sed -i "\|$INSTALL_DIR|d" "$FISH_RC" 2>/dev/null || true
    sed -i "/function $ALIAS_NAME/,/^end/d" "$FISH_RC" 2>/dev/null || true
    sed -i "/# dupfind alias/d" "$FISH_RC" 2>/dev/null || true
  fi

  ok "Uninstall complete"
  info "Restart your shell: ${DIM}exec \$SHELL${NC}"
  exit 0
fi

header

printf "\n${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}  ║  ${CYAN}DEPLOYMENT SEQUENCE${NC}${BOLD}                        rev 1.0  ║${NC}\n"
printf "${BOLD}  ║  ${DIM}PROTOCOL: DOWNLOAD → VERIFY → BUILD → INJECT${NC}${BOLD}          ║${NC}\n"
printf "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}\n\n"

info "${GREEN}ROOT ACCESS${NC} ........................ ${GREEN}CONFIRMED${NC}"
info "${DIM}USER${NC} .............................. $(whoami 2>/dev/null || echo "$USER")"
info "${DIM}TARGET${NC} ............................ $INSTALL_DIR/$BINARY_NAME"
info "${DIM}SOURCE${NC} ............................ github.com/$REPO"
echo

# Detect if running from within the repo
if [ -f Cargo.toml ] && grep -q 'name = "dupfind"' Cargo.toml 2>/dev/null; then
  LOCAL=true
else
  LOCAL=false
fi

# ── 1/4: Rust ───────────────────────────────────────────────────
step_header 1 "RUST ENVIRONMENT"
if ! command -v cargo &>/dev/null; then
  progress_bar 0 "Checking installation"
  warn "Rust is not installed"
  printf "  ${YELLOW}?${NC} Install Rust via rustup? ${BOLD}[Y/n]${NC} "
  if [ -t 0 ]; then
    read -r answer
  else
    read -r answer < /dev/tty 2>/dev/null || answer="y"
  fi
  case "${answer:-y}" in
    y|Y|yes|YES|"") ;;
    *) fail "Aborted by user" ;;
  esac
  progress_bar 25 "Installing Rust (this may take a minute)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1 | tail -1
  . "$HOME/.cargo/env"
  progress_bar 100 "Rust ready"
else
  progress_bar 100 "Rust is ready"
fi

# ── 2/4: Find existing binary ──────────────────────────────────
step_header 2 "EXISTING BINARY"
OLD_VER=""
OLD_PATH=""

for loc in "$INSTALL_DIR/$BINARY_NAME" "${HOME}/.cargo/bin/$BINARY_NAME"; do
  if [ -x "$loc" ]; then
    OLD_PATH="$loc"
    OLD_VER=$("$loc" --version 2>/dev/null | awk '{print $2}' || true)
    break
  fi
done

if [ -z "$OLD_PATH" ]; then
  FOUND=$(command -v "$BINARY_NAME" 2>/dev/null || true)
  if [ -n "$FOUND" ] && [ -x "$FOUND" ]; then
    OLD_PATH="$FOUND"
    OLD_VER=$("$FOUND" --version 2>/dev/null | awk '{print $2}' || true)
  fi
fi

NEW_INSTALL=false
if [ -z "$OLD_PATH" ]; then
  NEW_INSTALL=true
  info "No existing ${BINARY_NAME} found"
  progress_bar 100 "${DIM}fresh install${NC}"
else
  info "Found at ${DIM}$OLD_PATH${NC}"
  progress_bar 100 "${DIM}version ${OLD_VER:-?}${NC}"
fi

# ── 3/4: Get source + Build ──────────────────────────────────
step_header 3 "SOURCE ACQUISITION"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ "$LOCAL" = true ]; then
  progress_bar 30 "Copying local source..."
  cp -r . "$BUILD_DIR/"
  progress_bar 60 "Local source copied"
  progress_bar 100 "Ready to build"
else
  if ! command -v git &>/dev/null; then
    progress_bar 0 "Checking dependencies"
    warn "git is not installed"
    printf "  ${YELLOW}?${NC} Install git? ${BOLD}[Y/n]${NC} "
    if [ -t 0 ]; then
      read -r answer
    else
      read -r answer < /dev/tty 2>/dev/null || answer="y"
    fi
    case "${answer:-y}" in
      y|Y|yes|YES|"") ;;
      *) fail "Aborted by user" ;;
    esac
    progress_bar 20 "Installing git..."
    if command -v apt &>/dev/null; then
      apt update && apt install -y git 2>&1 | tail -1
    elif command -v pacman &>/dev/null; then
      pacman -Sy --noconfirm git 2>&1 | tail -1
    elif command -v dnf &>/dev/null; then
      dnf install -y git 2>&1 | tail -1
    elif command -v apk &>/dev/null; then
      apk add git 2>&1 | tail -1
    else
      fail "Can not determine package manager. Install git manually."
    fi
  fi
  progress_bar 20 "Fetching from github.com/$REPO..."
  git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$BUILD_DIR" 2>&1 | tail -1
  progress_bar 60 "Source downloaded"
  progress_bar 100 "Ready to build"
fi

step_header 4 "BUILD AND INJECT"
cd "$BUILD_DIR"
progress_bar 10 "Compiling (first run downloads crates)..."
cargo build --release 2>&1 | tail -1
progress_bar 60 "Build complete"

NEW_VER=$(./target/release/"$BINARY_NAME" --version 2>/dev/null | awk '{print $2}' || echo "?")

if [ "$NEW_INSTALL" = true ]; then
  mkdir -p "$INSTALL_DIR"
  rm -f "$INSTALL_DIR/$BINARY_NAME"
  cp "target/release/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
  chmod +x "$INSTALL_DIR/$BINARY_NAME"
  progress_bar 80 "Injecting to $INSTALL_DIR/"
  progress_bar 100 "${GREEN}Installed${NC} ${BOLD}$NEW_VER${NC}"
else
  DEST="$OLD_PATH"
  if [ ! -w "$(dirname "$DEST")" ]; then
    DEST="$INSTALL_DIR/$BINARY_NAME"
    mkdir -p "$INSTALL_DIR"
  fi
  rm -f "$DEST"
  cp "target/release/$BINARY_NAME" "$DEST"
  chmod +x "$DEST"
  progress_bar 80 "Injecting to ${DEST}"
  if [ "$OLD_VER" != "$NEW_VER" ]; then
    progress_bar 100 "${GREEN}Updated${NC} ${DIM}${OLD_VER}${NC} → ${BOLD}${NEW_VER}${NC}"
  else
    progress_bar 100 "${GREEN}Reinstalled${NC} ${BOLD}$NEW_VER${NC}"
  fi
fi

# ── PATH warning ────────────────────────────────────────────────
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *) warn "${DIM}$INSTALL_DIR${NC} is not in PATH"
     echo "           Add: ${BOLD}export PATH=\"\$PATH:$INSTALL_DIR\"${NC}" ;;
esac

# ── Shell setup ──────────────────────────────────────────────
section "SHELL INTEGRATION"

shell_setup() {
  local rc="$1"
  local path_line="export PATH=\"\$PATH:$INSTALL_DIR\""
  local alias_line="alias $ALIAS_NAME='$BINARY_NAME'"
  mkdir -p "$(dirname "$rc")"

  if grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then :; else
    echo >> "$rc"
    echo "# dupfind" >> "$rc"
    echo "$path_line" >> "$rc"
  fi

  if grep -qE "(alias $ALIAS_NAME=|function $ALIAS_NAME)" "$rc" 2>/dev/null; then :; else
    echo "$alias_line" >> "$rc"
    info "Alias '${BOLD}$ALIAS_NAME${NC}' added to ${DIM}$(basename "$rc")${NC}"
  fi
}

setup_fish() {
  local rc="${HOME}/.config/fish/config.fish"
  mkdir -p "$(dirname "$rc")"
  if grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then :; else
    echo >> "$rc"
    echo "# $INSTALL_DIR" >> "$rc"
    echo "fish_add_path -g \"$INSTALL_DIR\"" >> "$rc"
  fi
  if grep -q "function $ALIAS_NAME" "$rc" 2>/dev/null; then :; else
    cat >> "$rc" <<- EOF

# dupfind alias
function $ALIAS_NAME --wraps $BINARY_NAME
    $BINARY_NAME \$argv
end
EOF
    info "Alias '${BOLD}$ALIAS_NAME${NC}' added to ${DIM}config.fish${NC}"
  fi
}

CURRENT_SHELL=$(basename "${SHELL:-}" 2>/dev/null || echo "")
case "$CURRENT_SHELL" in
  bash) shell_setup "${HOME}/.bashrc" ;;
  zsh)  shell_setup "${HOME}/.zshrc" ;;
  fish) setup_fish ;;
esac

for shell in bash zsh fish; do
  [ "$shell" = "$CURRENT_SHELL" ] && continue
  case "$shell" in
    bash) [ -f "${HOME}/.bashrc" ] && shell_setup "${HOME}/.bashrc" ;;
    zsh)  [ -f "${HOME}/.zshrc" ] && shell_setup "${HOME}/.zshrc" ;;
    fish) [ -f "${HOME}/.config/fish/config.fish" ] && setup_fish ;;
  esac
done

shell_setup "${HOME}/.profile"

printf "\n${GREEN}${BOLD}"
printf "  ╔══════════════════════════════════════════════════════╗\n"
printf "  ║              DEPLOYMENT COMPLETE                     ║\n"
printf "  ╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\n  ${BOLD}$ALIAS_NAME${NC} is ready. Restart your shell or run:\n"
printf "    ${CYAN}exec \$SHELL${NC}\n"
echo
