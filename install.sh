#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="dupfind"
ALIAS_NAME="dfind"
INSTALL_DIR="${HOME}/.local/bin"
REPO="arebin1914/duplicate-finder"
BRANCH="master"

info() { echo "  [${1}/${2}] ${3}"; }

TOTAL=6

# ── Uninstall ──────────────────────────────────────────────────
if [ "${1:-}" = "--uninstall" ]; then
    echo "  Uninstalling $BINARY_NAME..."
    for loc in "$INSTALL_DIR/$BINARY_NAME" "${HOME}/.cargo/bin/$BINARY_NAME"; do
        if [ -x "$loc" ]; then
            rm -f "$loc"
            echo "    Removed: $loc"
        fi
    done
    FOUND=$(command -v "$BINARY_NAME" 2>/dev/null || true)
    if [ -n "$FOUND" ] && [ -x "$FOUND" ]; then
        rm -f "$FOUND"
        echo "    Removed: $FOUND"
    fi

    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        if [ -f "$rc" ]; then
            sed -i "/# dupfind/d" "$rc" 2>/dev/null || true
            sed -i "\|$INSTALL_DIR|d" "$rc" 2>/dev/null || true
            sed -i "/alias $ALIAS_NAME=/d" "$rc" 2>/dev/null || true
        fi
    done
    # fish
    FISH_RC="${HOME}/.config/fish/config.fish"
    if [ -f "$FISH_RC" ]; then
        sed -i "/# $INSTALL_DIR/d" "$FISH_RC" 2>/dev/null || true
        sed -i "\|$INSTALL_DIR|d" "$FISH_RC" 2>/dev/null || true
        sed -i "/function $ALIAS_NAME/,/^end/d" "$FISH_RC" 2>/dev/null || true
        sed -i "/# dupfind alias/d" "$FISH_RC" 2>/dev/null || true
    fi

    echo "  Uninstall complete."
    echo "  Restart your shell or run: exec \$SHELL"
    exit 0
fi

# Detect if running from within the repo
if [ -f Cargo.toml ] && grep -q 'name = "dupfind"' Cargo.toml 2>/dev/null; then
    LOCAL=true
else
    LOCAL=false
fi

# ── 1/6: Rust ───────────────────────────────────────────────────
step=1
if ! command -v cargo &>/dev/null; then
    info $step $TOTAL "Rust is not installed. Prompting user..."
    printf "Install Rust via rustup? [Y/n] "
    if [ -t 0 ]; then
        read -r answer
    else
        read -r answer < /dev/tty 2>/dev/null || answer="y"
    fi
    case "${answer:-y}" in
        y|Y|yes|YES|"") ;;
        *) echo "Aborted."; exit 1 ;;
    esac
    echo "       Installing Rust (this may take a minute)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
else
    info $step $TOTAL "Rust is ready"
fi

# ── 2/6: Find existing binary ──────────────────────────────────
step=2
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
    info $step $TOTAL "No existing $BINARY_NAME found (fresh install)"
else
    info $step $TOTAL "Found $BINARY_NAME at $OLD_PATH (v${OLD_VER:-?})"
fi

# ── 3/6: Get source ────────────────────────────────────────────
step=3
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ "$LOCAL" = true ]; then
    info $step $TOTAL "Copying local source..."
    cp -r . "$BUILD_DIR/"
else
    if ! command -v git &>/dev/null; then
        info $step $TOTAL "git is not installed. Prompting user..."
        printf "Install git? [Y/n] "
        if [ -t 0 ]; then
            read -r answer
        else
            read -r answer < /dev/tty 2>/dev/null || answer="y"
        fi
        case "${answer:-y}" in
            y|Y|yes|YES|"") ;;
            *) echo "Aborted."; exit 1 ;;
        esac
        echo "       Installing git..."
        if command -v apt &>/dev/null; then
            apt update && apt install -y git
        elif command -v pacman &>/dev/null; then
            pacman -Sy --noconfirm git
        elif command -v dnf &>/dev/null; then
            dnf install -y git
        elif command -v apk &>/dev/null; then
            apk add git
        else
            echo "       Error: can't determine package manager. Install git manually."
            exit 1
        fi
    fi
    info $step $TOTAL "Downloading source from $REPO..."
    git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$BUILD_DIR"
fi

# ── 4/6: Build ─────────────────────────────────────────────────
step=4
cd "$BUILD_DIR"
info $step $TOTAL "Compiling with cargo (first run downloads crates, may take a few min)..."
cargo build --release

# ── 5/6: Install binary ───────────────────────────────────────
step=5
NEW_VER=$(./target/release/"$BINARY_NAME" --version 2>/dev/null | awk '{print $2}' || echo "?")

if [ "$NEW_INSTALL" = true ]; then
    mkdir -p "$INSTALL_DIR"
    cp "target/release/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    info $step $TOTAL "Installed $BINARY_NAME $NEW_VER to $INSTALL_DIR/$BINARY_NAME"
else
    DEST="$OLD_PATH"
    if [ ! -w "$(dirname "$DEST")" ]; then
        DEST="$INSTALL_DIR/$BINARY_NAME"
        mkdir -p "$INSTALL_DIR"
    fi
    cp "target/release/$BINARY_NAME" "$DEST"
    chmod +x "$DEST"
    if [ "$OLD_VER" != "$NEW_VER" ]; then
        info $step $TOTAL "Updated $OLD_VER → $NEW_VER"
    else
        info $step $TOTAL "Reinstalled $BINARY_NAME $NEW_VER (same version)"
    fi
fi

# ── PATH warning ────────────────────────────────────────────────
case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *) echo "       Warning: $INSTALL_DIR is not in PATH. Add this to your shell config:"
       echo "           export PATH=\"\$PATH:$INSTALL_DIR\"" ;;
esac

# ── 6/6: Shell setup ──────────────────────────────────────────
step=6
info $step $TOTAL "Setting up shell aliases..."

shell_setup() {
    local rc="$1"
    local path_line="export PATH=\"\$PATH:$INSTALL_DIR\""
    local alias_line="alias $ALIAS_NAME='$BINARY_NAME'"
    mkdir -p "$(dirname "$rc")"

    if grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
        :
    else
        echo >> "$rc"
        echo "# dupfind" >> "$rc"
        echo "$path_line" >> "$rc"
    fi

    if grep -qE "(alias $ALIAS_NAME=|function $ALIAS_NAME)" "$rc" 2>/dev/null; then
        :
    else
        echo "$alias_line" >> "$rc"
        echo "         Added '$ALIAS_NAME' alias to $(basename "$rc")"
    fi
}

setup_fish() {
    local rc="${HOME}/.config/fish/config.fish"
    mkdir -p "$(dirname "$rc")"

    if grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
        :
    else
        echo >> "$rc"
        echo "# $INSTALL_DIR" >> "$rc"
        echo "fish_add_path -g \"$INSTALL_DIR\"" >> "$rc"
    fi

    if grep -q "function $ALIAS_NAME" "$rc" 2>/dev/null; then
        :
    else
        cat >> "$rc" <<- EOF

# dupfind alias
function $ALIAS_NAME --wraps $BINARY_NAME
    $BINARY_NAME \$argv
end
EOF
        echo "         Added '$ALIAS_NAME' alias to config.fish"
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

echo
echo "  Done! Restart your shell or run: exec \$SHELL"
echo "  Then type: $ALIAS_NAME"
