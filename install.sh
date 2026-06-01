#!/usr/bin/env bash
set -euo pipefail

BINARY_NAME="dupfind"
ALIAS_NAME="dfind"
INSTALL_DIR="${HOME}/.local/bin"

if ! command -v cargo &>/dev/null; then
    echo "Error: Rust/Cargo is not installed."
    echo "Install it first: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

echo "Building $BINARY_NAME..."
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
