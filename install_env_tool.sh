#!/bin/bash
# ==============================================================================
# Setup direnv for Automatic Environment Variable Loading
# ==============================================================================
set -e

echo "1. Checking if direnv is installed..."
if ! command -v direnv &> /dev/null; then
    echo "direnv not found. Installing via Homebrew..."
    brew install direnv
else
    echo "✅ direnv is already installed."
fi

# Detect shell configuration file
SHELL_NAME=$(basename "$SHELL")
SHELL_RC=""
if [ "$SHELL_NAME" = "zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ "$SHELL_NAME" = "bash" ]; then
    if [ -f "$HOME/.bash_profile" ]; then
        SHELL_RC="$HOME/.bash_profile"
    else
        SHELL_RC="$HOME/.bashrc"
    fi
fi

if [ -n "$SHELL_RC" ]; then
    echo "2. Configuring direnv hook in $SHELL_RC..."
    # Check if hook already exists
    if grep -q "direnv hook" "$SHELL_RC" 2>/dev/null; then
        echo "✅ direnv hook already exists in $SHELL_RC."
    else
        echo "" >> "$SHELL_RC"
        echo '# direnv configuration' >> "$SHELL_RC"
        echo 'eval "$(direnv hook '$SHELL_NAME')"' >> "$SHELL_RC"
        echo "✅ Added direnv hook to $SHELL_RC."
    fi
else
    echo "⚠️ Could not automatically detect shell RC file. Please add hook manually to your shell configuration:"
    echo "eval \"\$(direnv hook <shell_name>)\""
fi

echo "3. Authorizing direnv in the workspace..."
direnv allow .

echo "======================================================="
echo "🎉 Installation Complete!"
echo "Please restart your terminal or reload your shell profile:"
echo "  source $SHELL_RC"
echo "======================================================="
