;;; Selected golden cases from test/fixtures/mermaid-golden/reference.json,
;;; which was generated from the baseline grok-mermaid@0.2.2 dist/index.js
;;; (see reference.json :generatorScript).  Each case is (id input width
;;; warnings plain); a case with :null t in the fixture is stored as
;;; (id input :null).  These lock the renderer against regressions
;;; without depending on the JSON fixture, and complement the full
;;; golden comparison in mermaid-golden-test.lisp.
(in-package #:cadr-tui/tests)

(defparameter +mermaid-reference-cases+
  (list
   ;; graph-lr
   (list "graph-lr" "flowchart LR
  A-->B" 14 nil (list "┌───┐    ┌───┐" "│ A ├───▶│ B │" "└───┘    └───┘"))
   ;; graph-td-chain
   (list "graph-td-chain" "graph TD
  A-->B
  B-->C" 6 nil (list " ┌───┐" " │ A │" " └─┬─┘" "   │" "   ▼" " ┌───┐" " │ B │" " └─┬─┘" "   │" "   ▼" " ┌───┐" " │ C │" " └───┘"))
   ;; graph-subgraph
   (list "graph-subgraph" "flowchart LR
  subgraph one
    A-->B
  end
  C-->A" 25 nil (list "         ┌ one ─────────┐" "         │              │" "┌───┐    │┌───┐    ┌───┐│" "│ C ├───▶││ A ├───▶│ B ││" "└───┘    │└───┘    └───┘│" "         └──────────────┘"))
   ;; graph-html
   (list "graph-html" "flowchart LR
  A[&lt;b&gt;x&lt;/b&gt;] --> B[`code`]" 7 (list "node \"A\": label is missing its closing `]`" "dropped, does not start with a node: \"/b&gt\"" "dropped, does not start with a node: \"] --> B[`code`]\"") (list "┌─────┐" "│ &lt │" "└─────┘" "" "┌───┐" "│ b │" "└───┘" "" "┌────┐" "│ gt │" "└────┘" "" "┌───┐" "│ x │" "└───┘" "" "┌────┐" "│ lt │" "└────┘"))
   ;; graph-html2
   (list "graph-html2" "flowchart LR
  A[\"&amp;#35;\"] --> B[\"x<y\"]" 20 nil (list "┌───────┐    ┌─────┐" "│ &#35; ├───▶│ x<y │" "└───────┘    └─────┘"))
   ;; graph-cjk
   (list "graph-cjk" "flowchart LR
  A[你好世界]-->B[测试]" 24 nil (list "┌──────────┐    ┌──────┐" "│ 你好世界 ├───▶│ 测试 │" "└──────────┘    └──────┘"))
   ;; graph-emoji
   (list "graph-emoji" "flowchart LR
  A[👨‍👩‍👧 family]-->B[🇨🇳]" 23 nil (list "┌───────────┐    ┌────┐" "│ 👨‍👩‍👧 family ├───▶│ 🇨🇳 │" "└───────────┘    └────┘"))
   ;; state-basic
   (list "state-basic" "stateDiagram-v2
  [*] --> S1
  S1 --> S2
  S2 --> [*]" 6 nil (list " ╭───╮" " │ ● │" " ╰─┬─╯" "   │" "   ▼" "╭────╮" "│ S1 │" "╰──┬─╯" "   │" "   ▼" "╭────╮" "│ S2 │" "╰──┬─╯" "   │" "   ▼" " ╭───╮" " │ ● │" " ╰───╯"))
   ;; state-fork
   (list "state-fork" "stateDiagram-v2
  A --> B
  A --> C" 14 nil (list "     ╭───╮" "     │ A │" "     ╰─┬─╯" "   ┌───┴───┐" "   ▼       ▼" " ╭───╮   ╭───╮" " │ B │   │ C │" " ╰───╯   ╰───╯"))
   ;; state-note
   (list "state-note" "stateDiagram-v2
  A --> B
  note right of A: hi" 6 nil (list " ╭───╮" " │ A │" " ╰─┬─╯" "   │" "   ▼" " ╭───╮" " │ B │" " ╰───╯"))
   ;; class-basic
   (list "class-basic" "classDiagram
  class Animal
  class Dog
  Animal <|-- Dog" 10 nil (list "┌────────┐" "│ Animal │" "└────△───┘" "     │" "     │" "  ┌─────┐" "  │ Dog │" "  └─────┘"))
   ;; class-chain
   (list "class-chain" "classDiagram
  Animal <|-- Dog
  Dog --> Person" 10 nil (list "┌────────┐" "│ Animal │" "└────△───┘" "     │" "     │" "  ┌─────┐" "  │ Dog │" "  └──┬──┘" "     │" "     ▼" "┌────────┐" "│ Person │" "└────────┘"))
   ;; class-note
   (list "class-note" "classDiagram
  class A
  note \"hello\" for A" 6 nil (list " ┌───┐" " │ A │" " └───┘"))
   ;; er-basic
   (list "er-basic" "erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER ||--|{ LINE-ITEM : contains" 23 nil (list " ┌──────────┐" " │ CUSTOMER │" " └─────┬────┘" "       │" "       │1 places 0..*" "   ┌───────┐" "   │ ORDER │" "   └───┬───┘" "       │" "       │1 contains 1..*" " ┌───────────┐" " │ LINE-ITEM │" " └───────────┘"))
   ;; er-attrs
   (list "er-attrs" "erDiagram
  CUSTOMER {
    string name
  }
  CUSTOMER ||--o{ ORDER : places" 22 nil (list " ┌─────────────┐" " │  CUSTOMER   │" " ├─────────────┤" " │ string name │" " └──────┬──────┘" "        │" "        │1 places 0..*" "    ┌───────┐" "    │ ORDER │" "    └───────┘"))
   ;; er-doc-example
   (list "er-doc-example" "erDiagram
  CAR ||--o{ NAMED-DRIVER : allows
  CAR {
    string model
    string number
  }
  PERSON ||--o{ NAMED-DRIVER : is" 31 nil (list " ┌───────────────┐" " │      CAR      │  ┌────────┐" " ├───────────────┤  │ PERSON │" " │ string model  │  └────┬───┘" " │ string number │       │" " └───────┬───────┘       │" "         └───────┬───────┘" "                 │1 allows 0..*" "         ┌──────────────┐" "         │ NAMED-DRIVER │" "         └──────────────┘"))
   ;; seq-basic
   (list "seq-basic" "sequenceDiagram
  Alice->>John: Hello John
  John-->>Alice: Great" 20 nil (list "┌───────┐   ┌──────┐" "│ Alice │   │ John │" "└───┬───┘   └───┬──┘" "    │           │" "    │Hello John │" "    ├──────────▶│" "    │           │" "    │   Great   │" "    │◄╌╌╌╌╌╌╌╌╌╌┤" "    │           │" "┌───┴───┐   ┌───┴──┐" "│ Alice │   │ John │" "└───────┘   └──────┘"))
   ;; seq-note
   (list "seq-note" "sequenceDiagram
  Alice->>John: hi
  Note right of Alice: note text" 24 nil (list "┌───────┐       ┌──────┐" "│ Alice │       │ John │" "└───┬───┘       └───┬──┘" "    │               │" "    │      hi       │" "    ├──────────────▶│" "    │               │" "    │ ┌───────────┐ │" "    │ │ note text │ │" "    │ └───────────┘ │" "    │               │" "┌───┴───┐       ┌───┴──┐" "│ Alice │       │ John │" "└───────┘       └──────┘"))
   ;; seq-loop
   (list "seq-loop" "sequenceDiagram
  loop every day
    Alice->>John: hi
  end" 19 nil (list "┌───────┐ ┌──────┐" "│ Alice │ │ John │" "└───┬───┘ └───┬──┘" "    │         │" "── loop every day ─" "    │         │" "    │   hi    │" "    ├────────▶│" "    │         │" "── end ────────────" "    │         │" "┌───┴───┐ ┌───┴──┐" "│ Alice │ │ John │" "└───────┘ └──────┘"))
   ;; seq-cjk
   (list "seq-cjk" "sequenceDiagram
  小明->>小红: 你好
  小红-->>小明: 好的" 17 nil (list "┌──────┐ ┌──────┐" "│ 小明 │ │ 小红 │" "└───┬──┘ └───┬──┘" "    │        │" "    │  你好  │" "    ├───────▶│" "    │        │" "    │  好的  │" "    │◄╌╌╌╌╌╌╌┤" "    │        │" "┌───┴──┐ ┌───┴──┐" "│ 小明 │ │ 小红 │" "└──────┘ └──────┘"))
   ;; seq-emoji
   (list "seq-emoji" "sequenceDiagram
  Alice->>Bob: 👋 hi
  Bob-->>Alice: 👍" 18 nil (list "┌───────┐  ┌─────┐" "│ Alice │  │ Bob │" "└───┬───┘  └──┬──┘" "    │         │" "    │  👋 hi  │" "    ├────────▶│" "    │         │" "    │   👍    │" "    │◄╌╌╌╌╌╌╌╌┤" "    │         │" "┌───┴───┐  ┌──┴──┐" "│ Alice │  │ Bob │" "└───────┘  └─────┘"))
   ;; err-bad
   (list "err-bad" "not a diagram" :null)
   ;; flowchart-empty-body
   (list "flowchart-empty-body" "flowchart LR" :null)
   ;; state-err
   (list "state-err" "stateDiagram-v2
  A -->" :null)
   ;; empty
   (list "empty" "" :null)
   ;; comment
   (list "comment" "%% just a comment" :null)
   ;; err-graph
   (list "err-graph" "flowchart LR
  A[" 5 (list "node \"A\": label is missing its closing `]`") (list "┌───┐" "│   │" "└───┘"))
   ;; class-err
   (list "class-err" "classDiagram
  class A
  A -->" 6 (list "dropped, unreadable final line: \"A -->\"") (list " ┌───┐" " │ A │" " └───┘"))
   ;; graph-half-link
   (list "graph-half-link" "flowchart LR
  A-->" 5 (list "dropped, link has no target: \"A-->\"") (list "┌───┐" "│ A │" "└───┘"))
   ))
