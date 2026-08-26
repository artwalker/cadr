#!/usr/bin/env bash
# Save or restore render-diff capture cache keyed by BASELINE commit.
#
# usage:
#   scripts/goal21-render-diff-capture-cache.sh save
#   scripts/goal21-render-diff-capture-cache.sh restore
#   scripts/goal21-render-diff-capture-cache.sh status
#
# Cache root: .cache/render-diff-captures/<baseline-short>/
# Restore target: GOAL21_RENDER_DIFF_OUTPUT or /tmp/goal21-render-diff-output
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BASELINE_COMMIT="$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE")"
CACHE_KEY="${BASELINE_COMMIT:0:9}"
CACHE_ROOT="${GOAL21_RENDER_DIFF_CACHE_ROOT:-$PROJECT_DIRECTORY/.cache/render-diff-captures}"
CACHE_DIR="$CACHE_ROOT/$CACHE_KEY"
SOURCE="${GOAL21_RENDER_DIFF_OUTPUT:-/tmp/goal21-render-diff-output}"
ANALYSIS_SOURCE="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"

cmd="${1:-status}"

capture_count() {
	local dir="$1"
	if [ ! -d "$dir" ]; then
		echo 0
		return
	fi
	ls -1 "$dir"/*.pi.normalized.raw 2>/dev/null | wc -l
}

case "$cmd" in
status)
	count=0
	if [ -d "$CACHE_DIR/captures" ]; then
		count="$(capture_count "$CACHE_DIR/captures")"
	fi
	echo "goal21-render-diff-capture-cache: baseline=$CACHE_KEY cache=$CACHE_DIR captures=$count"
	;;
save)
	mkdir -p "$CACHE_DIR"
	if [ ! -d "$SOURCE" ]; then
		echo "goal21-render-diff-capture-cache: missing source $SOURCE" >&2
		exit 1
	fi
	count="$(capture_count "$SOURCE")"
	if [ "${count:-0}" -eq 0 ]; then
		echo "goal21-render-diff-capture-cache: no captures in $SOURCE" >&2
		exit 1
	fi
	rm -rf "$CACHE_DIR/captures" "$CACHE_DIR/analysis"
	mkdir -p "$CACHE_DIR"
	cp -a "$SOURCE" "$CACHE_DIR/captures"
	if [ -d "$ANALYSIS_SOURCE" ]; then
		cp -a "$ANALYSIS_SOURCE" "$CACHE_DIR/analysis"
	fi
	printf '%s\n' "$BASELINE_COMMIT" >"$CACHE_DIR/baseline.txt"
	echo "goal21-render-diff-capture-cache: saved $count captures to $CACHE_DIR"
	;;
restore)
	if [ ! -d "$CACHE_DIR/captures" ]; then
		echo "goal21-render-diff-capture-cache: no cache for $CACHE_KEY" >&2
		exit 1
	fi
	mkdir -p "$SOURCE"
	rm -rf "$SOURCE"/*
	cp -a "$CACHE_DIR/captures/." "$SOURCE/"
	if [ -d "$CACHE_DIR/analysis" ]; then
		mkdir -p "$ANALYSIS_SOURCE"
		rm -rf "$ANALYSIS_SOURCE"/*
		cp -a "$CACHE_DIR/analysis/." "$ANALYSIS_SOURCE/"
	fi
	echo "goal21-render-diff-capture-cache: restored $(capture_count "$SOURCE") captures to $SOURCE"
	;;
*)
	echo "usage: $0 save|restore|status" >&2
	exit 2
	;;
esac
