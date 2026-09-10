GOAL: Land Goal 26 charter surface (already authored on tip working tree). Confirm open-gate reports open-parity=17.

SCOPE: docs/acceptance/goal-v26.md; docs/benchmarks/goal26-*.tsv; scripts/goal26-open-gate.py; .orchestrate/goal26/; .audit/goal26-decisions.tsv. No product src.

CONTEXT: User asked for beat preferred, parity minimum. Cohort is 17 Goal25 frozen-unreachable. Out: subus-floor and measure-only.

ACCEPTANCE:
- python3 scripts/goal26-open-gate.py prints open-parity=17
- charter names met-beat | met-parity | accepted-runtime-gap only

VERIFY: python3 scripts/goal26-open-gate.py

TIMEBOX: 15 minutes

FORBIDDEN: no invent; no Goal 20–25 rewrite as incomplete

REPORT: gate output; paths touched

STANDING: read /root/projects/cadr/.orchestrate/goal26/preferences.md verbatim and obey
