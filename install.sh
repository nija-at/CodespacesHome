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
