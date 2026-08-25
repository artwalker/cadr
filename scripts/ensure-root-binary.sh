#!/usr/bin/env bash
# Refresh ./cadr when it is missing or older than src/. Fails if rebuild fails.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
	case "$1" in
	--project-directory)
		PROJECT_DIRECTORY="$(CDPATH= cd -- "${2:?}" && pwd)"
		shift 2
		;;
	esac
fi

if "$PROJECT_DIRECTORY/scripts/check-root-binary.sh" \
	--project-directory "$PROJECT_DIRECTORY" >/dev/null 2>&1; then
	echo "ensure-root-binary: fresh"
	exit 0
fi

echo "ensure-root-binary: stale or missing; rebuilding" >&2
"$PROJECT_DIRECTORY/scripts/rebuild-root-binary.sh" \
	--project-directory "$PROJECT_DIRECTORY"
"$PROJECT_DIRECTORY/scripts/check-root-binary.sh" \
	--project-directory "$PROJECT_DIRECTORY"
