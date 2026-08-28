#!/usr/bin/env bash
# Codespaces dotfiles bootstrap.
# GitHub Codespaces runs this automatically when dotfiles are enabled
# (Settings > Codespaces > Automatically install dotfiles).
#
# Each step below runs independently: a failure in one step is logged and
# skipped rather than aborting the rest of the script. Failures are recorded
# to LOG_FILE and summarized in STATUS_FILE; a snippet sourced from ~/.bashrc
# and ~/.zshrc shows a warning with that summary on the next interactive
# login.
set -uo pipefail

LOG_FILE="$HOME/.dotfiles-install.log"
STATUS_FILE="$HOME/.dotfiles-install-status"
login_check="$HOME/.dotfiles-login-check.sh"

: >"$LOG_FILE"
: >"$STATUS_FILE"

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- login warning plumbing (installed FIRST, before anything that can fail)
#
# This has to run before any risky step (network calls, jq, cp, ...) — if it
# ran last instead, a script death before reaching it (an unset-variable
# error under `set -u`, a bug in orchestration code, anything outside
# run_step's protected subshells) would silently skip installing the very
# mechanism meant to report that death. Putting it first means the reporting
# path only depends on local file writes, which are about as failure-proof
# as bash gets.
#
# The check logic itself lives in its own file, fully rewritten (not
# appended) on every run so its logic can change freely. Each shell rc file
# gets a single idempotent line sourcing it, guarded by grep so reruns never
# duplicate the line. Both bash and zsh rc files are patched since VS Code's
# integrated terminal may launch either regardless of the account's login
# shell.
cat >"$login_check" <<EOF
if [ -s "$STATUS_FILE" ]; then
  echo -e "\033[1;31m⚠ dotfiles install had errors:\033[0m"
  sed 's/^/  - /' "$STATUS_FILE"
  echo "  see $LOG_FILE for details"
fi
EOF

source_line=". \"$login_check\""
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && ! grep -qF "$login_check" "$rc"; then
    printf '\n%s\n' "$source_line" >>"$rc"
  fi
done

# Safety net: if the script exits non-zero for a reason run_step never saw
# (a bug in this orchestration code, an unset variable, ...), record a
# generic entry so the login banner still fires instead of staying silent.
# Skipped when STATUS_FILE already has real entries, so we don't double up
# on the deliberate `exit 1` below. The one thing this can't catch is
# SIGKILL — no trap survives that, in bash or otherwise.
report_unexpected_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$STATUS_FILE" ]; then
    echo "install.sh (unexpected exit $rc, see $LOG_FILE)" >>"$STATUS_FILE"
  fi
}
trap report_unexpected_exit EXIT

# run_step <name> <function> — run a step in its own subshell (with set -e so
# it stops at its first internal error), append its output to LOG_FILE, and
# on failure record <name> in STATUS_FILE without aborting the rest of the
# script.
run_step() {
  local name="$1" fn="$2" rc
  echo "=== $name ($(date -u +%FT%TZ)) ===" >>"$LOG_FILE"
  # Run in a subshell so the step's own `set -e` stops it at its first
  # internal error. Capture the exit code into a variable rather than
  # testing the subshell directly in `if` — bash silently disables a
  # subshell's own `set -e` when the subshell is itself an `if`/`&&`/`||`
  # condition, even though that's a different shell than the one being
  # tested.
  ( set -e; "$fn" ) >>"$LOG_FILE" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ok: $name"
  else
    echo "failed: $name (see $LOG_FILE)" >&2
    echo "$name" >>"$STATUS_FILE"
  fi
}

step_claude() {
  if command -v claude >/dev/null 2>&1; then
    echo "claude code already installed: $(command -v claude)"
  else
    echo "installing claude code..."
    curl -fsSL https://claude.ai/install.sh | bash
  fi
}

step_statusline() {
  mkdir -p "$HOME/.claude"
  cp "$dotfiles_dir/.claude/statusline.sh" "$HOME/.claude/statusline.sh"
  chmod +x "$HOME/.claude/statusline.sh"
  echo "statusline installed"
}

# Merges .claude/settings.json from this repo into ~/.claude/settings.json,
# with the repo's values taking precedence over any existing keys.
step_settings() {
  mkdir -p "$HOME/.claude"
  local settings_file="$HOME/.claude/settings.json"
  [ -f "$settings_file" ] || echo '{}' >"$settings_file"
  local tmp_settings
  tmp_settings=$(mktemp)
  jq -s '.[0] * .[1]' "$settings_file" "$dotfiles_dir/.claude/settings.json" >"$tmp_settings"
  mv "$tmp_settings" "$settings_file"
  echo "settings merged"
}

run_step "claude code" step_claude
run_step "statusline" step_statusline
run_step "settings" step_settings

if [ -s "$STATUS_FILE" ]; then
  echo "dotfiles install finished with errors: $(tr '\n' ',' <"$STATUS_FILE" | sed 's/,$//')" >&2
  exit 1
fi

echo "dotfiles install complete"
