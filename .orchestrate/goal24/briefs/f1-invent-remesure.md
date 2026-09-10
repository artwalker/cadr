GOAL: Remesure /tmp/g24-b2-invent.patch on Friend-MachineD; land keep if <=1.0x for touched metrics, else reclassify and discard patch.
SCOPE: May write /tmp/g24-b2-wt worktree, dispositions TSV rows for selector/dialog metrics, audit trail. May not touch RATIO_CEILINGS or Goal 20/21 docs.
CONTEXT: Patch /tmp/g24-b2-invent.patch from prior batch2. Tip already has watch_signature keep. Metrics still open-floor-invent include cli_selectors.* and cli_print_rpc.dialog_*.
ACCEPTANCE:
- Friend-MachineD paired remesure n>=5 with --only-enforce for metrics the patch claims
- Each metric either met-remesure with summary.json path, or terminal reclassify with reason
- Product keep only if remesure <=1.0x; otherwise revert patch application
VERIFY: scripts/goal20-paired-paths.sh --samples 5 --warmups 1 --only-enforce <metrics> --out /tmp/g24-f1-after; read ratios in summary.json
TIMEBOX: 90 minutes; return partial on expiry
FORBIDDEN: no gt, no rebase, no force-push, no tip dirty mid-edit, no ceiling drops with speedup
REPORT: status, branch, head SHA, PR if any, verdict, ratios table, patch path, disposition updates
STANDING: see store preferences.md
