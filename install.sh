#!/bin/zsh

# Installation script for aicommit function

# Get script directory (works in both zsh and bash)
if [ -n "$ZSH_VERSION" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
ZSHRC="$HOME/.zshrc"
FUNCTION_FILE="$SCRIPT_DIR/aicommit.sh"
BACKUP_FILE="${ZSHRC}.bak.$(date +%Y%m%d_%H%M%S)"

echo "Installing aicommit function..."

# Check if .zshrc exists
if [ ! -f "$ZSHRC" ]; then
    echo "❌ Error: $ZSHRC not found"
    exit 1
fi

# Validate function file syntax before installation
if [ -f "$FUNCTION_FILE" ]; then
    echo "Checking function syntax..."
    if ! zsh -n "$FUNCTION_FILE" 2>/dev/null; then
        echo "❌ Error: Function file has syntax errors:"
        zsh -n "$FUNCTION_FILE" 2>&1
        exit 1
    fi
    echo "✅ Function syntax is valid"
else
    echo "❌ Error: $FUNCTION_FILE not found"
    exit 1
fi

# Check current .zshrc syntax before making changes
echo "Checking current .zshrc syntax..."
if ! zsh -n "$ZSHRC" 2>/dev/null; then
    echo "⚠️  Warning: Your .zshrc has syntax errors:"
    zsh -n "$ZSHRC" 2>&1 | head -5
    echo ""
    read "?Do you want to continue anyway? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled. Please fix .zshrc syntax errors first."
        exit 1
    fi
    echo "⚠️  Continuing despite syntax errors..."
else
    echo "✅ Current .zshrc syntax is valid"
fi

# Create backup
echo "Creating backup: $BACKUP_FILE"
cp "$ZSHRC" "$BACKUP_FILE"

# Check if function already exists in .zshrc
if grep -q "^aicommit()" "$ZSHRC" 2>/dev/null; then
    echo "⚠️  aicommit function already exists in $ZSHRC"
    read "?Do you want to replace it? (y/N): " replace
    if [[ "$replace" =~ ^[Yy]$ ]]; then
        # Remove old function using a temporary file
        # This is more reliable than sed for complex functions
        awk '
            /^aicommit\(\)/ { in_function=1; brace_count=0; next }
            in_function {
                brace_count += gsub(/{/, "{")
                brace_count -= gsub(/}/, "}")
                if (brace_count == 0 && /^}/) {
                    in_function=0
                    next
                }
                if (in_function) next
            }
            { print }
        ' "$ZSHRC" > "${ZSHRC}.tmp" && mv "${ZSHRC}.tmp" "$ZSHRC"
        
        # Fallback: if awk fails, use simple sed pattern
        if [ $? -ne 0 ] || grep -q "^aicommit()" "$ZSHRC" 2>/dev/null; then
            # Simple pattern match as fallback
            sed -i.bak '/^aicommit()/,/^}$/d' "$ZSHRC"
        fi
        echo "✅ Removed old function"
    else
        echo "Installation cancelled."
        exit 0
    fi
fi

# Add function to .zshrc
echo "Adding aicommit function to $ZSHRC..."
{
    echo ""
    echo "# aicommit function - AI-powered git commit messages"
    echo "# Added on $(date '+%Y-%m-%d %H:%M:%S')"
    cat "$FUNCTION_FILE"
} >> "$ZSHRC"

# Validate .zshrc syntax after installation
echo "Validating .zshrc syntax after installation..."
if ! zsh -n "$ZSHRC" 2>/dev/null; then
    echo "❌ Error: .zshrc has syntax errors after installation:"
    zsh -n "$ZSHRC" 2>&1
    echo ""
    echo "⚠️  Restoring backup..."
    cp "$BACKUP_FILE" "$ZSHRC"
    echo "✅ Restored from backup: $BACKUP_FILE"
    echo ""
    echo "Please check the function file and try again."
    exit 1
fi

echo "✅ Added aicommit function to $ZSHRC"
echo "✅ Syntax validation passed"
echo ""
echo "Installation complete! Please run:"
echo "  source ~/.zshrc"
echo ""
echo "Or restart your terminal."
echo ""
echo "Optional: Set default model in ~/.zshrc:"
echo "  export OLLAMA_MODEL=\"llama2\""
echo ""
echo "Backup saved at: $BACKUP_FILE"

