# cli_print_rpc.dialog_request frozen-unreachable

Class: product-path. Sibling `dialog_result` stays frozen-leftover-ruler.

Timed work: cadr `rpc-dialog-request-object` (`src/cadr-cli/modes/rpc/ui.lisp`) vs the frozen mjs replica `rpcDialogRequestObject` (plain object plus optional assigns). Harness then `json-get`s six fields. Repetitions 50.

Stop: Friend-MachineD product remesure <=1.0x. Direction: lower ratio.

Baseline this run (PART_O/FLOOR unset): cadr n=5 median 1.765 µs (`/tmp/g25-cli_print_rpc-baseline/cadr.json`). Pi half of the frozen shell died later in `harness_storage` (`JsonlSessionRepo.absolutePath`). Booked pi from g24 f1-after on this host is 0.393 µs, ratio 4.128x.

Why 1.0x is unreachable:

1. The object is an EQUAL hash table. V8 builds a hidden-class object in ~0.4 µs. SBCL `make-hash-table` plus string hashes plus six `json-get`s does not match that.
2. Goal 24 already discarded the sized EQUAL hash + `setf` invent (local 1.82→1.13 µs, Friend-MachineD still 4.128x).
3. Goal 25 screened `:json-object` pairs (json-get already supports them), a defstruct with slot `json-get`, skipping `coerce`, and a recycled struct. Best local median ~0.52 µs. Applied pairs + `json-put` on pairs: product-current 0.91 µs, still ~2.3x vs 0.393 µs. Scaled with the g24 local-to-host factor that would be ~3x. Reverted in full.
4. Recycle did not beat the observe. The frozen ruler includes `json-get`, which is not V8 property access.
5. Global `:json-object` pairs and pre-size EQUAL hash are banned on `pi_messages` (adjudications 2026-08-21). Using them here still misses 1.0x.

Banned levers: leftover collect as met-hillclimb, RATIO_CEILINGS drop, Goal 23 jsonl adapter rewrite, `:json-object` pairs in `pi-context-json`.

Invent this run: 1 product attempt (pairs), reverted. No src keep.
