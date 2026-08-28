#!/usr/bin/env bash
# Claude Code statusLine script. Installed to ~/.claude/statusline.sh by install.sh.
# Receives session JSON on stdin; see https://code.claude.com/docs/en/statusline.md
set -euo pipefail

input=$(cat)

dir=$(jq -r '.workspace.current_dir // .cwd // "~"' <<<"$input")
dir="${dir/#$HOME/~}"

fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN{printf "%.1fk", n/1000}'
  else
    printf '%s' "$n"
  fi
}

line="$dir"

ctx_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
if [ -n "$ctx_pct" ]; then
  ctx_in=$(jq -r '.context_window.total_input_tokens // empty' <<<"$input")
  ctx_size=$(jq -r '.context_window.context_window_size // empty' <<<"$input")
  if [ -n "$ctx_in" ] && [ -n "$ctx_size" ]; then
    line+=" | ctx ${ctx_pct}% ($(fmt_tokens "$ctx_in")/$(fmt_tokens "$ctx_size"))"
  else
    line+=" | ctx ${ctx_pct}%"
  fi
fi

five_hour=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
[ -n "$five_hour" ] && line+=" | 5h ${five_hour}%"

seven_day=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")
[ -n "$seven_day" ] && line+=" | 7d ${seven_day}%"

printf '%s\n' "$line"
