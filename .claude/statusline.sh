#!/usr/bin/env bash
# Claude Code statusLine script. Installed to ~/.claude/statusline.sh by install.sh.
# Receives session JSON on stdin; see https://code.claude.com/docs/en/statusline.md
set -euo pipefail

input=$(cat)

RESET='\033[0m'
CYAN='\033[36m'
DIM='\033[2m'
GREEN='\033[32m'
PINK='\033[35m'

# 256-color escape for a percentage, as a green->yellow->orange->red gradient
# that deepens in five 20-point steps.
color_for() {
  local code
  code=$(awk -v p="$1" 'BEGIN {
    if      (p >= 80) c = 196;  # deep red
    else if (p >= 60) c = 208;  # orange
    else if (p >= 40) c = 220;  # amber
    else if (p >= 20) c = 154;  # yellow-green
    else              c = 46;   # green
    print c;
  }')
  printf '\033[38;5;%sm' "$code"
}

raw_dir=$(jq -r '.workspace.current_dir // .cwd // "~"' <<<"$input")
dir="${raw_dir/#$HOME/~}"

# Left side: cwd (+ git branch) + context usage.
left="${CYAN}${dir}${RESET}"
left_plain="$dir"

if git -C "$raw_dir" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$raw_dir" branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    left+=" ${PINK}(${branch})${RESET}"
    left_plain+=" ($branch)"
  fi
fi

model=$(jq -r '.model.display_name // empty' <<<"$input")
effort=$(jq -r '.effort.level // empty' <<<"$input")
if [ -n "$model" ]; then
  model_str="$model"
  [ -n "$effort" ] && model_str+="/$effort"
  left+=" ${DIM}|${RESET} ${GREEN}${model_str}${RESET}"
  left_plain+=" | ${model_str}"
fi

ctx_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
if [ -n "$ctx_pct" ]; then
  ctx_pct=$(awk -v p="$ctx_pct" 'BEGIN { printf "%.0f", p }')
  c=$(color_for "$ctx_pct")
  left+=" ${DIM}|${RESET} ${DIM}ctx${RESET} ${c}${ctx_pct}%${RESET}"
  left_plain+=" | ctx ${ctx_pct}%"
fi

# Right side: rate-limit usage, right-aligned.
right=""
right_plain=""
add_right() {
  local label=$1 pct c
  pct=$(awk -v p="$2" 'BEGIN { printf "%.0f", p }')
  c=$(color_for "$pct")
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

# Reserve a safety margin for the interface's own edges/padding so the
# right-aligned part never overflows and gets cut off.
margin=8
cols=$(( ${COLUMNS:-80} - margin ))
needed=$(( ${#left_plain} + ${#right_plain} + 1 ))

if [ -n "$right_plain" ] && [ "$needed" -le "$cols" ]; then
  pad=$(( cols - ${#left_plain} - ${#right_plain} ))
  printf -v padding '%*s' "$pad" ""
  printf '%b\n' "${left}${padding}${right}"
elif [ -n "$right_plain" ]; then
  # Not enough room to right-align without overflowing; fall back to inline.
  printf '%b\n' "${left} ${DIM}|${RESET} ${right}"
else
  printf '%b\n' "$left"
fi
