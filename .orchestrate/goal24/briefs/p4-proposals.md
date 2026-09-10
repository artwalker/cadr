GOAL: Close all needs-proposal rows with written proposals in docs/adjudications.md or benchmark notes + disposition update.
SCOPE: docs/adjudications.md, dispositions, audit. No silent ignore. Includes write_* and any other needs-proposal on tip.
ACCEPTANCE: needs-proposal count 0
VERIFY: each former row has disposition != needs-proposal and evidence pointer
TIMEBOX: 90m
FORBIDDEN: invent that claims close without proposal text
REPORT: list of proposals
STANDING: preferences.md
