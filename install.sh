#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="dupfind"
ALIAS_NAME="dfind"
INSTALL_DIR="${HOME}/.local/bin"
REPO="arebin1914/duplicate-finder"
BRANCH="master"

# Detect if running from within the repo (local install) or via curl
if [ -f Cargo.toml ] && grep -q 'name = "dupfind"' Cargo.toml 2>/dev/null; then
    LOCAL=true
else
    LOCAL=false
fi

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

mkdir -p "$INSTALL_DIR"
cp "target/release/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo "Installed to: $INSTALL_DIR/$BINARY_NAME"

# Add to PATH if not already present
case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *) echo "Warning: $INSTALL_DIR is not in PATH. Add this to your shell config:"
       echo "    export PATH=\"\$PATH:$INSTALL_DIR\"" ;;
esac

shell_setup() {
    local rc="$1"
    local path_line="export PATH=\"\$PATH:$INSTALL_DIR\""
    local alias_line="alias $ALIAS_NAME='$BINARY_NAME'"

    mkdir -p "$(dirname "$rc")"

    if ! grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
        echo >> "$rc"
        echo "# dupfind" >> "$rc"
        echo "$path_line" >> "$rc"
    fi

    if grep -qE "(alias $ALIAS_NAME=|function $ALIAS_NAME)" "$rc" 2>/dev/null; then
        echo "Alias '$ALIAS_NAME' already configured in $rc"
    else
        echo "$alias_line" >> "$rc"
        echo "Added '$ALIAS_NAME' alias to $rc"
    fi
}

setup_fish() {
    local rc="${HOME}/.config/fish/config.fish"
    mkdir -p "$(dirname "$rc")"

    if ! grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
        echo >> "$rc"
        echo "# $INSTALL_DIR" >> "$rc"
        echo "fish_add_path -g \"$INSTALL_DIR\"" >> "$rc"
    fi

    if grep -q "function $ALIAS_NAME" "$rc" 2>/dev/null; then
        echo "Alias '$ALIAS_NAME' already configured in $rc"
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

# Detect current shell
CURRENT_SHELL=$(basename "${SHELL:-}" 2>/dev/null || echo "")

case "$CURRENT_SHELL" in
    bash) shell_setup "${HOME}/.bashrc" ;;
    zsh)  shell_setup "${HOME}/.zshrc" ;;
    fish) setup_fish ;;
esac

# Also set up other shells present on the system
for shell in bash zsh fish; do
    [ "$shell" = "$CURRENT_SHELL" ] && continue
    case "$shell" in
        bash) [ -f "${HOME}/.bashrc" ] && shell_setup "${HOME}/.bashrc" ;;
        zsh)  [ -f "${HOME}/.zshrc" ] && shell_setup "${HOME}/.zshrc" ;;
        fish) [ -f "${HOME}/.config/fish/config.fish" ] && setup_fish ;;
    esac
done

# Always add to .profile for POSIX sh compatibility
shell_setup "${HOME}/.profile"

echo
echo "Done! Restart your shell or run 'source ~/.profile' then run '$ALIAS_NAME' or '$BINARY_NAME'."
