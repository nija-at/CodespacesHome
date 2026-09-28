#!/usr/bin/env bash
# Codespaces dotfiles bootstrap.
# GitHub Codespaces runs this automatically when dotfiles are enabled
# (Settings > Codespaces > Automatically install dotfiles).
#
# Each step below runs independently: a failure in one step is logged and
# skipped rather than aborting the rest of the script. The terminal gets one
# line per step (✓/✗ + duration) plus a totals line; each step's full output
# goes to STATE_LOG.
set -uo pipefail

# ---- setup status + terminal banner ---------------------------------------
#
# Shared convention with project setup scripts (e.g. nija-at/strandufer's
# scripts/setup.sh): each script records its own component under STATE_DIR —
# <component>.log (full run log), <component>.status (one line per problem;
# empty = clean), <component>.running (pid marker, removed on exit) — and
# installs the same login banner, which reports every component that is still
# running, was interrupted, or errored, or one green "setup complete" line
# naming them all. The banner is duplicated (not shared at runtime) because
# Codespaces clones this repo on its own, so neither script depends on the
# other or on the order they run in. Keep the banner byte-identical across
# repos; test-setup-banner.sh (identical in both) guards it.
STATE_DIR="$HOME/.codespace-setup.d"
COMPONENT="dotfiles"
COMPONENT_LABEL="dotfiles (nija-at/CodespacesHome install.sh)"
STATE_LOG="$STATE_DIR/$COMPONENT.log"
STATE_STATUS="$STATE_DIR/$COMPONENT.status"
STATE_RUNNING="$STATE_DIR/$COMPONENT.running"

dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
# term — print to the terminal only (fd 3, saved by status_begin), not the log.
term() { printf '%s' "$*" >&3; }
# say — print a full line to both the terminal and the log.
say()  { printf '%s\n' "$*" >&3; printf '%s\n' "$*"; }

# Safety net: if the script exits non-zero for a reason run_step never saw
# (a bug in this orchestration code, an unset variable, ...), record a
# generic entry so the login banner still fires instead of staying silent.
# Skipped when STATE_STATUS already has real entries, so we don't double up
# on the deliberate `exit 1` below. The one thing this can't catch is
# SIGKILL — no trap survives that, in bash or otherwise; the leftover
# .running marker is what makes the banner report that case.
on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$STATE_STATUS" ]; then
    echo "install.sh (unexpected exit $rc, see $STATE_LOG)" >>"$STATE_STATUS"
  fi
  rm -f "$STATE_RUNNING"
}

# status_begin — create the state dir, reset this run's log + status, mark the
# component running, and send all further output to STATE_LOG only; the
# terminal gets just the compact per-step lines written via `term`/`say`.
status_begin() {
  mkdir -p "$STATE_DIR"
  : >"$STATE_STATUS"
  : >"$STATE_LOG"
  printf 'pid=%s\nstarted=%s\nlabel=%s\n' \
    "$$" "$(date -u +%FT%TZ)" "$COMPONENT_LABEL" >"$STATE_RUNNING"
  trap on_exit EXIT
  exec 3>&1 >>"$STATE_LOG" 2>&1
}

