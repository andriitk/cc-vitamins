#!/bin/sh
# cc-vitamins test suite — pure POSIX sh, no external test framework.
#
# Each case feeds a fixture to bin/cc-vitamins in a hermetic environment:
#   - NO_COLOR=1 so output is plain text
#   - HOME / XDG_CACHE_HOME / XDG_CONFIG_HOME under a fresh temp dir
#   - ccusage disabled (CC_VITAMINS_CCUSAGE=0) so no network/process spawns
#   - cwd fields point at nonexistent paths, so the git segment stays empty
#
# Exit status is non-zero if any assertion fails.

set -u

TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=${TESTS_DIR%/tests}
BIN="$ROOT_DIR/bin/cc-vitamins"
FIX="$TESTS_DIR/fixtures"

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/cc-vitamins-test.XXXXXX") || exit 1
trap 'rm -rf "$TMPROOT"' EXIT

HOME="$TMPROOT/home"
XDG_CACHE_HOME="$TMPROOT/cache"
XDG_CONFIG_HOME="$TMPROOT/config"
export HOME XDG_CACHE_HOME XDG_CONFIG_HOME
export NO_COLOR=1
export CC_VITAMINS_CCUSAGE=0
mkdir -p "$HOME" "$XDG_CACHE_HOME/cc-vitamins" "$XDG_CONFIG_HOME"

PASS=0
FAIL=0

# render <fixture> — print rendered status for a fixture file.
render() { "$BIN" < "$FIX/$1"; }

ok()   { PASS=$(( PASS + 1 )); printf 'ok   - %s\n' "$1"; }
bad()  { FAIL=$(( FAIL + 1 )); printf 'FAIL - %s\n' "$1"; printf '       %s\n' "$2"; }

assert_contains() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) ok "$1" ;;
    *)      bad "$1" "expected to contain: [$3]${NL}got: [$2]" ;;
  esac
}

assert_equals() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then ok "$1"
  else bad "$1" "expected: [$3]${NL}actual:   [$2]"; fi
}

assert_lines() { # <name> <output> <n>
  _n=$(printf '%s\n' "$2" | grep -c '')
  if [ "$_n" = "$3" ]; then ok "$1"
  else bad "$1" "expected $3 line(s), got $_n"; fi
}

NL='
'

# ── Case: basic (line 1 exact, context + session cost) ───────────────────────
printf '%s 0\n' "$(date +%Y%m%d)" > "$XDG_CACHE_HOME/cc-vitamins/day-sess-basic"
out=$(CC_VITAMINS_LINE2="context session_cost" render basic.json)
l1=$(printf '%s\n' "$out" | sed -n '1p')
l2=$(printf '%s\n' "$out" | sed -n '2p')
assert_equals "basic/line1" "$l1" "myproject · Sonnet 4.6 high · ⏱ 23m45s · +40 -7"
assert_contains "basic/ctx-bar" "$l2" "ctx █████░░░░░░░ 42%"
assert_contains "basic/ctx-tokens" "$l2" "84k/200k"
assert_contains "basic/session-cost" "$l2" "session \$1.23"

# ── Case: big window colored by absolute tokens, humanized sizes ─────────────
out=$(CC_VITAMINS_LINE2="context" render big_window.json)
assert_contains "bigwin/tokens" "$out" "300k/1M"
assert_contains "bigwin/pct" "$out" "30%"

# ── Case: minimal input prints only line 1 (no empty line 2) ─────────────────
out=$(CC_VITAMINS_LINE2="context cache session_cost today spend ratelimits" render minimal.json)
assert_lines "minimal/one-line" "$out" 1
assert_equals "minimal/line1" "$out" "solo · Haiku 4.5"

# ── Case: vim mode, cold cache, spend limit, rate limits ─────────────────────
out=$(CC_VITAMINS_LINE2="cache spend ratelimits" render vim_cold.json)
l1=$(printf '%s\n' "$out" | sed -n '1p')
l2=$(printf '%s\n' "$out" | sed -n '2p')
assert_contains "vim/mode" "$l1" "[N] myproject"
assert_contains "vim/fast" "$l1" "⚡fast"
assert_contains "cold/cache" "$l2" "cache 80% cold"
assert_contains "spend/segment" "$l2" "spend \$3.50/\$50.00"
assert_contains "ratelimit/5h" "$l2" "5h 45%"
assert_contains "ratelimit/7d" "$l2" "7d 12%"

# ── Case: context token delta from seeded prior state ────────────────────────
printf '70000 50000\n' > "$XDG_CACHE_HOME/cc-vitamins/ctx-sess-delta"
out=$(CC_VITAMINS_LINE2="context" render delta.json)
assert_contains "delta/up" "$out" "▲+14k"

# ── Case: active-session heartbeat counts this live process ──────────────────
out=$(CC_VITAMINS_LINE2="sessions" render basic.json)
assert_contains "sessions/present" "$out" "session"

# ── Case: missing jq produces a single hint line (not a crash) ───────────────
fakepath="$TMPROOT/nojq"
mkdir -p "$fakepath"
for t in sh cat date awk sed grep basename dirname mktemp find stat chmod printf readlink; do
  _p=$(command -v "$t" 2>/dev/null) && ln -sf "$_p" "$fakepath/$t" 2>/dev/null
