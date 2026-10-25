#!/bin/sh
# cc-vitamins installer.
#
#   Local checkout:  ./install.sh
#   One-liner:       curl -fsSL https://raw.githubusercontent.com/andriitk/cc-vitamins/main/install.sh | sh
#
# It copies cc-vitamins into your Claude Code config directory and wires up the
# `statusLine` setting in settings.json, preserving every other key and backing
# up the previous file. Safe by default: it never clobbers a different existing
# statusLine without your confirmation (or --force).
#
# Flags:
#   --dry-run     Show what would happen; change nothing.
#   --uninstall   Restore the statusLine that was present before install
#                 (or remove the key) and delete the installed files.
#   --force       Overwrite an existing, different statusLine without asking.
#   --help        Show this help.

set -eu

REPO_URL="https://github.com/andriitk/cc-vitamins.git"
REPO_BRANCH="main"

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CONFIG_DIR/cc-vitamins"
SETTINGS="$CONFIG_DIR/settings.json"
STATUSLINE_CMD="$DEST/bin/cc-vitamins"
BACKUP_MARKER="$DEST/.statusline-backup.json"

DRY_RUN=0
FORCE=0
ACTION="install"

log()  { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf 'cc-vitamins: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = "1" ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --uninstall) ACTION="uninstall" ;;
    --force)     FORCE=1 ;;
    --help|-h)   usage ;;
    *)           die "unknown option: $arg (try --help)" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is required. Install it from https://jqlang.github.io/jq/"

# atomic_write_settings <jq-filter> [args...] — update $SETTINGS in place.
atomic_write_settings() {
  _filter=$1; shift
  _src="$SETTINGS"
  [ -f "$_src" ] || _src=/dev/null
  _tmp=$(mktemp "${TMPDIR:-/tmp}/cc-vitamins.XXXXXX") || die "mktemp failed"
  if [ "$_src" = /dev/null ]; then
    printf '{}' | jq "$@" "$_filter" > "$_tmp" || { rm -f "$_tmp"; die "jq failed"; }
  else
    jq "$@" "$_filter" "$_src" > "$_tmp" || { rm -f "$_tmp"; die "jq failed"; }
  fi
  mv "$_tmp" "$SETTINGS"
}

backup_settings() {
  [ -f "$SETTINGS" ] || return 0
  _ts=$(date +%Y%m%d-%H%M%S)
  _bak="$SETTINGS.bak.$_ts"
  run "cp '$SETTINGS' '$_bak'"
  info "Backed up settings.json -> $(basename "$_bak")"
}

do_uninstall() {
  log "Uninstalling cc-vitamins..."
  if [ -f "$SETTINGS" ]; then
    backup_settings
    _current=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)
    if [ "$_current" = "$STATUSLINE_CMD" ]; then
      if [ -f "$BACKUP_MARKER" ] && [ "$(jq -r 'has("statusLine")' "$BACKUP_MARKER" 2>/dev/null)" = "true" ]; then
        _prev=$(jq -c '.statusLine' "$BACKUP_MARKER")
        if [ "$DRY_RUN" = "1" ]; then info "[dry-run] restore statusLine: $_prev"
        else atomic_write_settings '.statusLine = $prev' --argjson prev "$_prev"; fi
        info "Restored the previous statusLine."
      else
        if [ "$DRY_RUN" = "1" ]; then info "[dry-run] remove the statusLine key"
        else atomic_write_settings 'del(.statusLine)'; fi
        info "Removed the statusLine key."
      fi
    else
      info "statusLine is not cc-vitamins; leaving settings.json untouched."
    fi
  fi
  run "rm -rf '$DEST'"
  info "Removed $DEST"
  log "Done."
  exit 0
}

[ "$ACTION" = "uninstall" ] && do_uninstall

# ── Locate source files (local checkout or fetch for curl | sh) ──────────────
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || echo "")
CLEANUP_SRC=""
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/bin/cc-vitamins" ]; then
  SRC="$SELF_DIR"
