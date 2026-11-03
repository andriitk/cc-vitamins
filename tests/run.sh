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

TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
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
assert_equals "basic/line1" "$l1" "myproject · Sonnet 4.6 high · ⏱ 23m45s · +40 -7 · cc v2.1.296"
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

# ── Case: one process with several session IDs counts once ────────────────
SD="$XDG_CACHE_HOME/cc-vitamins/sessions"
rm -rf "$SD"; mkdir -p "$SD"
printf '%s' "$$" > "$SD/old-session-of-this-process"
printf '%s' "$$" > "$SD/new-session-of-this-process"
printf '%s' "999999" > "$SD/dead-session"
out=$(CC_VITAMINS_LINE2="sessions" sh -c '. "$0/lib/sessions.sh"; count_live_sessions "$1"' "$ROOT_DIR" "$SD")
assert_equals "sessions/dedupe-pids" "$out" "1"
if [ -f "$SD/dead-session" ]; then bad "sessions/prune-dead" "dead heartbeat kept"; else ok "sessions/prune-dead"; fi

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

# ── Case: escape sequences in field values are neutralized ───────────────────
out=$(printf '%s' '{"cwd":"/x/evil\\033]0;pwned\\007dir","session_id":"s-esc","session_name":"a\\nb","model":{"display_name":"M"}}' \
  | "$BIN" | sed -n 1p)
assert_equals "escape/stripped" "$out" "evil033]0;pwned007dir [anb] · M"

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
if [ -d "$CFG/cc-vitamins" ]; then bad "uninstall/removes-files" "dir still exists"
else ok "uninstall/removes-files"; fi

# ── Accounts (ccv): setup, routing, sharing, switching, status line ──────────
CCV="$ROOT_DIR/bin/ccv"
export CCV_CLAUDE="$TESTS_DIR/fake-claude"
export FAKE_CLAUDE_LOG="$TMPROOT/claude.log"
unset CLAUDE_CONFIG_DIR CLAUDECODE CCV_ACCOUNT CCV_RUN ANTHROPIC_API_KEY 2>/dev/null || :
SHELL=/bin/zsh; export SHELL
HOME=$(cd "$HOME" && pwd -P); export HOME
P="$HOME/.claude"
mkdir -p "$P/skills/demo" "$P/projects" "$P/backups" "$HOME/work/repo" "$HOME/other"
printf '{"model":"opus"}\n' > "$P/settings.json"
printf 'secret\n' > "$P/.credentials.json"
printf '{}\n' > "$P/remote-settings.json"
printf '%s\n' '{"hasCompletedOnboarding":true,"oauthAccount":{"accountUuid":"p","organizationType":"claude_enterprise"},
  "mcpServers":{"a":{"type":"http","url":"https://a"},"shared":{"type":"http","url":"https://primary"}},
  "projects":{"'"$HOME"'/other":{"hasTrustDialogAccepted":true}}}' > "$HOME/.claude.json"
lastlog() { tail -n 1 "$FAKE_CLAUDE_LOG"; }

# Feature off: no config → claude runs untouched.
: > "$FAKE_CLAUDE_LOG"
(cd "$HOME/other" && "$CCV" launch --model opus >/dev/null 2>&1)
assert_equals "acc/off-passthrough" "$(lastlog)" "cfg=<unset> args=--model opus"
out=$("$CCV" 2>&1)
assert_contains "acc/off-list-hint" "$out" "ccv add <name>"

# add: config, links, per-account files, seeded JSON, login in the new dir.
out=$("$CCV" add personal < /dev/null 2>&1)
assert_contains "acc/add-says-ready" "$out" "Account 'personal' ready"
assert_contains "acc/add-no-prompt" "$out" "ccv shell-init --install"
A="$HOME/.claude-personal"
cfg="$XDG_CONFIG_HOME/cc-vitamins/accounts"
assert_contains "acc/config-primary" "$(cat "$cfg")" "account default ~/.claude blue"
assert_contains "acc/config-extra" "$(cat "$cfg")" "account personal ~/.claude-personal green"
for e in skills projects settings.json; do
  if [ -L "$A/$e" ] && [ "$(readlink "$A/$e")" = "$P/$e" ]; then ok "acc/linked-$e"
  else bad "acc/linked-$e" "not a link to $P/$e"; fi
