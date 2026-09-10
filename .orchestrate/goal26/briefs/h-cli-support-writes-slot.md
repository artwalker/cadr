GOAL: Close the paired-path vs isolated-microbench gap on the three cli_support write metrics. Prefer ≤1.0× on fair Friend-MachineD remesure. Do not relitigate posix shapes already reverted.

SCOPE: Exclusive worktree /tmp/cadr-g26-h-support-writes-slot. Harness timed slot and only product changes that remove work the leftover does not pay (prove pi writeFileSync+renameSync does not fsync before touching :durability). Evidence /tmp/g26-support-writes-slot-* .

CONTEXT:
- HEAD fair paired: overwrite 3.329× (887/266µs), hello 5.760× (808/140µs), empty 10.994× (467/42µs).
- Best product invent h2 reverted: 1.585× / 1.777× / 1.341× (422/249/57µs). Keep bar ≤1.0×.
- Worker note: isolated hello microbench ~126–158µs already sits at leftover 140µs. Paired h2 hello median 249µs. That ~100µs is the next knife. It is the cadr collect slot, not another unix-open variant.
- Product HEAD `cadr-core:atomic-write-string` still calls `ensure-directories-exist` inside `call-with-atomic-replacement` and defaults `:durability :flush` (`finish-output`). Confirm whether leftover `activateManagedReleaseWrite` fsyncs. If it does not, a flush downgrade is a fair alignment only with that evidence. If it does, do not drop flush.
- Standing: /root/projects/cadr/.orchestrate/goal26/preferences.md
- Prior: /tmp/g26-h-support-writes-REPORT.md

ACCEPTANCE:
- Explain paired vs isolated µs with a measurement, then one hypothesis, remesure, keep only ≤1.0× or full revert.
- If the slot tax is real and removable without leftover-only win, land that keep.
- If after the slot fix the product is still >1.0×, stop and say so. Do not open a second posix hunt.
- /tmp/g26-h-support-writes-slot-REPORT.md + decisions.tsv + patches.

VERIFY: print three write ratios plus the isolated vs paired hello µs you measured.

TIMEBOX: 90 minutes

FORBIDDEN: no gt/rebase/force-push; no dirty tip; no leftover-only win; no silent freeze; no RATIO_CEILINGS drop; do not revert threads/close keeps.

STANDING: read preferences.md verbatim and obey