else
  log "Fetching cc-vitamins..."
  command -v git >/dev/null 2>&1 || die "git is required to bootstrap via curl | sh"
  SRC=$(mktemp -d "${TMPDIR:-/tmp}/cc-vitamins-src.XXXXXX") || die "mktemp failed"
  CLEANUP_SRC="$SRC"
  git clone --quiet --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$SRC" \
    || die "git clone failed from $REPO_URL"
fi
cleanup() { [ -n "$CLEANUP_SRC" ] && rm -rf "$CLEANUP_SRC"; }
trap cleanup EXIT

# ── Dependency notes ─────────────────────────────────────────────────────────
log "cc-vitamins installer"
info "jq: found"
if command -v ccusage >/dev/null 2>&1; then
  info "ccusage: found (today's cross-session cost enabled)"
else
  info "ccusage: not found — the optional 'today \$' segment stays hidden."
  info "  Enable it with 'npm i -g ccusage', or CC_VITAMINS_CCUSAGE=npx in the config."
fi

# ── Copy files ───────────────────────────────────────────────────────────────
log "Installing to $DEST"
run "mkdir -p '$DEST'"
run "cp -R '$SRC/bin' '$DEST/'"
run "cp -R '$SRC/lib' '$DEST/'"
run "cp '$SRC/config.example' '$DEST/config.example'"
[ -f "$SRC/README.md" ] && run "cp '$SRC/README.md' '$DEST/README.md'"
run "chmod +x '$DEST/bin/cc-vitamins'"

# ── Wire up statusLine ───────────────────────────────────────────────────────
run "mkdir -p '$CONFIG_DIR'"
EXISTING=""
if [ -f "$SETTINGS" ]; then
  EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)
fi

if [ -n "$EXISTING" ] && [ "$EXISTING" != "$STATUSLINE_CMD" ]; then
  log ""
  log "A different statusLine is already configured:"
  info "$EXISTING"
  if [ "$FORCE" != "1" ]; then
    _ok=0
    if [ -r /dev/tty ]; then
      printf '  Replace it with cc-vitamins? [y/N] '
      read -r _ans < /dev/tty 2>/dev/null || _ans=""
      case "$_ans" in y|Y|yes|YES) _ok=1 ;; esac
    fi
    if [ "$_ok" != "1" ]; then
      log "Leaving the existing statusLine in place. Re-run with --force to replace it."
      log "Files are installed at $DEST; you can set the command manually."
      exit 0
    fi
  fi
fi

# Record the pre-install statusLine so --uninstall can restore it. A re-install
# (statusLine already ours) keeps the original record instead of overwriting it
# with cc-vitamins itself.
if [ "$DRY_RUN" != "1" ] && { [ "$EXISTING" != "$STATUSLINE_CMD" ] || [ ! -f "$BACKUP_MARKER" ]; }; then
  mkdir -p "$DEST"
  if [ -f "$SETTINGS" ]; then
    jq '{statusLine} | if .statusLine == null then {} else . end' "$SETTINGS" > "$BACKUP_MARKER" 2>/dev/null \
      || printf '{}' > "$BACKUP_MARKER"
  else
    printf '{}' > "$BACKUP_MARKER"
  fi
fi

backup_settings
# refreshInterval keeps the countdowns (cache expiry, 5h/7d reset) current
# while the session is idle.
if [ "$DRY_RUN" = "1" ]; then
  info "[dry-run] set statusLine.command = $STATUSLINE_CMD"
else
  atomic_write_settings '.statusLine = {type: "command", command: $cmd, padding: 0, refreshInterval: 60}' \
    --arg cmd "$STATUSLINE_CMD"
fi

log ""
log "Installed. statusLine set to:"
info "$STATUSLINE_CMD"
log "Open a new Claude Code session (or wait for the next render) to see it."
[ "$DRY_RUN" = "1" ] && log "(dry-run: nothing was actually changed)"