done
for e in .credentials.json remote-settings.json backups; do
  if [ -e "$A/$e" ] || [ -L "$A/$e" ]; then bad "acc/private-$e" "$e must not be shared"
  else ok "acc/private-$e"; fi
done
assert_contains "acc/login-in-new-dir" "$(cat "$FAKE_CLAUDE_LOG")" "cfg=$A args=auth login"
assert_equals "acc/seed-mcp" "$(jq -r '.mcpServers.a.url' "$A/.claude.json")" "https://a"
assert_equals "acc/seed-onboarding" "$(jq -r '.hasCompletedOnboarding' "$A/.claude.json")" "true"
# shellcheck disable=SC2012 # one known file; ls -l is the portable way to read its mode
assert_equals "acc/json-mode" "$(ls -l "$A/.claude.json" | cut -c1-10)" "-rw-------"
out=$("$CCV" add personal < /dev/null 2>&1)
assert_contains "acc/add-twice-refused" "$out" "already exists"
mkdir -p "$HOME/busy" && : > "$HOME/busy/x"
out=$("$CCV" add busy --dir "$HOME/busy" < /dev/null 2>&1)
assert_contains "acc/add-nonempty-refused" "$out" "not empty"

# list
out=$(cd "$HOME/other" && "$CCV")
assert_contains "acc/list-primary" "$out" "default        Enterprise  yes"
assert_contains "acc/list-extra" "$out" "personal       Pro         yes"

# routing: route + default, longest match, --account override (not passed on).
"$CCV" route "$HOME/work" default >/dev/null
"$CCV" default personal >/dev/null
(cd "$HOME/work/repo" && "$CCV" launch >/dev/null 2>&1)
assert_equals "acc/route-work" "$(lastlog)" "cfg=<unset> args="
(cd "$HOME/other" && "$CCV" launch -p hi >/dev/null 2>&1)
assert_equals "acc/route-default" "$(lastlog)" "cfg=$A args=-p hi"
(cd "$HOME/other" && "$CCV" launch --account default -p hi >/dev/null 2>&1)
assert_equals "acc/explicit-account" "$(lastlog)" "cfg=<unset> args=-p hi"
(cd "$HOME/other" && "$CCV" launch --account=1 >/dev/null 2>&1)
assert_equals "acc/explicit-by-number" "$(lastlog)" "cfg=<unset> args="
(cd "$HOME/other" && CCV_ACCOUNT=default "$CCV" launch >/dev/null 2>&1)
assert_equals "acc/terminal-pin" "$(lastlog)" "cfg=<unset> args="

# MCP union (primary wins), folder trust carried over, new entries linked.
jq '.mcpServers.b = {"type":"http","url":"https://b"} | .mcpServers.shared.url = "https://mine"' \
  "$A/.claude.json" > "$A/x" && mv "$A/x" "$A/.claude.json"
mkdir -p "$P/commands"
(cd "$HOME/other" && "$CCV" launch >/dev/null 2>&1)
assert_equals "acc/mcp-union-primary" "$(jq -r '.mcpServers | keys | join(",")' "$HOME/.claude.json")" "a,b,shared"
assert_equals "acc/mcp-union-account" "$(jq -r '.mcpServers | keys | join(",")' "$A/.claude.json")" "a,b,shared"
assert_equals "acc/mcp-primary-wins" "$(jq -r '.mcpServers.shared.url' "$A/.claude.json")" "https://primary"
assert_equals "acc/trust-carried" "$(jq -r --arg k "$HOME/other" '.projects[$k].hasTrustDialogAccepted' "$A/.claude.json")" "true"
if [ -L "$A/commands" ]; then ok "acc/new-entry-linked"; else bad "acc/new-entry-linked" "commands not linked"; fi
assert_equals "acc/primary-login-kept" "$(jq -r '.oauthAccount.organizationType' "$HOME/.claude.json")" "claude_enterprise"

