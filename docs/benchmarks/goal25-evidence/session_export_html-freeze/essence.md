# session_export_html.to_html frozen-unreachable

Class: product-path.

Timed work: cadr `export-session-html` vs pi `exportSessionToHtml` (Pair 23).

Friend-MachineD remesure 2026-09-07 n=5, GOAL20_PART_O_SLICE and GOAL20_FLOOR_SLICE unset: 2.331x (13867.6 / 5948.2 us). Gate PASS enforced-only. Observed has_accent=1 theme=dark exact. html_chars 555702 vs 547028 is the booked size gap.

Why 1.0x is unreachable: stream-splice templates already shipped. The remaining ~2.3x is Lisp JSON plus template write versus V8, plus 1.6% more HTML. Closing 1.0x means matching the exported document or the JSON encoder, which changes the ruler.

Invent this run: 0 keeps.
