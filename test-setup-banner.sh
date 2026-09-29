#!/usr/bin/env bash
#
# test-setup-banner.sh — assert the login-banner state machine embedded in the
# setup script behaves correctly across its states, in both bash and zsh.
#
# The banner is the one piece of these bootstrap scripts with non-trivial,
# cross-shell, pure logic — and when it regresses it fails *silently* (the
# banner just stops appearing), which reintroduces the exact "codespace hung
# with no signal" bug it exists to prevent. So it gets a test; the network/
# side-effect step orchestration around it does not.
#
# The banner body is extracted from the setup script itself (the single source
# of truth), so this test also catches the banner drifting from what ships.
# This file is intentionally identical in the project repo and the personal
# dotfiles repo (it auto-detects setup.sh vs install.sh) — running it in both
# is what guards the two copied banners against diverging.
#
# Run: bash scripts/test-setup-banner.sh   (or `npm run test:setup`)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target script: an explicit arg, else the setup script next to this test.
SCRIPT="${1:-}"
if [ -z "$SCRIPT" ]; then
  for c in "$HERE/setup.sh" "$HERE/install.sh"; do
    [ -f "$c" ] && SCRIPT="$c" && break
  done
fi
if [ -z "$SCRIPT" ] || [ ! -f "$SCRIPT" ]; then
  echo "FAIL: could not find a setup script to test (looked for setup.sh / install.sh next to this file)"
  exit 1
fi

tmp="$(mktemp -d)"
SLEEP_PID=""
cleanup() { rm -rf "$tmp"; [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; }
trap cleanup EXIT

# Extract the banner between the `<<'BANNER'` heredoc markers.
banner="$tmp/banner.sh"
awk '/<<.BANNER.$/{flag=1;next} /^BANNER$/{flag=0} flag' "$SCRIPT" >"$banner"
if [ ! -s "$banner" ]; then
  echo "FAIL: could not extract banner from $SCRIPT"
  exit 1
fi

fail=0

# check <desc> <expect|-> <output> — with expect '-' the output must be silent.
check() {
  local desc="$1" want="$2" out="$3"
  if [ "$want" = "-" ]; then
    if [ -n "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
      echo "FAIL [$desc]: expected silence, got: $out"; fail=1; return
    fi
  elif ! printf '%s' "$out" | grep -qF "$want"; then
    echo "FAIL [$desc]: expected output to contain: $want"; fail=1; return
  fi
  echo "ok   [$desc]"
}

shells=(bash)
command -v zsh >/dev/null 2>&1 && shells+=(zsh)

for sh in "${shells[@]}"; do
  # still running: marker present, pid alive
  sleep 300 & SLEEP_PID=$!
  h="$tmp/running"; rm -rf "$h"; mkdir -p "$h/.codespace-setup.d"
  printf 'pid=%s\nstarted=x\nlabel=demo component\n' "$SLEEP_PID" \
    >"$h/.codespace-setup.d/demo.running"
  check "$sh/running" "still running" "$(HOME="$h" "$sh" "$banner")"
  kill "$SLEEP_PID" 2>/dev/null; SLEEP_PID=""

  # interrupted: marker present, pid dead
  h="$tmp/int"; rm -rf "$h"; mkdir -p "$h/.codespace-setup.d"
  printf 'pid=2147480000\nstarted=x\nlabel=demo component\n' \
    >"$h/.codespace-setup.d/demo.running"
  check "$sh/interrupted" "did NOT finish" "$(HOME="$h" "$sh" "$banner")"

  # errored: non-empty status, no marker — detail line must surface
  h="$tmp/err"; rm -rf "$h"; mkdir -p "$h/.codespace-setup.d"
  printf 'plugins: boom detail\n' >"$h/.codespace-setup.d/demo.status"
  check "$sh/errored" "boom detail" "$(HOME="$h" "$sh" "$banner")"

  # complete: empty status, no marker — short success line naming the component
  h="$tmp/clean"; rm -rf "$h"; mkdir -p "$h/.codespace-setup.d"
  : >"$h/.codespace-setup.d/demo.status"
  out="$(HOME="$h" "$sh" "$banner")"
  check "$sh/complete-line" "setup complete" "$out"
  check "$sh/complete-names" "demo" "$out"

  # errored takes priority over complete: one errored + one clean -> no success
  h="$tmp/mixed"; rm -rf "$h"; mkdir -p "$h/.codespace-setup.d"
  printf 'boom detail\n' >"$h/.codespace-setup.d/bad.status"
  : >"$h/.codespace-setup.d/good.status"
  out="$(HOME="$h" "$sh" "$banner")"
  check "$sh/mixed-shows-error" "boom detail" "$out"
  if printf '%s' "$out" | grep -qF "setup complete"; then
    echo "FAIL [$sh/mixed-no-success]: success line shown despite an error"; fail=1
  else
    echo "ok   [$sh/mixed-no-success]"
  fi

  # per-step summary is replayed in every terminal, before the verdict line
  h="$tmp/summary"; rm -rf "$h"; mkdir -p "$h/.codespace-setup.d"
  : >"$h/.codespace-setup.d/demo.status"
  printf '==> [1/2] step one… ✓ 3s\n==> Done: 2 succeeded, 0 failed in 5s\n' \
    >"$h/.codespace-setup.d/demo.summary"
  out="$(HOME="$h" "$sh" "$banner")"
  check "$sh/summary-step-line" "[1/2] step one… ✓ 3s" "$out"
  check "$sh/summary-done-line" "Done: 2 succeeded" "$out"
  if [ "$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1 | grep -c 'setup complete')" -eq 1 ]; then
    echo "ok   [$sh/summary-verdict-last]"
  else
    echo "FAIL [$sh/summary-verdict-last]: verdict is not the last line: $out"; fail=1
  fi

  # summary also shown alongside errors (so you see which step failed)
  printf 'step two: boom\n' >"$h/.codespace-setup.d/demo.status"
  out="$(HOME="$h" "$sh" "$banner")"
  check "$sh/summary-with-error" "[1/2] step one" "$out"
  check "$sh/summary-error-detail" "step two: boom" "$out"

  # no state dir at all — must be silent
  h="$tmp/none"; rm -rf "$h"; mkdir -p "$h"
  check "$sh/nodir-silent" "-" "$(HOME="$h" "$sh" "$banner")"
done

if [ "$fail" -ne 0 ]; then
  echo "BANNER TESTS FAILED"
  exit 1
fi
echo "All banner tests passed (shells: ${shells[*]})."
