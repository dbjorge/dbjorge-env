#!/bin/bash

# Parse command line arguments
GIT_PROFILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --git-profile)
            GIT_PROFILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --git-profile {work|personal}"
            exit 1
            ;;
    esac
done

# Validate git-profile parameter
if [[ "$GIT_PROFILE" != "work" && "$GIT_PROFILE" != "personal" ]]; then
    echo "Error: --git-profile must be either 'work' or 'personal'"
    echo "Usage: $0 --git-profile {work|personal}"
    exit 1
fi

# Function to ensure a file starts with a specific line
ensure_file_starts_with_line() {
    local file_path="$1"
    local line="$2"

    # Create parent directory if it doesn't exist
    mkdir -p "$(dirname "$file_path")" 2>/dev/null

    # Read existing lines or create empty array
    if [[ -f "$file_path" ]]; then
        mapfile -t lines < "$file_path"
    else
        lines=()
    fi

    # Check if file is empty or doesn't start with the required line
    if [[ ${#lines[@]} -eq 0 || "${lines[0]}" != "$line" ]]; then
        # Prepend the line
        {
            echo "$line"
            if [[ -f "$file_path" ]]; then
                cat "$file_path"
            fi
        } > "$file_path.tmp"
        mv "$file_path.tmp" "$file_path"
    fi
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configure zsh to source the profile
ZSHRC_IMPL="$SCRIPT_DIR/.zshrc"
ensure_file_starts_with_line "$HOME/.zshrc" "source \"$ZSHRC_IMPL\""

# Configure git to include global config
GIT_CONFIG_IMPL="$SCRIPT_DIR/gitconfig_global.txt"
ensure_file_starts_with_line "$HOME/.gitconfig" "[include] path = $GIT_CONFIG_IMPL"

# If running in WSL, include WSL-specific git config
if [[ -n "$WSL_INTEROP" ]]; then
    GIT_CONFIG_WSL_IMPL="$SCRIPT_DIR/gitconfig_global_wsl.txt"
    ensure_file_starts_with_line "$HOME/.gitconfig" "[include] path = $GIT_CONFIG_WSL_IMPL"
fi

# Include profile-specific git config
GIT_CONFIG_PROFILE_IMPL="$SCRIPT_DIR/gitconfig_global_$GIT_PROFILE.txt"
ensure_file_starts_with_line "$HOME/.gitconfig" "[include] path = $GIT_CONFIG_PROFILE_IMPL"

echo "Installation complete!"
echo "Zsh profile configured to source: $ZSHRC_IMPL"
echo "Git config configured with profile: $GIT_PROFILE"
