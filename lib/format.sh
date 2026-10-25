# shellcheck shell=sh
# cc-vitamins — formatting helpers and colors.
# This file is sourced; it defines functions and color variables only.

# init_colors — define color escapes, honoring NO_COLOR.
# When NO_COLOR is set (to anything, per https://no-color.org) every color
# variable becomes empty, so the rendered output is plain text.
# The colors are used by the sourcing script, not here (SC2034).
# shellcheck disable=SC2034
init_colors() {
  if [ -n "${NO_COLOR:-}" ]; then
    RESET=""; BOLD=""; DIM=""
    CYAN=""; BLUE=""; GREEN=""; YELLOW=""
    RED=""; ORANGE=""; MAGENTA=""; WHITE=""
  else
    RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
    CYAN="\033[0;36m"; BLUE="\033[1;34m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"
    RED="\033[0;31m"; ORANGE="\033[38;5;208m"; MAGENTA="\033[1;35m"; WHITE="\033[0;37m"
  fi
  SEP=" ${DIM}·${RESET} "
}

# make_bar <pct_int> <width>  ->  █████░░░░░
make_bar() {
  _filled=$(( $1 * $2 / 100 ))
  [ "$_filled" -gt "$2" ] && _filled=$2
  [ "$_filled" -lt 0 ] && _filled=0
  _bar=""; _i=0
  while [ "$_i" -lt "$_filled" ]; do _bar="${_bar}█"; _i=$(( _i + 1 )); done
  while [ "$_i" -lt "$2" ]; do _bar="${_bar}░"; _i=$(( _i + 1 )); done
  printf '%s' "$_bar"
}

# pct_color <pct_int>  ->  green/yellow/red by CC_VITAMINS_PCT_* thresholds
pct_color() {
  if [ "$1" -ge "${CC_VITAMINS_PCT_RED:-80}" ]; then printf '%s' "$RED"
  elif [ "$1" -ge "${CC_VITAMINS_PCT_YELLOW:-50}" ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# ctx_color <tokens> <window> <pct_int>
# Big windows (> CC_VITAMINS_BIGWIN_THRESHOLD) use absolute token thresholds,
# since a small percentage of a 1M window is already a lot of tokens; smaller
# windows use percentages. green -> yellow -> orange -> red.
ctx_color() {
  if [ "$2" -gt "${CC_VITAMINS_BIGWIN_THRESHOLD:-200000}" ]; then
    if [ "$1" -ge "${CC_VITAMINS_CTX_TOK_RED:-500000}" ]; then printf '%s' "$RED"
    elif [ "$1" -ge "${CC_VITAMINS_CTX_TOK_ORANGE:-250000}" ]; then printf '%s' "$ORANGE"
    elif [ "$1" -ge "${CC_VITAMINS_CTX_TOK_YELLOW:-100000}" ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"; fi
  else
    if [ "$3" -ge "${CC_VITAMINS_CTX_PCT_RED:-85}" ]; then printf '%s' "$RED"
    elif [ "$3" -ge "${CC_VITAMINS_CTX_PCT_ORANGE:-70}" ]; then printf '%s' "$ORANGE"
    elif [ "$3" -ge "${CC_VITAMINS_CTX_PCT_YELLOW:-50}" ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"; fi
  fi
}

# today_color <usd>  ->  green/yellow/red by today-$ thresholds
today_color() {
  awk -v c="$1" -v y="${CC_VITAMINS_TODAY_YELLOW:-10}" -v rr="${CC_VITAMINS_TODAY_RED:-25}" \
      -v g="$GREEN" -v yc="$YELLOW" -v rc="$RED" \
      'BEGIN { print (c >= rr ? rc : c >= y ? yc : g) }'
}

# human_tokens <n>  ->  950 / 68.2k / 1.2M
human_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) { s = sprintf("%.1f", n / 1000000); u = "M" }
    else if (n >= 1000) { s = sprintf("%.1f", n / 1000); u = "k" }
    else { printf "%d", n; exit }
    sub(/\.0$/, "", s); printf "%s%s", s, u
  }'
}

# format_duration <ms>  ->  45s / 23m45s / 1h23m
format_duration() {
  _secs=$(( $1 / 1000 ))
  if [ "$_secs" -ge 3600 ]; then printf '%dh%02dm' $(( _secs / 3600 )) $(( (_secs % 3600) / 60 ))
  elif [ "$_secs" -ge 60 ]; then printf '%dm%02ds' $(( _secs / 60 )) $(( _secs % 60 ))
  else printf '%ds' "$_secs"; fi
}

# fit_width <line> <cols>  ->  <line>, with "\n" inserted between segments so
# that no row is wider than <cols> visible characters. Segments are joined by
# the " · " separator; ANSI codes are still literal "\033[...m" text here and
# do not count toward the width, and neither do UTF-8 continuation bytes.
fit_width() {
  case "$2" in '' | *[!0-9]* | 0 ) printf '%s' "$1"; return 0 ;; esac
  # SEP goes through the environment: awk -v would turn the literal "\033"
  # into a real ESC byte and the separator would no longer match.
  _fw=$(printf '%s' "$1" | CC_VITAMINS_SEP="$SEP" awk -v cols="$2" '
    function vis(s) { gsub(/\\033\[[0-9;]*m/, "", s); gsub(/[\200-\277]/, "", s); return length(s) }
    {
      sep = ENVIRON["CC_VITAMINS_SEP"]; rest = $0; n = 0
      while ((i = index(rest, sep)) > 0) { parts[++n] = substr(rest, 1, i - 1); rest = substr(rest, i + length(sep)) }
      parts[++n] = rest
      sw = vis(sep); out = parts[1]; w = vis(parts[1])
      for (k = 2; k <= n; k++) {
        pw = vis(parts[k])
        if (w + sw + pw > cols) { out = out "\\n" parts[k]; w = pw }
        else { out = out sep parts[k]; w += sw + pw }
      }
      printf "%s", out
    }' 2>/dev/null)
  # Never lose the line: fall back to the unwrapped text if awk failed.
  printf '%s' "${_fw:-$1}"
}

# file_age <path>  ->  seconds since the file was last modified (BSD and GNU stat)
file_age() {
  _now=$(date +%s)
  _mtime=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo "$_now")
  echo $(( _now - _mtime ))
}
