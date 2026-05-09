#!/usr/bin/env sh
# cmagent installer for Linux and macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Coremail/cmagent/main/install.sh | sh
#
# Installs the cmagent binary to ~/.local/bin (created if needed).
# Add ~/.local/bin to your PATH if it is not already there.

set -eu

REPO="Coremail/cmagent"
BIN_NAME="cmagent"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
say()  { printf '\033[1m%s\033[0m\n' "$*"; }
err()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "Required tool not found: $1"; }

# ---------------------------------------------------------------------------
# Detect OS and arch
# ---------------------------------------------------------------------------
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
    Linux)  OS_LABEL="linux"  ;;
    Darwin) OS_LABEL="macos"  ;;
    *)      err "Unsupported OS: $OS. Download manually from https://github.com/$REPO/releases" ;;
esac

case "$ARCH" in
    x86_64)        ARCH_LABEL="x86_64"  ;;
    aarch64|arm64) ARCH_LABEL="aarch64" ;;
    *)             err "Unsupported arch: $ARCH. Download manually from https://github.com/$REPO/releases" ;;
esac

PLATFORM="$OS_LABEL-$ARCH_LABEL"
ARCHIVE="$BIN_NAME-$PLATFORM.tar.gz"
URL="https://github.com/$REPO/releases/latest/download/$ARCHIVE"

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
say "Downloading cmagent ($PLATFORM)..."
need curl

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL --progress-bar "$URL" -o "$TMP_DIR/$ARCHIVE" || \
    err "Download failed. Check https://github.com/$REPO/releases for available platforms."

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
say "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
tar xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"
chmod +x "$TMP_DIR/$BIN_NAME"
mv "$TMP_DIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"

# ---------------------------------------------------------------------------
# PATH hint
# ---------------------------------------------------------------------------
say "cmagent installed to $INSTALL_DIR/$BIN_NAME"

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        echo ""
        echo "  $INSTALL_DIR is not in your PATH."
        echo "  Add this line to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo '    export PATH="$HOME/.local/bin:$PATH"'
        echo ""
        echo "  Then restart your shell or run: source ~/.bashrc"
        ;;
esac

echo ""
say "Run 'cmagent --help' to get started."
