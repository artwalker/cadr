#!/usr/bin/env bash
# Serialize edits to the shared Goal 20 harness on the main worktree.
#
# Pairing agents in isolated worktrees do NOT need this lock. Only the director
# (or any agent editing cadr-migration harness in-place) acquires it.
#
# usage:
#   scripts/goal20-team-lock.sh acquire <role>   # pairing|director|optimization|testing
#   scripts/goal20-team-lock.sh release
#   scripts/goal20-team-lock.sh status
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOCK_FILE="$PROJECT_DIRECTORY/scripts/.goal20-harness.lock"
LOCK_FD=9

_acquire() {
	local role="${1:-unknown}"
	exec 9>"$LOCK_FILE"
	if ! flock -n 9; then
		echo "goal20 harness lock: busy ($(cat "$LOCK_FILE" 2>/dev/null || echo unknown))" >&2
		exit 1
	fi
	printf '%s %s %s\n' "$role" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >&9
	echo "goal20 harness lock: acquired role=$role pid=$$"
}

_release() {
	if [ ! -f "$LOCK_FILE" ]; then
		echo "goal20 harness lock: not held"
		return 0
	fi
	exec 9>"$LOCK_FILE"
	if flock -n 9; then
		: >"$LOCK_FILE"
		echo "goal20 harness lock: released (was empty or stale)"
		return 0
	fi
	local holder
	holder="$(sed -n '1p' "$LOCK_FILE" 2>/dev/null || true)"
	local holder_pid
	holder_pid="$(printf '%s' "$holder" | awk '{print $2}')"
	if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
		echo "goal20 harness lock: held by $holder" >&2
		exit 1
	fi
	: >"$LOCK_FILE"
	echo "goal20 harness lock: released stale lock ($holder)"
}

_status() {
	if [ ! -f "$LOCK_FILE" ] || [ ! -s "$LOCK_FILE" ]; then
		echo "goal20 harness lock: free"
		return 0
	fi
	local holder
	holder="$(sed -n '1p' "$LOCK_FILE")"
	local holder_pid
	holder_pid="$(printf '%s' "$holder" | awk '{print $2}')"
	if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
		echo "goal20 harness lock: busy $holder"
	else
		echo "goal20 harness lock: stale $holder"
	fi
}

case "${1:-status}" in
acquire) _acquire "${2:-unknown}" ;;
release) _release ;;
status) _status ;;
*)
	echo "usage: $0 acquire|release|status [role]" >&2
	exit 2
	;;
esac
