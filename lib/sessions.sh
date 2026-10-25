# shellcheck shell=sh
# cc-vitamins — active-session counting.
#
# Each render drops a heartbeat file at $SESS_DIR/<session_id> containing the
# PID of the long-lived Claude Code process that owns this status line. To count
# how many Claude Code sessions are currently open we list the heartbeat files
# and keep only those whose PID is still alive (kill -0), deleting the rest.
#
# Which PID?
#   Claude Code runs the status line command. Depending on how it is spawned,
#   $PPID is either the Claude Code process itself (when the command is exec'd
#   directly, e.g. `sh -c 'cc-vitamins'` where the shell execs the only command)
#   or a short-lived shell wrapper whose own parent is Claude Code. A short-lived
#   wrapper would die right after rendering and make the heartbeat look dead on
#   the next poll, so when $PPID is a shell we walk one level up to its parent.
#   That parent (the node process running Claude Code) persists for the whole
#   session, which is exactly the lifetime we want to track.

# resolve_owner_pid  ->  PID of the persistent Claude Code process
resolve_owner_pid() {
  _pid=$PPID
  _comm=$(ps -o comm= -p "$_pid" 2>/dev/null | sed 's#.*/##')
  case "$_comm" in
    sh|bash|dash|zsh|ksh|-sh|-bash|-zsh|-ksh)
      _up=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
      case "$_up" in
        '' | *[!0-9]* ) : ;;   # not a clean number: keep $PPID
        * ) [ "$_up" -gt 1 ] && _pid=$_up ;;
      esac
      ;;
  esac
  printf '%s' "$_pid"
}

# write_heartbeat <sessions_dir> <session_id>
write_heartbeat() {
  [ -n "$2" ] || return 0
  mkdir -p "$1" 2>/dev/null || return 0
  resolve_owner_pid > "$1/$2" 2>/dev/null || :
}

# count_live_sessions <sessions_dir>  ->  number of heartbeats with a live PID
# Dead heartbeats are removed as a side effect.
count_live_sessions() {
  [ -d "$1" ] || { printf '0'; return 0; }
  _count=0
  for _f in "$1"/*; do
    [ -f "$_f" ] || continue
    _p=$(cat "$_f" 2>/dev/null)
    case "$_p" in
      '' | *[!0-9]* ) rm -f "$_f" 2>/dev/null; continue ;;
    esac
    if kill -0 "$_p" 2>/dev/null; then
      _count=$(( _count + 1 ))
    else
      rm -f "$_f" 2>/dev/null
    fi
  done
  printf '%s' "$_count"
}
