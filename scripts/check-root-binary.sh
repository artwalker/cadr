#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--project-directory" ]; then
    echo "usage: $0 [--project-directory PATH]" >&2
    exit 2
  fi
  PROJECT_DIRECTORY="$(CDPATH= cd -- "$2" && pwd)"
fi

ROOT_BINARY="$PROJECT_DIRECTORY/cadr"
SOURCE_DIRECTORY="$PROJECT_DIRECTORY/src"

for REQUIRED_COMMAND in find git stat; do
  if ! command -v "$REQUIRED_COMMAND" >/dev/null 2>&1; then
    echo "root binary freshness: required command is missing: $REQUIRED_COMMAND" >&2
    exit 2
  fi
done

if [ ! -d "$SOURCE_DIRECTORY" ]; then
  echo "root binary freshness: source directory is missing: $SOURCE_DIRECTORY" >&2
  exit 1
fi

if [ ! -x "$ROOT_BINARY" ]; then
  echo "root binary freshness: root cadr binary is missing or not executable: $ROOT_BINARY" >&2
  exit 1
fi

LATEST_SOURCE_MTIME_EPOCH=0
LATEST_SOURCE_MTIME_PATH=""
while IFS= read -r -d '' SOURCE_PATH; do
  SOURCE_MTIME_EPOCH="$(stat -c %Y "$SOURCE_PATH")"
  if [ "$SOURCE_MTIME_EPOCH" -gt "$LATEST_SOURCE_MTIME_EPOCH" ]; then
    LATEST_SOURCE_MTIME_EPOCH="$SOURCE_MTIME_EPOCH"
    LATEST_SOURCE_MTIME_PATH="$SOURCE_PATH"
  fi
done < <(find "$SOURCE_DIRECTORY" -type f -print0)

LATEST_SRC_COMMIT_EPOCH=0
LATEST_SRC_COMMIT_HASH="none"
LATEST_SRC_COMMIT_TIME="none"
if git -C "$PROJECT_DIRECTORY" rev-parse --is-inside-work-tree \
    >/dev/null 2>&1; then
  LATEST_SRC_COMMIT_EPOCH="$(
    git -C "$PROJECT_DIRECTORY" log -1 --format=%ct -- src
  )"
  if [ -n "$LATEST_SRC_COMMIT_EPOCH" ]; then
    LATEST_SRC_COMMIT_HASH="$(
      git -C "$PROJECT_DIRECTORY" log -1 --format=%H -- src
    )"
    LATEST_SRC_COMMIT_TIME="$(
      git -C "$PROJECT_DIRECTORY" log -1 --format=%cI -- src
    )"
  else
    LATEST_SRC_COMMIT_EPOCH=0
  fi
fi

ROOT_BINARY_EPOCH="$(stat -c %Y "$ROOT_BINARY")"
ROOT_BINARY_TIME="$(stat -c %y "$ROOT_BINARY")"
ROOT_BINARY_VERSION="$("$ROOT_BINARY" --version)"
LATEST_SOURCE_MTIME="none"
if [ -n "$LATEST_SOURCE_MTIME_PATH" ]; then
  LATEST_SOURCE_MTIME="$(stat -c %y "$LATEST_SOURCE_MTIME_PATH")"
fi

printf '%s\n' "root binary freshness:"
printf '  binary: %s\n' "$ROOT_BINARY"
printf '  binary build time: %s\n' "$ROOT_BINARY_TIME"
printf '  binary version: %s\n' "$ROOT_BINARY_VERSION"
printf '  latest src commit: %s %s\n' \
  "$LATEST_SRC_COMMIT_HASH" "$LATEST_SRC_COMMIT_TIME"
printf '  latest source mtime: %s %s\n' \
  "$LATEST_SOURCE_MTIME" "$LATEST_SOURCE_MTIME_PATH"

FRESHNESS_EPOCH="$LATEST_SOURCE_MTIME_EPOCH"
if [ "$LATEST_SRC_COMMIT_EPOCH" -gt "$FRESHNESS_EPOCH" ]; then
  FRESHNESS_EPOCH="$LATEST_SRC_COMMIT_EPOCH"
fi

if [ "$ROOT_BINARY_EPOCH" -le "$FRESHNESS_EPOCH" ]; then
  echo "root binary freshness: root cadr binary is stale" >&2
  exit 1
fi

echo "root binary freshness: root cadr binary is fresh"