# Heal: Claude Code replaced shared files with copies (write-then-rename).
rm -f "$A/settings.json"; cp "$P/settings.json" "$A/settings.json"
printf 'old shared\n' > "$P/CLAUDE.md"; touch -t 202601010000 "$P/CLAUDE.md"
rm -f "$A/CLAUDE.md"; printf 'newer in account\n' > "$A/CLAUDE.md"
(cd "$HOME/other" && "$CCV" launch >/dev/null 2>&1)
if [ -L "$A/settings.json" ]; then ok "acc/heal-identical-relinked"; else bad "acc/heal-identical-relinked" "still a file"; fi
if [ -L "$A/CLAUDE.md" ]; then ok "acc/heal-newer-relinked"; else bad "acc/heal-newer-relinked" "still a file"; fi
assert_equals "acc/heal-newer-wins" "$(cat "$P/CLAUDE.md")" "newer in account"
assert_contains "acc/heal-backup-kept" "$(cat "${XDG_STATE_HOME:-$HOME/.local/state}"/cc-vitamins/healed/*/CLAUDE.md.shared 2>/dev/null)" "old shared"

# Auth override warning names the variable, never its value.
out=$(cd "$HOME/other" && ANTHROPIC_API_KEY=sk-test-value "$CCV" launch 2>&1 >/dev/null)
assert_contains "acc/override-warns" "$out" "ANTHROPIC_API_KEY is set"
case "$out" in *sk-test-value*) bad "acc/override-no-value" "value leaked" ;; *) ok "acc/override-no-value" ;; esac

# Switch inside a session: stop, resume the same ID under the other account,
# keep safe flags, drop the prompt.
: > "$FAKE_CLAUDE_LOG"; rm -f "$FAKE_CLAUDE_LOG.switched"
(cd "$HOME/work/repo" && FAKE_SWITCH_TO=personal "$CCV" launch --model opus "fix the bug" >/dev/null 2>&1)
rc=$?
assert_equals "acc/switch-exit" "$rc" "0"
assert_equals "acc/switch-first" "$(sed -n 1p "$FAKE_CLAUDE_LOG")" "cfg=<unset> args=--model opus fix the bug"
assert_contains "acc/switch-message" "$(cat "$FAKE_CLAUDE_LOG")" "Switching default -> personal"
assert_equals "acc/switch-resumed" "$(lastlog)" "cfg=$A args=--resume 11111111-2222-3333-4444-555555555555 --model opus"
if [ -n "$(ls -A "${XDG_STATE_HOME:-$HOME/.local/state}/cc-vitamins/switch" 2>/dev/null)" ]; then
  bad "acc/switch-request-cleaned" "request file left behind"
else ok "acc/switch-request-cleaned"; fi

# use: refusals. No transcript on disk → Claude is NOT stopped.
out=$(CLAUDECODE=1 CCV_RUN=tok CLAUDE_CODE_SESSION_ID=22222222-2222-2222-2222-222222222222 \
  sh -c 'CLAUDE_PID=$$ "$0" use personal; echo alive' "$CCV" 2>&1)
assert_contains "acc/use-no-transcript" "$out" "no saved transcript"
assert_contains "acc/use-no-transcript-not-stopped" "$out" "alive"

out=$(CLAUDECODE=1 CLAUDE_CONFIG_DIR="$A" "$CCV" use personal 2>&1)
assert_contains "acc/use-already" "$out" "Already on 'personal'"
out=$(CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=11111111-2222-3333-4444-555555555555 CLAUDE_PID=1 "$CCV" use personal 2>&1)
assert_contains "acc/use-without-wrapper" "$out" "claude --account personal --resume 11111111-2222-3333-4444-555555555555"
out=$(CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=11111111-2222-3333-4444-555555555555 CLAUDE_PID=1 CCV_RUN=abc "$CCV" use personal 2>&1)
assert_contains "acc/use-foreign-pid" "$out" "refusing"
mkdir -p "$HOME/.claude-nologin" && : > "$HOME/.claude-nologin/.ccv-account"
printf 'account nologin ~/.claude-nologin\n' >> "$cfg"
out=$(CLAUDECODE=1 "$CCV" use nologin 2>&1)
assert_contains "acc/use-not-logged-in" "$out" "not logged in"
out=$("$CCV" use 2 2>&1)
assert_contains "acc/use-terminal-hint" "$out" "claude --account personal"