# install_status_banner — write the shell-rc login banner and wire it into
# ~/.bashrc and ~/.zshrc (idempotent). The banner scans STATE_DIR and reports
# any component that is still running, was interrupted, or logged errors; it is
# silent when everything finished cleanly. Both this script and the dotfiles
# install.sh install the identical banner, so whichever runs keeps it current.
install_status_banner() {
  local check="$HOME/.codespace-setup-login-check.sh"
  cat >"$check" <<'BANNER'
# Codespace setup status banner (auto-generated; sourced from your shell rc).
# Heads-up when bootstrap scripts are still running, were interrupted, or hit
# errors. Silent once everything has finished cleanly.
__codespace_setup_banner() {
  emulate -L sh 2>/dev/null || true   # zsh: sh-compat (no nomatch) scoped here
  dir="$HOME/.codespace-setup.d"
  [ -d "$dir" ] || return 0
  running=''; interrupted=''; errored=''; complete=''
  for f in "$dir"/*.running; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .running)
    pid=$(sed -n 's/^pid=//p' "$f" 2>/dev/null)
    label=$(sed -n 's/^label=//p' "$f" 2>/dev/null)
    [ -n "$label" ] || label=$name
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      running="${running}${label}|"
    else
      interrupted="${interrupted}${label}|${dir}/${name}.log|"
    fi
  done
  for f in "$dir"/*.status; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .status)
    if [ -s "$f" ]; then
      errored="$errored $f"
    elif [ ! -e "$dir/$name.running" ]; then
      complete="${complete}${name} "
    fi
  done
  # Anything wrong takes priority and stays loud; otherwise a short green line
  # confirms the tracking is working and every component finished cleanly.
  if [ -n "$running$interrupted$errored" ]; then
    printf '\n'
    if [ -n "$running" ]; then
      printf '\033[1;33m⏳ Codespace setup is still running:\033[0m\n'
      old_ifs=$IFS; IFS='|'; set -- $running; IFS=$old_ifs
      for x in "$@"; do [ -n "$x" ] && printf '   • %s\n' "$x"; done
      printf '   It will finish on its own; reopen this terminal in a moment.\n'
    fi
    if [ -n "$interrupted" ]; then
      printf '\033[1;31m⚠ Codespace setup did NOT finish (interrupted before completion):\033[0m\n'
      old_ifs=$IFS; IFS='|'; set -- $interrupted; IFS=$old_ifs
      while [ "$#" -ge 2 ]; do
        lbl=$1; lg=$2; shift 2
        [ -n "$lbl" ] || continue
        printf '   • %s — see %s; re-run its setup script to finish.\n' "$lbl" "$lg"
      done
    fi
    if [ -n "$errored" ]; then
      printf '\033[1;31m⚠ Codespace setup reported errors:\033[0m\n'
      for f in $errored; do
        name=$(basename "$f" .status)
        printf '   %s:\n' "$name"
        sed 's/^/     - /' "$f" 2>/dev/null
        printf '     log: %s/%s.log\n' "$dir" "$name"
      done
    fi
    printf '   Fix, then re-run the setup script — or `rm -rf %s` to dismiss.\n' "$dir"
    printf '\n'
  elif [ -n "$complete" ]; then
    set -- $complete
    names=$1; shift
    for n in "$@"; do names="$names, $n"; done
    printf '\033[1;32m✓ Codespace setup complete:\033[0m %s\n' "$names"
  fi
}
__codespace_setup_banner
unset -f __codespace_setup_banner 2>/dev/null || true
BANNER
  local src='. "$HOME/.codespace-setup-login-check.sh"'
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -qF '.codespace-setup-login-check.sh' "$rc" \
      || printf '\n%s\n' "$src" >>"$rc"
  done
}

# Remove the pre-shared-banner mechanism (its own status file + login check),
# superseded by STATE_DIR and the shared banner above.
remove_legacy_banner() {
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] && sed -i '/\.dotfiles-login-check\.sh/d' "$rc"
  done
  rm -f "$HOME/.dotfiles-login-check.sh" "$HOME/.dotfiles-install-status" \
    "$HOME/.dotfiles-install.log"
}

# Status plumbing goes FIRST, before anything that can fail: if it ran last, a
# script death before reaching it would silently skip installing the very
# mechanism meant to report that death. It only depends on local file writes.
status_begin
install_status_banner
remove_legacy_banner

# run_step <label> <function> — run a step in its own subshell (with set -e so
# it stops at its first internal error), print one "[i/N] label… ✓/✗ Ns" line,
# and on failure record "<label>: <last output line>" in STATE_STATUS without
# aborting the rest of the script.
STEP_TOTAL=5 STEP_I=0 STEP_FAILED=0
run_step() {
  local label="$1" fn="$2" rc start dur out detail
  STEP_I=$((STEP_I + 1))
  term "$(printf '\033[1;34m==>\033[0m [%d/%d] %s… ' "$STEP_I" "$STEP_TOTAL" "$label")"
  log "[$STEP_I/$STEP_TOTAL] $label…"
  out="$(mktemp)"
  start=$SECONDS
  # Capture the exit code into a variable rather than testing the subshell
  # directly in `if` — bash silently disables a subshell's own `set -e` when
  # the subshell is itself an `if`/`&&`/`||` condition.
  ( set -e; "$fn" ) >"$out" 2>&1
  rc=$?
  dur=$((SECONDS - start))
  cat "$out"
  if [ "$rc" -eq 0 ]; then
    term "$(printf '\033[1;32m✓\033[0m %ss' "$dur")"$'\n'
    log "[$STEP_I/$STEP_TOTAL] $label — ✓ ${dur}s"
  else
    STEP_FAILED=$((STEP_FAILED + 1))
    detail="$(grep -v '^[[:space:]]*$' "$out" | tail -n 1)"
    detail="$label: ${detail:-exit $rc}"
    echo "$detail" >>"$STATE_STATUS"
    term "$(printf '\033[1;31m✗ FAILED\033[0m %ss' "$dur")"$'\n'
    term "$(printf '      \033[1;33m!\033[0m %s' "$detail")"$'\n'
    log "[$STEP_I/$STEP_TOTAL] $label — ✗ FAILED ${dur}s (exit $rc)"
  fi
  rm -f "$out"
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

# Registers plugin marketplaces and installs the plugins this repo makes
# available. Installing (rather than only declaring the marketplace) populates
# ~/.claude/plugins/cache/, which doesn't survive between ephemeral codespaces.
# Enablement is opt-in and handled separately: this repo's settings.json sets a
# global default of `false` for each installed plugin, and individual project
# repos flip the ones they want to `true` in their own .claude/settings.json.
# Idempotent: `marketplace add` no-ops if already declared, and `install`
# no-ops if the plugin is already present.
step_plugins() {
  claude plugin marketplace add anthropics/claude-plugins-official
  claude plugin install frontend-design@claude-plugins-official
  echo "plugins installed"
}

# Installs the global agent instructions to ~/AGENTS.md, with ~/CLAUDE.md
# importing it. Both are overwritten on every run so their content stays in
# sync with this repo.
step_global_agents() {
  cp "$dotfiles_dir/home/AGENTS.md.template" "$HOME/AGENTS.md"
  cp "$dotfiles_dir/home/CLAUDE.md.template" "$HOME/CLAUDE.md"
  echo "global AGENTS.md and CLAUDE.md installed"
}

started=$SECONDS
say "$(log "Installing dotfiles from $dotfiles_dir")"
run_step "claude code" step_claude
run_step "statusline" step_statusline
run_step "settings" step_settings
run_step "plugins" step_plugins
run_step "global agents" step_global_agents
say "$(log "Done: $((STEP_TOTAL - STEP_FAILED)) succeeded, $STEP_FAILED failed in $((SECONDS - started))s — full log: $STATE_LOG")"

[ "$STEP_FAILED" -eq 0 ] || exit 1
