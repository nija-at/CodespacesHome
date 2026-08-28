#!/usr/bin/env bash
# Codespaces dotfiles bootstrap.
# GitHub Codespaces runs this automatically when dotfiles are enabled
# (Settings > Codespaces > Automatically install dotfiles).
set -euo pipefail

if command -v claude >/dev/null 2>&1; then
  echo "claude code already installed: $(command -v claude)"
else
  echo "installing claude code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- statusline ---
dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.claude"
cp "$dotfiles_dir/statusline.sh" "$HOME/.claude/statusline.sh"
chmod +x "$HOME/.claude/statusline.sh"

settings_file="$HOME/.claude/settings.json"
[ -f "$settings_file" ] || echo '{}' >"$settings_file"
tmp_settings=$(mktemp)
jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}' \
  "$settings_file" >"$tmp_settings"
mv "$tmp_settings" "$settings_file"
echo "statusline installed"
