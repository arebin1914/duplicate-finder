#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="dupfind"
ALIAS_NAME="dfind"
INSTALL_DIR="${HOME}/.local/bin"
REPO="arebin1914/duplicate-finder"
BRANCH="master"

FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

# Detect if running from within the repo
if [ -f Cargo.toml ] && grep -q 'name = "dupfind"' Cargo.toml 2>/dev/null; then
    LOCAL=true
else
    LOCAL=false
fi

# ── Rust check ──────────────────────────────────────────────────
if ! command -v cargo &>/dev/null; then
    echo "Rust/Cargo is not installed."
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
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
fi

# ── Find existing binary ────────────────────────────────────────
OLD_VER=""
OLD_PATH=""

for loc in "$INSTALL_DIR/$BINARY_NAME" "${HOME}/.cargo/bin/$BINARY_NAME"; do
    if [ -x "$loc" ]; then
        OLD_PATH="$loc"
        OLD_VER=$("$loc" --version 2>/dev/null | awk '{print $2}' || true)
        break
    fi
done

# also check PATH as fallback
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
fi

# ── Build ───────────────────────────────────────────────────────
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

if [ "$LOCAL" = true ]; then
    echo "Building $BINARY_NAME from local source..."
    cp -r . "$BUILD_DIR/"
else
    if ! command -v git &>/dev/null; then
        echo "Error: git is required for curl-based installation."
        exit 1
    fi
    echo "Downloading $BINARY_NAME from $REPO..."
    git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$BUILD_DIR"
fi

cd "$BUILD_DIR"
cargo build --release

# ── Get new version ─────────────────────────────────────────────
NEW_VER=$(./target/release/"$BINARY_NAME" --version 2>/dev/null | awk '{print $2}' || echo "?")

# ── Install ─────────────────────────────────────────────────────
if [ "$NEW_INSTALL" = true ]; then
    mkdir -p "$INSTALL_DIR"
    cp "target/release/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    echo "Installed $BINARY_NAME $NEW_VER to $INSTALL_DIR/$BINARY_NAME"
else
    # Same location, or use INSTALL_DIR if old path isn't writable
    DEST="$OLD_PATH"
    if [ ! -w "$(dirname "$DEST")" ]; then
        DEST="$INSTALL_DIR/$BINARY_NAME"
        mkdir -p "$INSTALL_DIR"
    fi
    cp "target/release/$BINARY_NAME" "$DEST"
    chmod +x "$DEST"
    if [ "$OLD_VER" != "$NEW_VER" ]; then
        echo "Updated: $OLD_VER → $NEW_VER"
    else
        echo "Reinstalled $BINARY_NAME $NEW_VER (same version)"
    fi
fi

# ── PATH warning ────────────────────────────────────────────────
case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *) echo "Warning: $INSTALL_DIR is not in PATH. Add this to your shell config:"
       echo "    export PATH=\"\$PATH:$INSTALL_DIR\"" ;;
esac

# ── Shell setup ────────────────────────────────────────────────
shell_setup() {
    local rc="$1"
    local path_line="export PATH=\"\$PATH:$INSTALL_DIR\""
    local alias_line="alias $ALIAS_NAME='$BINARY_NAME'"

    mkdir -p "$(dirname "$rc")"

    if grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
        : # already in PATH
    else
        echo >> "$rc"
        echo "# dupfind" >> "$rc"
        echo "$path_line" >> "$rc"
    fi

    if grep -qE "(alias $ALIAS_NAME=|function $ALIAS_NAME)" "$rc" 2>/dev/null; then
        : # already configured
    else
        echo "$alias_line" >> "$rc"
        echo "Added '$ALIAS_NAME' alias to $rc"
    fi
}

setup_fish() {
    local rc="${HOME}/.config/fish/config.fish"
    mkdir -p "$(dirname "$rc")"

    if grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
        : # already in PATH
    else
        echo >> "$rc"
        echo "# $INSTALL_DIR" >> "$rc"
        echo "fish_add_path -g \"$INSTALL_DIR\"" >> "$rc"
    fi

    if grep -q "function $ALIAS_NAME" "$rc" 2>/dev/null; then
        : # already configured
    else
        cat >> "$rc" <<- EOF

# dupfind alias
function $ALIAS_NAME --wraps $BINARY_NAME
    $BINARY_NAME \$argv
end
EOF
        echo "Added '$ALIAS_NAME' alias to $rc"
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
echo "Done! Restart your shell or run: exec \$SHELL"