# Status line segment follows the process's CLAUDE_CONFIG_DIR.
out=$(CLAUDE_CONFIG_DIR="$A" "$BIN" < "$FIX/basic.json" | sed -n 1p)
assert_contains "acc/segment-extra" "$out" "● personal Pro myproject"
out=$("$BIN" < "$FIX/basic.json" | sed -n 1p)
assert_contains "acc/segment-primary" "$out" "● default Enterprise myproject"
case "$out" in *@*|*fake-uuid*) bad "acc/segment-private" "$out" ;; *) ok "acc/segment-private" ;; esac

# rename, doctor, remove.
"$CCV" rename default work >/dev/null
assert_contains "acc/rename-account" "$(cat "$cfg")" "account work ~/.claude blue"
assert_contains "acc/rename-route" "$(cat "$cfg")" "route ~/work work"
"$CCV" remove nologin --yes >/dev/null 2>&1
out=$("$CCV" doctor 2>&1); rc=$?
assert_equals "acc/doctor-ok" "$rc" "0"
"$CCV" route --remove "$HOME/work" >/dev/null
case "$(cat "$cfg")" in *"route ~/work"*) bad "acc/route-removed" "route still present" ;; *) ok "acc/route-removed" ;; esac
"$CCV" remove personal --yes >/dev/null 2>&1
if [ -d "$A" ]; then bad "acc/remove-dir" "$A still exists"; else ok "acc/remove-dir"; fi
if [ -d "$P/skills/demo" ] && [ -f "$P/settings.json" ]; then ok "acc/remove-keeps-shared"
else bad "acc/remove-keeps-shared" "shared content lost"; fi
assert_contains "acc/remove-logout" "$(cat "$FAKE_CLAUDE_LOG")" "cfg=$A args=auth logout"
case "$(cat "$cfg")" in *personal*) bad "acc/remove-config" "personal still in config" ;; *) ok "acc/remove-config" ;; esac
out=$("$BIN" < "$FIX/basic.json" | sed -n 1p)
case "$out" in *●*) bad "acc/segment-single-hidden" "$out" ;; *) ok "acc/segment-single-hidden" ;; esac

# shell-init defines both functions and quotes the path.
out=$("$CCV" shell-init)
# shellcheck disable=SC2016 # literal text expected in the output
assert_contains "acc/shell-init-claude" "$out" 'claude() { command "$CCV_BIN" launch "$@"; }'
assert_contains "acc/shell-init-bin" "$out" "CCV_BIN='$ROOT_DIR/bin/ccv'"

# ── Case: install from an extra account whose files link to the primary ──
X="$TMPROOT/xacct"; XP="$TMPROOT/xprimary"
mkdir -p "$X" "$XP"
CLAUDE_CONFIG_DIR="$XP" sh "$ROOT_DIR/install.sh" --force >/dev/null 2>&1
ln -s "$XP/settings.json" "$X/settings.json"; ln -s "$XP/cc-vitamins" "$X/cc-vitamins"
out=$(CLAUDE_CONFIG_DIR="$X" sh "$ROOT_DIR/install.sh" < /dev/null 2>&1)
case "$out" in *"A different statusLine"*) bad "install/linked-account-no-prompt" "$out" ;; *) ok "install/linked-account-no-prompt" ;; esac
if [ -L "$X/settings.json" ]; then ok "install/linked-account-keeps-link"
else bad "install/linked-account-keeps-link" "settings.json link was replaced by a file"; fi
assert_equals "install/linked-account-keeps-path" "$(jq -r .statusLine.command "$XP/settings.json")" "$XP/cc-vitamins/bin/cc-vitamins"

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
