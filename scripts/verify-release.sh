#!/usr/bin/env bash
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# The release gate may never report success with live verification
# unrun: CADR_RELEASE_GATE turns any live SKIP into a failure that names
# the missing credential (goal 18 I6).
export CADR_RELEASE_GATE=1

"$project_root/scripts/verify.sh"
"$project_root/scripts/test-render-diff-full.sh"
