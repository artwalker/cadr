#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${CADR_RENDER_DIFF_FULL_OUTPUT:-/tmp/cadr-render-diff-full}
analysis=${CADR_RENDER_DIFF_FULL_ANALYSIS:-/tmp/cadr-render-diff-full-analysis}

exec python3 "$project_root/scripts/render-diff.py" gate \
  --tier full \
  --pi-repo "$project_root" \
  --output "$output" \
  --analysis-output "$analysis" \
  "$@"