done
out=$(PATH="$fakepath" sh "$BIN" < "$FIX/basic.json" 2>&1)
assert_contains "nojq/hint" "$out" "jq not found"

# ── Case: plan matrix ────────────────────────────────────────────────────────
# Pro/Max: 5h/7d windows with reset times, $ figures are estimates (≈).
now=$(date +%s)
cat > "$TMPROOT/max.json" <<JSON
{ "cwd": "/nonexistent/maxproj", "session_id": "sess-max",
  "model": { "display_name": "Opus 4.6" },
  "cost": { "total_cost_usd": 4.5 },
  "rate_limits": {
    "five_hour": { "used_percentage": 61.4, "resets_at": $(( now + 7830 )) },
    "seven_day": { "used_percentage": 22, "resets_at": $(( now + 3 * 86400 + 4 * 3600 + 60 )) } } }
JSON
printf '%s 0\n' "$(date +%Y%m%d)" > "$XDG_CACHE_HOME/cc-vitamins/day-sess-max"
out=$(CC_VITAMINS_LINE2="session_cost spend ratelimits" "$BIN" < "$TMPROOT/max.json")
assert_contains "max/5h-reset" "$out" "5h 61% ↻2h10m"
assert_contains "max/7d-reset" "$out" "7d 22% ↻3d4h"
assert_contains "max/cost-estimate" "$out" "session ≈\$4.50"
out=$(CC_VITAMINS_RESET_COUNTDOWN=0 CC_VITAMINS_LINE2="ratelimits" "$BIN" < "$TMPROOT/max.json")
assert_contains "max/no-countdown" "$out" "5h 61% · 7d 22%"

# Team/Enterprise/API: no rate_limits at all; plain $ and no limit segments.
out=$(CC_VITAMINS_LINE2="session_cost spend ratelimits" render basic.json)
l2=$(printf '%s\n' "$out" | sed -n '2p')
assert_equals "enterprise/line2" "$l2" "session \$1.23"

# Gateway spend limit: percentage arrives before the dollar figures.
printf '%s\n' '{"cwd":"/nonexistent/gw","session_id":"sess-gw","model":{"display_name":"Opus"},
  "rate_limits":{"spend_limit":{"used_percentage":63.2,"resets_at":1}}}' > "$TMPROOT/gw.json"
out=$(CC_VITAMINS_LINE2="spend" "$BIN" < "$TMPROOT/gw.json")
assert_contains "gateway/pct-only" "$out" "spend 63%"
out=$(CC_VITAMINS_LINE2="spend" render vim_cold.json)
assert_contains "gateway/period" "$out" "spend \$3.50/\$50.00/mo"

# ── Case: rows wrap between segments to fit COLUMNS ──────────────────────────
for colored in 1 0; do
  if [ "$colored" = 1 ]; then
    out=$(env -u NO_COLOR COLUMNS=40 CC_VITAMINS_LINE2="session_cost ratelimits" "$BIN" < "$TMPROOT/max.json" \
      | sed "s/$(printf '\033')\\[[0-9;]*m//g")
  else
    out=$(COLUMNS=40 CC_VITAMINS_LINE2="session_cost ratelimits" "$BIN" < "$TMPROOT/max.json")
  fi
  assert_lines "wrap/rows-color=$colored" "$out" 3
  assert_contains "wrap/segment-intact-color=$colored" "$out" "5h 61% ↻2h10m"
done
out=$(COLUMNS=500 CC_VITAMINS_LINE2="session_cost ratelimits" "$BIN" < "$TMPROOT/max.json")
assert_lines "wrap/wide-no-wrap" "$out" 2

# ── Case: comma-decimal locale still renders numbers ─────────────────────────
for loc in de_DE.UTF-8 uk_UA.UTF-8; do
  out=$(LC_ALL=$loc LANG=$loc CC_VITAMINS_LINE2="context" render basic.json 2>&1)
  assert_contains "locale/$loc" "$out" "42% 84k/200k"
done

# ── Case: installer install -> reinstall -> uninstall restores the original ──
CFG="$TMPROOT/claude"
mkdir -p "$CFG"
printf '%s\n' '{"model":"opus","statusLine":{"type":"command","command":"echo it'"'"'s mine"}}' > "$CFG/settings.json"
CLAUDE_CONFIG_DIR="$CFG" sh "$ROOT_DIR/install.sh" --force >/dev/null 2>&1
assert_equals "install/command" "$(jq -r .statusLine.command "$CFG/settings.json")" "$CFG/cc-vitamins/bin/cc-vitamins"
assert_equals "install/keeps-keys" "$(jq -r .model "$CFG/settings.json")" "opus"
CLAUDE_CONFIG_DIR="$CFG" sh "$ROOT_DIR/install.sh" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$CFG" sh "$ROOT_DIR/install.sh" --uninstall >/dev/null 2>&1
assert_equals "uninstall/restores" "$(jq -r .statusLine.command "$CFG/settings.json")" "echo it's mine"
[ ! -d "$CFG/cc-vitamins" ] && ok "uninstall/removes-files" || bad "uninstall/removes-files" "dir still exists"

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
