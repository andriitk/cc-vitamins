# shellcheck shell=sh
# cc-vitamins — accounts: config parsing and account resolution.
# This file is sourced by bin/ccv and bin/cc-vitamins; it defines functions only.
#
# Config file: ${XDG_CONFIG_HOME:-~/.config}/cc-vitamins/accounts
#
#   account <name> <config-dir> [color]   first line = primary account
#   route   <folder> <name>               folder and everything below it
#   default <name>                        every other folder
#
# Names are [A-Za-z0-9_-]. Config dirs may not contain spaces; route folders may.
# See docs/ACCOUNTS.md.

ACCOUNTS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cc-vitamins/accounts"

# acc_expand <path>  ->  path with a leading ~ replaced by $HOME
acc_expand() {
  # shellcheck disable=SC2088 # matching a literal "~/" prefix
  case "$1" in
    "~")   printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *)     printf '%s' "$1" ;;
  esac
}

# acc_real <path>  ->  physical absolute path (symlinks resolved) if it exists,
# otherwise the expanded path unchanged.
acc_real() {
  _ar=$(acc_expand "$1")
  if [ -d "$_ar" ]; then (CDPATH='' cd -P -- "$_ar" 2>/dev/null && pwd -P) || printf '%s' "$_ar"
  else printf '%s' "$_ar"; fi
}

# acc_valid_name <name>  ->  status 0 if usable as an account name
acc_valid_name() {
  case "$1" in '' | *[!A-Za-z0-9_-]* ) return 1 ;; esac
  return 0
}

# acc_enabled  ->  status 0 when the config defines at least one account
acc_enabled() {
  [ -f "$ACCOUNTS_FILE" ] && [ -n "$(acc_names)" ]
}

# acc_lines <kind>  ->  config lines of that kind, comments and blanks removed
acc_lines() {
  [ -f "$ACCOUNTS_FILE" ] || return 0
  awk -v k="$1" '{ sub(/#.*/, "") } $1 == k { print }' "$ACCOUNTS_FILE"
}

# acc_names  ->  account names, one per line, primary first
acc_names() { acc_lines account | awk '{ print $2 }'; }

acc_primary() { acc_names | sed -n 1p; }
acc_count()   { acc_names | grep -c . ; }

# acc_field <name> <n>  ->  field n of that account's line (3 = dir, 4 = color)
acc_field() { acc_lines account | awk -v n="$1" -v f="$2" '$2 == n { print $f; exit }'; }

acc_exists() { [ -n "$1" ] && [ -n "$(acc_field "$1" 2)" ]; }
acc_dir()    { acc_expand "$(acc_field "$1" 3)"; }
acc_color()  { acc_field "$1" 4; }

# acc_by_index <n>  ->  name of the n-th account (1-based)
acc_by_index() { acc_names | sed -n "${1}p"; }

# acc_resolve <name|number>  ->  account name, or status 1
acc_resolve() {
  case "$1" in
    '' ) return 1 ;;
    *[!0-9]* ) acc_exists "$1" && { printf '%s' "$1"; return 0; } ;;
    * ) _n=$(acc_by_index "$1"); [ -n "$_n" ] && { printf '%s' "$_n"; return 0; } ;;
  esac
  return 1
}

# acc_default  ->  the `default` account, else the primary
acc_default() {
  _d=$(acc_lines default | awk '{ print $2; exit }')
  if acc_exists "$_d"; then printf '%s' "$_d"; else acc_primary; fi
}

# acc_is_home_default <dir>  ->  status 0 when dir is Claude Code's built-in
# default (~/.claude). For it CLAUDE_CONFIG_DIR must stay UNSET: setting it
# explicitly moves .claude.json and the Keychain entry and logs the user out.
acc_is_home_default() {
  [ "$(acc_real "$1")" = "$(acc_real "$HOME/.claude")" ]
}

# acc_config_env <name>  ->  value for CLAUDE_CONFIG_DIR, empty = leave unset
acc_config_env() {
  _ad=$(acc_dir "$1")
  if acc_is_home_default "$_ad"; then printf ''; else printf '%s' "$_ad"; fi
}

# acc_json <name>  ->  path of that account's .claude.json
acc_json() {
  _ad=$(acc_dir "$1")
  if acc_is_home_default "$_ad"; then printf '%s/.claude.json' "$HOME"
  else printf '%s/.claude.json' "$_ad"; fi
}

# acc_current  ->  account of the running Claude Code process, judged by the
# CLAUDE_CONFIG_DIR it was started with (unset = ~/.claude). Empty if unknown.
acc_current() {
  _want=$(acc_real "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
  for _n in $(acc_names); do
    if [ "$(acc_real "$(acc_dir "$_n")")" = "$_want" ]; then printf '%s' "$_n"; return 0; fi
  done
  return 0
}

# acc_for_path <folder>  ->  account routed for that folder (longest match),
# else the default account
acc_for_path() {
  _p=$(acc_real "$1")
  _best=""; _bestlen=0
  # Route lines: "route <folder, may contain spaces> <name>".
  _routes=$(acc_lines route | awk '{ n = $NF; $1 = ""; $NF = ""; sub(/^ +/, ""); sub(/ +$/, ""); print n "\t" $0 }')
  _tab=$(printf '\t')
  while IFS="$_tab" read -r _name _folder; do
    [ -n "$_folder" ] || continue
    acc_exists "$_name" || continue
    _f=$(acc_real "$_folder")
    case "$_p/" in
      "$_f"/*)
        if [ "${#_f}" -gt "$_bestlen" ]; then _best=$_name; _bestlen=${#_f}; fi ;;
    esac
  done <<EOF
$_routes
EOF
  if [ -n "$_best" ]; then printf '%s' "$_best"; else acc_default; fi
}

# acc_plan <name>  ->  Pro / Max / Team / Enterprise, or empty when unknown.
# Reads only the organization type; never the email, names or IDs.
acc_plan() {
  _j=$(acc_json "$1")
  [ -f "$_j" ] || return 0
  _t=$(jq -r '.oauthAccount.organizationType // empty' "$_j" 2>/dev/null)
  case "$_t" in
    *enterprise*) printf 'Enterprise' ;;
    *team*)       printf 'Team' ;;
    *max*)        printf 'Max' ;;
    *pro*)        printf 'Pro' ;;
    *ultra*)      printf 'Ultra' ;;
    *)            : ;;
  esac
}

# acc_logged_in <name>  ->  status 0 when that account has a claude.ai login
acc_logged_in() {
  _j=$(acc_json "$1")
  [ -f "$_j" ] && [ "$(jq -r '.oauthAccount.accountUuid // empty' "$_j" 2>/dev/null)" != "" ]
}
