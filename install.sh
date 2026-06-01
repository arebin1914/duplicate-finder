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
    read -r answer
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

# Fish alias
if command -v fish &>/dev/null; then
    FISH_CONFIG="${HOME}/.config/fish/config.fish"
    mkdir -p "$(dirname "$FISH_CONFIG")"

    # Ensure INSTALL_DIR is in fish PATH
    if ! grep -q "fish_add_path.*$INSTALL_DIR" "$FISH_CONFIG" 2>/dev/null; then
        echo >> "$FISH_CONFIG"
        echo "# $INSTALL_DIR" >> "$FISH_CONFIG"
        echo "fish_add_path -g \"$INSTALL_DIR\"" >> "$FISH_CONFIG"
        echo "Added $INSTALL_DIR to fish PATH in $FISH_CONFIG"
    fi

    if ! grep -q "function $ALIAS_NAME" "$FISH_CONFIG" 2>/dev/null; then
        cat >> "$FISH_CONFIG" <<- EOF

# dupfind alias
function $ALIAS_NAME --wraps $BINARY_NAME
    $BINARY_NAME \$argv
end
EOF
        echo "Added fish alias '$ALIAS_NAME' to $FISH_CONFIG"
    else
        echo "Fish alias '$ALIAS_NAME' already configured"
    fi
fi

echo
echo "Done! Run '$ALIAS_NAME' or '$BINARY_NAME' to start."
