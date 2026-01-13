#!/bin/bash
set -euo pipefail

VERSION="0.1.0"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/StefanVonRanda/architect/main/continuous_opencode.sh"
SCRIPT_SHA256_URL="https://raw.githubusercontent.com/StefanVonRanda/architect/main/continuous_opencode.sh.sha256"

echo "🚀 Installing Continuous OpenCode v${VERSION}..."

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "📁 Creating directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

echo "📥 Downloading script..."
curl -fsSL "$SCRIPT_URL" -o "${INSTALL_DIR}/cop"
chmod +x "${INSTALL_DIR}/cop"

echo "✅ Installed to: ${INSTALL_DIR}/cop"

if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo ""
    echo "⚠️  ${INSTALL_DIR} is not in your PATH"
    echo ""
    echo "Add the following to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "    export PATH=\"${INSTALL_DIR}:\$PATH\""
    echo ""
    echo "Then restart your shell or run: source ~/.bashrc"
fi

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Quick start:"
echo "    cop --prompt \"add unit tests\" --max-runs 5"
