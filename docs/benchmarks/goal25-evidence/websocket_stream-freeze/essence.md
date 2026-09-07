# websocket_stream.stream_roundtrip frozen-unreachable

Class: product-path.

Timed work: cadr `stream-chat` `:transport :websocket` (usocket loopback on 127.0.0.1) vs pi `stream` `transport: "websocket"` through MockWebSocket with no TCP (Pair 102).

Friend-MachineD remesure 2026-09-07 n=5, GOAL20_PART_O_SLICE and GOAL20_FLOOR_SLICE unset: 229.69x (45856.9 / 199.6 us). Gate PASS enforced-only. Observed ws_text=Hello stop_reason=stop usage 1/1 exact.

Why 1.0x is unreachable: cadr pays a real TCP handshake and frames (~46 ms). pi pays an in-process mock (~0.2 ms). Banned levers: mock the cadr transport, or put pi on TCP. Frame-encode invent cannot close ~230x.

Invent this run: 0 keeps.
