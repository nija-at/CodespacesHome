#!/usr/bin/env bash
# Claude Code statusLine script. Installed to ~/.claude/statusline.sh by install.sh.
# Receives session JSON on stdin; see https://code.claude.com/docs/en/statusline.md
set -euo pipefail

input=$(cat)

RESET='\033[0m'
CYAN='\033[36m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'

# Color for a percentage: green < 50, yellow < 80, red >= 80.
pct_color() {
  awk -v p="$1" 'BEGIN {
    if (p >= 80) print "red";
    else if (p >= 50) print "yellow";
    else print "green";
  }'
}

color_for() {
  case "$1" in
    red) printf '%b' "$RED" ;;
    yellow) printf '%b' "$YELLOW" ;;
    green) printf '%b' "$GREEN" ;;
  esac
}

fmt_tokens() {
  local n=$1
  if [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN{printf "%.1fk", n/1000}'
  else
    printf '%s' "$n"
  fi
}

dir=$(jq -r '.workspace.current_dir // .cwd // "~"' <<<"$input")
dir="${dir/#$HOME/~}"

# Left side: cwd + context usage.
left="${CYAN}${dir}${RESET}"
left_plain="$dir"

ctx_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
if [ -n "$ctx_pct" ]; then
  ctx_in=$(jq -r '.context_window.total_input_tokens // empty' <<<"$input")
  ctx_size=$(jq -r '.context_window.context_window_size // empty' <<<"$input")
  c=$(color_for "$(pct_color "$ctx_pct")")
  if [ -n "$ctx_in" ] && [ -n "$ctx_size" ]; then
    tokens="($(fmt_tokens "$ctx_in")/$(fmt_tokens "$ctx_size"))"
    left+=" ${DIM}|${RESET} ${DIM}ctx${RESET} ${c}${ctx_pct}%${RESET} ${DIM}${tokens}${RESET}"
    left_plain+=" | ctx ${ctx_pct}% ${tokens}"
  else
    left+=" ${DIM}|${RESET} ${DIM}ctx${RESET} ${c}${ctx_pct}%${RESET}"
    left_plain+=" | ctx ${ctx_pct}%"
  fi
fi

# Right side: rate-limit usage, right-aligned.
right=""
right_plain=""
add_right() {
  local label=$1 pct=$2 c
  c=$(color_for "$(pct_color "$pct")")
  if [ -n "$right_plain" ]; then
    right+=" ${DIM}|${RESET} "
    right_plain+=" | "
  fi
  right+="${DIM}${label}${RESET} ${c}${pct}%${RESET}"
  right_plain+="${label} ${pct}%"
}

five_hour=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
[ -n "$five_hour" ] && add_right "5h" "$five_hour"

seven_day=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")
[ -n "$seven_day" ] && add_right "7d" "$seven_day"

cols="${COLUMNS:-80}"
if [ -n "$right_plain" ]; then
  pad=$(( cols - ${#left_plain} - ${#right_plain} - 1 ))
  [ "$pad" -lt 1 ] && pad=1
  printf -v padding '%*s' "$pad" ""
  printf '%b\n' "${left}${padding}${right}"
else
  printf '%b\n' "$left"
fi
