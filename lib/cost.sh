# shellcheck shell=sh
# cc-vitamins — stateful cost/usage helpers backed by small cache files.

# ctx_delta <cache_dir> <session_id> <ctx_tokens>  ->  signed token delta, or empty
# Remembers "<current> <previous>" per session. The pair only shifts when the
# value actually changes, so repeated renders within one turn keep one delta.
ctx_delta() {
  [ -n "$2" ] || return 0
  _state="$1/ctx-$2"
  _cur=""; _prev=""
  [ -f "$_state" ] && read -r _cur _prev < "$_state"
  if [ "$_cur" != "$3" ]; then
    _prev="$_cur"; _cur="$3"
    printf '%s %s\n' "$_cur" "$_prev" > "$_state" 2>/dev/null || :
  fi
  [ -n "$_prev" ] || return 0
  printf '%s' $(( _cur - _prev ))
}

# session_today_cost <cache_dir> <session_id> <session_cost> <transcript_path>
#   ->  dollars spent by THIS session today
# Claude Code only reports the cumulative session total, so we remember what it
# was the first time we rendered today and subtract that baseline. A session
# that actually started today has a baseline of 0. If the counter ever drops
# below the baseline (a reset) we fall back to the raw total.
session_today_cost() {
  _cd="$1"; _sid="$2"; _cost="$3"; _tp="$4"
  if [ -z "$_sid" ]; then printf '%s' "$_cost"; return 0; fi
  _today=$(date +%Y%m%d)
  _state="$_cd/day-$_sid"
  _bdate=""; _bcost=""
  [ -f "$_state" ] && read -r _bdate _bcost < "$_state"
  if [ "$_bdate" != "$_today" ]; then
    _bdate="$_today"; _bcost="$_cost"
    if [ -n "$_tp" ] && [ -f "$_tp" ]; then
      _first_ts=$(head -n 20 "$_tp" | jq -r 'select(.timestamp) | .timestamp' 2>/dev/null | head -n 1)
      if [ -n "$_first_ts" ]; then
        _first_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${_first_ts%%.*}" +%s 2>/dev/null \
          || date -d "$_first_ts" +%s 2>/dev/null)
        if [ -n "$_first_epoch" ]; then
          _first_day=$(date -r "$_first_epoch" +%Y%m%d 2>/dev/null \
            || date -d "@$_first_epoch" +%Y%m%d 2>/dev/null)
          [ "$_first_day" = "$_today" ] && _bcost=0
        fi
      fi
    fi
    printf '%s %s\n' "$_bdate" "$_bcost" > "$_state" 2>/dev/null || :
  fi
  awk -v c="$_cost" -v b="${_bcost:-0}" 'BEGIN { d = c - b; if (d < 0) d = c; printf "%.4f", d }'
}

# ccusage_today <cache_dir> <ttl> <cmd>  ->  today's cost across all sessions, or empty
# Stale-while-revalidate: returns the cached value immediately and kicks off a
# background refresh when the cache is older than <ttl> seconds. A lock file
# prevents concurrent refreshes; a stale lock is reaped after 5 minutes.
ccusage_today() {
  _cd="$1"; _ttl="$2"; _cmd="$3"
  _cache="$_cd/ccusage.json"
  _lock="$_cd/ccusage.lock"

  [ -f "$_lock" ] && [ "$(file_age "$_lock")" -gt 300 ] && rm -f "$_lock"

  _refresh=1
  [ -f "$_cache" ] && [ "$(file_age "$_cache")" -lt "$_ttl" ] && _refresh=0

  if [ "$_refresh" = "1" ] && [ ! -f "$_lock" ]; then
    (
      touch "$_lock"
      trap 'rm -f "$_lock"' EXIT
      _day=$(date +%Y%m%d)
      _tc=$($_cmd daily --since "$_day" --json 2>/dev/null | jq -r '.totals.totalCost // empty')
      [ -n "$_tc" ] && printf '{"date":"%s","today_cost":"%s"}\n' "$_day" "$_tc" > "$_cache"
    ) </dev/null >/dev/null 2>&1 &
  fi

  [ -f "$_cache" ] || return 0
  _cdate=$(jq -r '.date // empty' < "$_cache" 2>/dev/null)
  _tc=$(jq -r '.today_cost // empty' < "$_cache" 2>/dev/null)
  # Ignore a cache written before midnight.
  if [ -n "$_tc" ] && [ "$_cdate" = "$(date +%Y%m%d)" ]; then
    printf '%s' "$_tc"
  fi
}
