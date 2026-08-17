;;; grok-mermaid@0.2.2 dist/ansi.js:1-22 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; grok-mermaid dist/ansi.js paints :styled spans with SGR.  cadr's TUI
;;; does that through mermaid-themed-lines / mermaid-style-span (theme
;;; tokens, not this class→SGR map).  Golden fixtures compare :styled,
;;; not ANSI, so the convenience was never called.  File stays as the
;;; port attribution; class names ("border", "edge", "edgeLabel",
;;; "title") are written by canvas/layout and read by transform.

(in-package #:cadr-tui)
