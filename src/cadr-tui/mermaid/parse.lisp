;;; grok-mermaid@0.2.2 dist/parse.js:1-1107 — direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; Source text to diagram model.  Every parser returns NIL when the source is
;;; not that kind of diagram, or when it exceeds a cap — the renderer tries
;;; each in turn and falls back to a framed copy of the source when they all
;;; decline.  Statements are split on `;` with `%%` comments and quoted spans
;;; opaque; further parsing walks the source string with CHAR (JS [...s]
;;; indexes code points; SBCL characters are already code points).

(in-package #:cadr-tui)

;;; JS function declarations hoist; CL compiles top-down, so the direct-port
;;; order would otherwise warn on every forward call.  Declare the set of
;;; functions defined later in this file so the module compiles warning-free
;;; without reordering definitions away from the JS source order.
(declaim (ftype function
                gm-display-generics gm-er-card gm-line-kind gm-lstrip-pluses
                gm-parse-class-relation gm-parse-er-op gm-parse-link
                gm-parse-node gm-parse-node-group gm-parse-note-anchor
                gm-parse-seq-message gm-parse-state-decl gm-parse-state-desc
                gm-parse-statement gm-parse-subgraph-decl
                gm-parse-subgraph-decl-bracket gm-parse-transition
                gm-push-er-attribute gm-push-member gm-read-shape
                gm-read-shape-at gm-skip-spaces gm-split-er-relationship
                gm-state-endpoint gm-strip-cardinality-prefix
                gm-strip-cardinality-suffix gm-trailing-head))

(defun gm-char-list (s) s)
(defun gm-char (chars i)
  ;; grok-mermaid parse.js indexes a code-point array.  SBCL characters
  ;; are code points, so CHAR is the O(1) equivalent of nth on a list.
  (and (< i (length chars)) (char chars i)))
(defun gm-list-string (chars) (coerce chars 'string))

;;; chars[i..i+len) equals string s.
(defun gm-char-seq-equal (chars i s)
  (let ((len (length s)))
    (and (<= (+ i len) (length chars))
         (loop for k from 0 below len
               always (char= (char chars (+ i k)) (char s k))))))

(defun gm-trim-start (s)
  (let ((start 0))
    (loop while (and (< start (length s)) (gm-whitespace-p (char s start)))
          do (incf start))
    (subseq s start)))

(defun gm-trim-end (s)
  (let ((end (length s)))
    (loop while (and (plusp end) (gm-whitespace-p (char s (1- end))))
          do (decf end))
    (subseq s 0 end)))

(defun gm-has-whitespace (s)
  (find-if (lambda (c) (gm-whitespace-p c)) s))

;;; Rust's split_once: first occurrence of sep.
(defun gm-split-once (s sep)
  (let ((i (search sep s)))
    (if i
        (list (subseq s 0 i) (subseq s (+ i (length sep))))
        nil)))

(defun gm-non-empty (s) (if (string= s "") nil s))

(defun gm-join-strings (list sep)
  (with-output-to-string (out)
    (loop for s in list
          for first = t then nil
          do (unless first (write-string sep out))
             (write-string s out))))

;;; Join non-empty strings with sep (JS .filter(s => s !== '').join(sep)).
(defun gm-join-nonempty (list sep)
  (gm-join-strings (remove-if (lambda (s) (string= s "")) list) sep))

(defun gm-rstrip-dashes (s)
  (let ((end (length s)))
    (loop while (and (plusp end) (char= (char s (1- end)) #\-))
          do (decf end))
    (subseq s 0 end)))

(defun gm-lstrip-arrows (s)
  (let ((start 0))
    (loop while (and (< start (length s)) (char= (char s start) #\>))
          do (incf start))
    (subseq s start)))

(defun gm-rstrip-brackets (s)
  (let ((end (length s)))
    (loop while (and (plusp end) (char= (char s (1- end)) #\]))
          do (decf end))
    (subseq s 0 end)))

;;; ---------------------------------------------------------------- statements
(defun gm-flush-statement (cur out)
  (let ((trimmed (gm-trim cur)))
    (if (plusp (length trimmed))
        (cons trimmed out)
        out)))

;;; Split one source line into statements on `;`, stopping at a `%%` comment.
;;; Quoted spans are opaque, so a label may contain `;` and `%%`.
(defun gm-split-statements (line out)
  ;; Stream the accumulator and index the string directly: the old
  ;; char-list + nth + per-char concatenate form was quadratic twice
  ;; over (goal 20, 12F-4).
  (let ((in-quotes nil)
        (line-length (length line)))
    (with-output-to-string (stream)
      (loop for i from 0 below line-length
            for c = (char line i)
            do (cond (in-quotes
                      (when (char= c #\") (setf in-quotes nil))
                      (write-char c stream))
                     ((char= c #\")
                      (setf in-quotes t)
                      (write-char c stream))
                     ((and (char= c #\%) (< (1+ i) line-length)
                           (char= (char line (1+ i)) #\%))
                      (return))
                     ((char= c #\;)
                      (setf out
                            (gm-flush-statement
                             (get-output-stream-string stream) out)))
                     (t
                      (write-char c stream))))
      (setf out
            (gm-flush-statement (get-output-stream-string stream) out)))
    out))

;;; All statements in a source block, in order.
(defun gm-statements-of (src)
  (let ((out nil))
    (dolist (line (gm-src-lines src))
      (setf out (gm-split-statements line out)))
    (nreverse out)))

(defun gm-first-word (s)
  (let ((ws (gm-split-words s)))
    (if ws (first ws) "")))

(defun gm-words (s) (gm-split-words s))

;;; Diagram kind from the header statement, lowercased.
(defun gm-header-kind (statements)
  (if (null statements)
      nil
      (let ((kind (gm-first-word (first statements))))
        (if (string= kind "") nil (gm-ascii-lower kind)))))

;;; The kind of diagram src declares, or NIL if its header names no type this
;;; renderer draws.  Reads the header only — it says nothing about whether the
;;; body parses.
(defun gm-diagram-kind (src)
  (let ((kind (gm-header-kind (gm-statements-of src))))
    (cond ((null kind) nil)
          ((or (string= kind "graph") (string= kind "flowchart")) "flowchart")
          ((and (>= (length kind) (length "statediagram"))
                (string= kind "statediagram"
                          :end1 (length "statediagram")
                          :end2 (length "statediagram")))
           "state")
          ((and (>= (length kind) (length "classdiagram"))
                (string= kind "classdiagram"
                          :end1 (length "classdiagram")
                          :end2 (length "classdiagram")))
           "class")
          ((string= kind "erdiagram") "er")
          ((string= kind "sequencediagram") "sequence")
          (t nil))))

;;; ---------------------------------------------------------------- flowchart
(defun gm-parse-graph (src)
  (let* ((statements (gm-statements-of src))
         (kind (gm-header-kind statements)))
    (unless (or (string= kind "graph") (string= kind "flowchart"))
      (return-from gm-parse-graph nil))
    (let ((graph (gm-make-graph (gm-parse-dir
                                 (or (second (gm-words (first statements))) "TB"))))
          (stack nil))
      (dolist (st (rest statements))
        (let ((first (gm-ascii-lower (gm-first-word st))))
          (cond ((string= first "subgraph")
                 (when (or (>= (length (gm-graph-groups graph)) +gm-max-groups+)
                           (>= (length stack) +gm-max-group-depth+))
                   (return-from gm-parse-graph nil))
                 (let* ((rest (gm-trim (subseq st (length "subgraph"))))
                        (decl (gm-parse-subgraph-decl rest)))
                   (setf (gm-graph-groups graph)
                         (append (gm-graph-groups graph)
                                 (list (list :id (first decl)
                                             :label (second decl)
                                             :parent (if stack (car stack) nil)))))
                   (push (1- (length (gm-graph-groups graph))) stack)
                   (setf (gm-graph-cur-group graph) (car stack))))
                ((string= first "end")
                 (pop stack)
                 (setf (gm-graph-cur-group graph) (car stack)))
                ((member first '("classdef" "class" "style" "linkstyle"
                                 "click" "direction")
                         :test #'string=)
                 nil)
                (t
                 (gm-parse-statement st graph))))
        (when (gm-graph-over-cap graph)
          (return-from gm-parse-graph nil)))
      (if (zerop (length (gm-graph-nodes graph))) nil graph))))

;;; subgraph id[Title], subgraph "Title", or a bare title.
(defun gm-parse-subgraph-decl (rest)
  (if (and (plusp (length rest)) (char= (char rest 0) #\"))
      (let ((close (position #\" rest :start 1)))
        (if close
            (let ((label (subseq rest 1 close)))
              (list label (gm-decode-html-entities label)))
            (gm-parse-subgraph-decl-bracket rest)))
      (gm-parse-subgraph-decl-bracket rest)))

(defun gm-parse-subgraph-decl-bracket (rest)
  (let ((open (position #\[ rest)))
    (if open
        (let ((id (gm-trim (subseq rest 0 open)))
              (label (gm-clean-label (gm-trim (gm-rstrip-brackets (subseq rest (1+ open)))))))
          (if (and (not (string= id "")) (not (string= label "")))
              (list id label)
              (list rest rest)))
        (list rest rest))))

;;; A chain of node link node link node ..., each link fanning out over `&`.
;;; Parses as far as it can and keeps the prefix; whatever it could not read
;;; is recorded in graph.warnings rather than failing the diagram.
(defun gm-parse-statement (st graph)
  (let ((chars (gm-char-list st)))
    (let ((head (gm-parse-node-group chars 0 graph)))
      (unless head
        (setf (gm-graph-warnings graph)
              (nconc (gm-graph-warnings graph)
                     (list (format nil "dropped, does not start with a node: \"~A\""
                                   st))))
        (return-from gm-parse-statement nil))
      (let ((prev (first head))
            (i (second head)))
        (loop do (setf i (gm-skip-spaces chars i))
              until (>= i (length chars))
              do (let ((link (gm-parse-link chars i)))
                   (unless link
                     (setf (gm-graph-warnings graph)
                           (nconc (gm-graph-warnings graph)
                                  (list (format nil "dropped, expected a link: \"~A\""
                                                (gm-list-string (subseq chars i))))))
                     (return))
                   (setf i (gm-skip-spaces chars (fifth link)))
                   (let ((target (gm-parse-node-group chars i graph)))
                     (unless target
                       (setf (gm-graph-warnings graph)
                             (nconc (gm-graph-warnings graph)
                                    (list (format nil "dropped, link has no target: \"~A\""
                                                  st))))
                       (return))
                     (setf i (second target))
                     (dolist (f prev)
                       (dolist (tgt (first target))
                         ;; A <-- B reads right-to-left: swap the endpoints so
                         ;; the arrow written on the left becomes a forward head.
                         (let* ((reversed (and (string= (first link) "arrow")
                                               (not (string= (second link) "arrow"))))
                                (edge (gm-make-edge
                                       :from (if reversed tgt f)
                                       :to (if reversed f tgt)
                                       :label (fourth link)
                                       :head-to (if reversed "arrow" (second link))
                                       :head-from (if reversed (second link) (first link))
                                       :line (third link))))
                           (unless (gm-push-edge graph edge)
                             (return-from gm-parse-statement nil)))))
                     (setf prev (first target)))))))))

;;; One or more nodes joined by `&`, which fan out into a cross product.
;;; Returns (group next) or NIL.
(defun gm-parse-node-group (chars start graph)
  (let ((first (gm-parse-node chars start graph)))
    (unless first
      (return-from gm-parse-node-group nil))
    (let ((group (list (first first)))
          (i (second first)))
      (loop do (let ((j (gm-skip-spaces chars i)))
                (unless (and (< j (length chars)) (char= (gm-char chars j) #\&))
                  (return))
                (let ((next (gm-parse-node chars (1+ j) graph)))
                  (unless next
                    (return-from gm-parse-node-group nil))
                  (push (first next) group)
                  (setf i (second next)))))
      (list (nreverse group) i))))

(defun gm-skip-spaces (chars i)
  (loop while (and (< i (length chars))
                   (or (char= (gm-char chars i) #\Space)
                       (char= (gm-char chars i) #\Tab)))
        do (incf i))
  i)

;;; A node id plus its optional shape bracket.  Returns (index next) or NIL.
(defun gm-parse-node (chars start graph)
  (let* ((i (gm-skip-spaces chars start))
         (id-start i))
    (loop while (and (< i (length chars)) (gm-is-id-char (gm-char chars i)))
          do (incf i))
    (if (= i id-start)
        (return-from gm-parse-node nil))
    (let* ((id (gm-list-string (subseq chars id-start i)))
           (shaped (gm-read-shape-at chars i)))
      (when (fourth shaped)
        (setf (gm-graph-warnings graph)
              (nconc (gm-graph-warnings graph)
                     (list (format nil "node \"~A\": label is missing its closing `~A`"
                                   id (fourth shaped))))))
      (let ((index (gm-node-index graph id (second shaped) (first shaped))))
        (if (null index)
            nil
            (list index (third shaped)))))))

;;; Dispatch on the bracket following an id to pick shape and closing token.
;;; Returns (shape label after unclosed); unclosed is a closer string or NIL.
(defun gm-read-shape-at (chars i)
  (let ((c (gm-char chars i))
        (n (gm-char chars (1+ i))))
    (cond ((and c (char= c #\[))
           (cond ((and n (char= n #\[)) (gm-read-shape chars (+ i 2) "]]" "rect"))
                 ((and n (char= n #\()) (gm-read-shape chars (+ i 2) ")]" "round"))
                 (t (gm-read-shape chars (1+ i) "]" "rect"))))
          ((and c (char= c #\())
           (cond ((and n (char= n #\()) (gm-read-shape chars (+ i 2) "))" "round"))
                 ((and n (char= n #\[)) (gm-read-shape chars (+ i 2) "])" "round"))
                 (t (gm-read-shape chars (1+ i) ")" "round"))))
          ((and c (char= c #\{))
           (if (and n (char= n #\{))
               (gm-read-shape chars (+ i 2) "}}" "diamond")
               (gm-read-shape chars (1+ i) "}" "diamond")))
          ((and c (char= c #\>))
           (gm-read-shape chars (1+ i) "]" "rect"))
          (t (list "rect" nil i nil)))))

;;; Read label text up to closer.  Quoting is decided by the first non-space
;;; character: inside a quoted label the closer is ignored until the quote
;;; closes.  An unquoted label ends at the first closer.
(defun gm-read-shape (chars start closer shape)
  (let ((j start))
    (loop while (and (< j (length chars))
                     (or (char= (gm-char chars j) #\Space)
                         (char= (gm-char chars j) #\Tab)))
          do (incf j))
    (let ((quoted (and (< j (length chars)) (char= (gm-char chars j) #\")))
          (i start)
          (text "")
          (in-quotes nil))
      (loop while (< i (length chars))
            do (let ((c (gm-char chars i)))
                 (cond ((and quoted (char= c #\"))
                        (setf in-quotes (not in-quotes))
                        (setf text (concatenate 'string text (string c)))
                        (incf i))
                       ((and (not in-quotes)
                             (gm-char-seq-equal chars i closer))
                        (return-from gm-read-shape
                          (list shape (gm-clean-label text)
                                (+ i (length closer)) nil)))
                       (t
                        (setf text (concatenate 'string text (string c)))
                        (incf i)))))
      ;; Ran off the end still looking for the closer: everything after the
      ;; opening bracket became label text, so any link operator in it was
      ;; swallowed.
      (list shape (gm-clean-label text) (length chars) closer))))

(defun gm-is-link-char (c)
  (or (char= c #\-) (char= c #\.) (char= c #\=)
      (char= c #\<) (char= c #\>)))

;;; Read a link operator and its label.  Labels come in two forms: -->|text|
;;; and the inline `-- text -->`, the latter only when the first operator
;;; carried no head.  Returns (left right line label next) or NIL.
(defun gm-parse-link (chars start)
  (let ((i (gm-skip-spaces chars start))
        (left "none"))
    ;; A leading o/x decorates the tail, but only directly before an operator.
    (when (and (< i (length chars))
               (or (char= (gm-char chars i) #\o) (char= (gm-char chars i) #\x))
               (< (1+ i) (length chars))
               (let ((n (gm-char chars (1+ i))))
                 (or (char= n #\-) (char= n #\.) (char= n #\=))))
      (setf left (if (char= (gm-char chars i) #\o) "circle" "cross"))
      (incf i))
    (let ((op-start i))
      (loop while (and (< i (length chars)) (gm-is-link-char (gm-char chars i)))
            do (incf i))
      (if (= i op-start)
          (return-from gm-parse-link nil))
      (let* ((op1 (gm-list-string (subseq chars op-start i)))
             (line (gm-line-kind op1))
             (right "none"))
        (when (and (string= left "none")
                   (plusp (length op1))
                   (char= (char op1 0) #\<))
          (setf left "arrow"))
        (when (find #\> op1)
          (setf right "arrow"))
        (when (string= right "none")
          (let ((trailing (gm-trailing-head chars i)))
            (when trailing
              (setf right (first trailing))
              (setf i (second trailing)))))
        (if (and (< i (length chars)) (char= (gm-char chars i) #\|))
            (progn
              (incf i)
              (let ((l-start i))
                (loop while (and (< i (length chars))
                                 (not (char= (gm-char chars i) #\|)))
                      do (incf i))
                (let ((label (gm-clean-label (gm-list-string (subseq chars l-start i)))))
                  (when (and (< i (length chars)) (char= (gm-char chars i) #\|))
                    (incf i))
                  (list left right line (gm-non-empty label) i))))
            (progn
              (if (string= right "none")
                  (let* ((text-start (gm-skip-spaces chars i))
                         (j text-start))
                    (loop while (and (< j (length chars))
                                     (not (gm-is-link-char (gm-char chars j))))
                          do (incf j))
                    (if (and (< j (length chars))
                             (> j text-start)
                             (not (char= (gm-char chars j) #\<)))
                        (let* ((text (gm-list-string (subseq chars text-start j)))
                               (op2-start j))
                          (loop while (and (< j (length chars))
                                           (gm-is-link-char (gm-char chars j)))
                                do (incf j))
                          (let ((op2 (gm-list-string (subseq chars op2-start j))))
                            (when (find #\> op2)
                              (setf right "arrow"))
                            (when (string= right "none")
                              (let ((trailing (gm-trailing-head chars j)))
                                (when trailing
                                  (setf right (first trailing))
                                  (setf j (second trailing)))))
                            (when (string= line "solid")
                              (setf line (gm-line-kind op2)))
                            (list left right line
                                  (gm-non-empty (gm-clean-label text)) j)))
                        (list left right line nil i)))
                  (list left right line nil i))))))))

(defun gm-line-kind (op)
  (cond ((find #\= op) "thick")
        ((find #\. op) "dotted")
        (t "solid")))

;;; A trailing o/x head, only when followed by a statement boundary.
(defun gm-trailing-head (chars i)
  (let ((head (cond ((and (< i (length chars)) (char= (gm-char chars i) #\o)) "circle")
                    ((and (< i (length chars)) (char= (gm-char chars i) #\x)) "cross")
                    (t nil))))
    (unless head
      (return-from gm-trailing-head nil))
    (let* ((after (gm-char chars (1+ i)))
           (boundary (or (null after)
                         (char= after #\Space)
                         (char= after #\Tab)
                         (char= after #\|)
                         (char= after #\&)
                         (char= after #\;))))
      (if boundary (list head (1+ i)) nil))))

;;; --------------------------------------------------------------------- state
(defun gm-parse-state (src)
  (let* ((statements (gm-statements-of src))
         (kind (gm-header-kind statements)))
    (unless (and kind
                 (>= (length kind) (length "statediagram"))
                 (string= kind "statediagram"
                           :end1 (length "statediagram")
                           :end2 (length "statediagram")))
      (return-from gm-parse-state nil))
    (let ((graph (gm-make-graph))
          (in-note nil))
      (dolist (st (rest statements))
        (cond (in-note
               (when (string= (gm-ascii-lower st) "end note")
                 (setf in-note nil)))
              (t
               (let ((first (gm-ascii-lower (gm-first-word st))))
                 (cond ((string= first "direction")
                        (setf (gm-graph-dir graph)
                              (or (second (gm-words st)) "")))
                       ((string= first "note")
                        ;; A single-line `note ... : text` needs no terminator.
                        (unless (find #\: st) (setf in-note t)))
                       ((string= first "state")
                        (unless (gm-parse-state-decl st graph)
                          (return-from gm-parse-state nil)))
                       ((member first '("classdef" "class" "hide" "scale"
                                        "}" "--")
                                :test #'string=)
                        ;; Styling and composite-state punctuation carry no
                        ;; layout meaning.
                        nil)
                       ((search "-->" st)
                        (unless (gm-parse-transition st graph)
                          (return-from gm-parse-state nil)))
                       ((null (gm-parse-state-desc st graph))
                        (return-from gm-parse-state nil))))))
        (when (gm-graph-over-cap graph)
          (return-from gm-parse-state nil)))
      (if (zerop (length (gm-graph-nodes graph))) nil graph))))

;;; state "Label" as id, state id <<choice>>, or state id {.
(defun gm-parse-state-decl (st graph)
  (let* ((rest (gm-trim (subseq st (length "state"))))
         (rest (gm-trim (if (and (plusp (length rest))
                                 (char= (char rest (1- (length rest))) #\{))
                            (subseq rest 0 (1- (length rest)))
                            rest))))
    (when (string= rest "")
      (return-from gm-parse-state-decl t))
    (if (char= (char rest 0) #\")
        (let ((close (position #\" rest :start 1)))
          (when (null close)
            (return-from gm-parse-state-decl nil))
          (let* ((label (subseq rest 1 close))
                 (after (gm-trim (subseq rest (1+ close))))
                 (id (if (and (>= (length after) 2)
                              (string= (subseq after 0 2) "as"))
                         (gm-trim (subseq after 2))
                         label)))
            (if (null (gm-node-label graph id (gm-decode-html-entities label)))
                nil
                t)))
        (let ((shape "round")
              (id rest)
              (stereotyped nil))
          (let ((pos (search "<<" rest)))
            (when pos
              (let* ((tail (subseq rest (+ pos 2)))
                     (stereo (gm-trim
                              (if (and (>= (length tail) 2)
                                       (string= (subseq tail (- (length tail) 2)) ">>"))
                                  (subseq tail 0 (- (length tail) 2))
                                  tail))))
                (when (string= stereo "choice")
                  (setf shape "diamond"))
                (setf id (gm-trim (subseq rest 0 pos)))
                (setf stereotyped t))))
          (if (or (string= id "") (gm-has-whitespace id))
              (return-from gm-parse-state-decl nil))
          (if (null (gm-node-index graph id (if stereotyped id nil) shape))
              nil
              t)))))

;;; A --> B: label, including chains A --> B --> C.
(defun gm-parse-transition (st graph)
  (let ((rest st)
        (prev nil))
    (loop do (let ((split (gm-split-once rest "-->")))
              (unless split
                (return))
              (let* ((lhs (first split))
                     (rhs (second split))
                     (from-id (gm-trim (gm-rstrip-dashes (gm-trim-end lhs))))
                     (from nil))
                (if prev
                    ;; Mid-chain: the source is the previous target, so
                    ;; nothing may precede.
                    (if (not (string= from-id ""))
                        (return-from gm-parse-transition nil)
                        (setf from prev))
                    (progn
                      (when (string= from-id "")
                        (return-from gm-parse-transition nil))
                      (let ((f (gm-state-endpoint graph from-id t)))
                        (when (null f)
                          (return-from gm-parse-transition nil))
                        (setf from f))))
                (let* ((next-arrow (search "-->" rhs))
                       (to-part-raw (if next-arrow (subseq rhs 0 next-arrow) rhs))
                       (tail (if next-arrow (subseq rhs next-arrow) ""))
                       (colon (gm-split-once to-part-raw ":"))
                       (to-part (if colon (first colon) to-part-raw))
                       (label (if colon
                                  (gm-non-empty
                                   (gm-trim (gm-decode-html-entities (second colon))))
                                  nil))
                       (to-id (gm-trim
                               (gm-rstrip-dashes
                                (gm-lstrip-arrows (gm-trim-end to-part))))))
                  (when (string= to-id "")
                    (return-from gm-parse-transition nil))
                  (let ((to (gm-state-endpoint graph to-id nil)))
                    (when (null to)
                      (return-from gm-parse-transition nil))
                    (unless (gm-push-edge
                             graph
                             (gm-make-edge :from from :to to :label label
                                           :head-to "arrow" :head-from "none"
                                           :line "solid"))
                      (return-from gm-parse-transition t))
                    (setf prev to)
                    (setf rest tail))))))
    t))

;;; [*] is start or end depending on which side of the arrow it sits.
(defun gm-state-endpoint (graph id is-source)
  (if (string= id "[*]")
      (gm-node-index graph (if is-source "[*]start" "[*]end") "●" "round")
      (gm-node-index graph id nil "round")))

;;; id: description, or a bare state name.
(defun gm-parse-state-desc (st graph)
  (let ((split (gm-split-once st ":")))
    (if split
        (let ((id (gm-trim (first split)))
              (desc (gm-trim (second split))))
          (if (or (string= id "") (gm-has-whitespace id) (string= desc ""))
              (return-from gm-parse-state-desc nil))
          (if (null (gm-node-label graph id (gm-decode-html-entities desc)))
              nil
              t))
        (progn
          (when (gm-has-whitespace st)
            (return-from gm-parse-state-desc nil))
          (if (null (gm-node-index graph st nil "round"))
              nil
              t)))))

;;; --------------------------------------------------------------------- class
;;; Relation operators, longest-first so --|> wins over --.
(defparameter +gm-class-ops+
  '(("<|--" "triangle" "none" "solid")
    ("--|>" "none" "triangle" "solid")
    ("<|.." "triangle" "none" "dotted")
    ("..|>" "none" "triangle" "dotted")
    ("*--" "diamondFill" "none" "solid")
    ("--*" "none" "diamondFill" "solid")
    ("o--" "diamondOpen" "none" "solid")
    ("--o" "none" "diamondOpen" "solid")
    ("<--" "arrow" "none" "solid")
    ("-->" "none" "arrow" "solid")
    ("<.." "arrow" "none" "dotted")
    ("..>" "none" "arrow" "dotted")
    ("--" "none" "none" "solid")
    (".." "none" "none" "dotted")))

(defparameter +gm-max-class-op+ 4)

(defun gm-parse-class (src)
  (let* ((statements (gm-statements-of src))
         (kind (gm-header-kind statements)))
    (unless (and kind
                 (>= (length kind) (length "classdiagram"))
                 (string= kind "classdiagram"
                           :end1 (length "classdiagram")
                           :end2 (length "classdiagram")))
      (return-from gm-parse-class nil))
    (let ((graph (gm-make-graph))
          (infos (make-array 0 :adjustable t :fill-pointer 0))
          (cur-class nil))
      (labels ((sync ()
                 ;; Keep infos aligned with graph.nodes.
                 (loop while (< (length infos) (gm-graph-node-count graph))
                       do (vector-push-extend (gm-empty-class-info) infos)))
               (declare-class (name)
                 (prog1 (gm-node-index graph name nil "rect")
                   (sync))))
        (dolist (st (rest statements))
          (if cur-class
              (if (string= st "}")
                  (setf cur-class nil)
                  (gm-push-member (aref infos cur-class) st))
              (let ((first (gm-ascii-lower (gm-first-word st))))
                (cond ((string= first "direction")
                       (setf (gm-graph-dir graph)
                             (or (second (gm-words st)) "")))
                      ((member first '("note" "callback" "click" "link"
                                       "style" "cssclass" "classdef"
                                       "namespace" "}")
                               :test #'string=)
                       nil)
                      ((string= first "class")
                       (let* ((rest (gm-trim (subseq st (length "class"))))
                              (open (and (plusp (length rest))
                                         (char= (char rest (1- (length rest))) #\{)))
                              (name (if open
                                        (gm-trim (subseq rest 0 (1- (length rest))))
                                        rest)))
                         (when (or (string= name "") (gm-has-whitespace name))
                           (return-from gm-parse-class nil))
                         (let ((idx (declare-class name)))
                           (when (null idx)
                             (return-from gm-parse-class nil))
                           (when open
                             (setf cur-class idx)))))
                      ((and (>= (length st) 2)
                            (string= (subseq st 0 2) "<<"))
                       (let ((split (gm-split-once (subseq st 2) ">>")))
                         (unless split
                           (return-from gm-parse-class nil))
                         (let ((name (gm-trim (second split))))
                           (when (or (string= name "") (gm-has-whitespace name))
                             (return-from gm-parse-class nil))
                           (let ((idx (declare-class name)))
                             (when (null idx)
                               (return-from gm-parse-class nil))
                             (setf (getf (aref infos idx) :annotation)
                                   (gm-trim (first split)))))))
                      (t
                       (let ((rel (gm-parse-class-relation st)))
                         (if rel
                             (let ((f (declare-class (first rel)))
                                   (tgt (declare-class (second rel))))
                               (when (or (null f) (null tgt))
                                 (return-from gm-parse-class nil))
                               (when (>= (length (gm-graph-edges graph))
                                         +gm-max-edges+)
                                 (return-from gm-parse-class nil))
                               (vector-push-extend
                                (gm-make-edge :from f :to tgt :label (sixth rel)
                                              :head-to (fourth rel)
                                              :head-from (third rel)
                                              :line (fifth rel))
                                (gm-graph-edges graph)))
                             (let ((member (gm-split-once st ":")))
                               (if member
                                   (let ((id (gm-trim (first member)))
                                         (text (gm-trim (second member))))
                                     (when (or (string= id "") (gm-has-whitespace id)
                                               (string= text ""))
                                       (return-from gm-parse-class nil))
                                     (let ((idx (declare-class id)))
                                       (when (null idx)
                                         (return-from gm-parse-class nil))
                                       (gm-push-member (aref infos idx) text)))
                                   (return-from gm-parse-class nil))))))))))
        (if (zerop (gm-graph-node-count graph))
            nil
            (progn (sync) (list graph infos)))))))

;;; Add a member to the attribute or method compartment, eliding past the cap.
(defun gm-push-member (info raw)
  (if (and (>= (length raw) 2) (string= (subseq raw 0 2) "<<"))
      (let ((split (gm-split-once (subseq raw 2) ">>")))
        (when split
          (setf (getf info :annotation) (gm-trim (first split)))))
      (let* ((member (gm-decode-html-entities (gm-display-generics (gm-trim raw))))
             (key (if (find #\( member) :methods :attrs))
             (list (getf info key)))
        (cond ((< (length list) +gm-max-members+)
               (setf (getf info key) (append list (list member))))
              ((= (length list) +gm-max-members+)
               (setf (getf info key) (append list (list "…"))))))))

;;; Returns (from to head-from head-to line label) or NIL.
(defun gm-parse-class-relation (st)
  (let ((chars (gm-char-list st))
        (found nil))
    (block outer
      (loop for pos from 0 below (length chars)
            do (let* ((tail-end (min (length chars) (+ pos +gm-max-class-op+)))
                      (tail (gm-list-string (subseq chars pos tail-end))))
                 (dolist (entry +gm-class-ops+)
                   (let ((op (first entry)))
                     (when (and (>= (length tail) (length op))
                                (string= (subseq tail 0 (length op)) op))
                       ;; o is also an identifier character: skip a match
                       ;; glued to a name.
                       (let ((glued-l (and (char= (char op 0) #\o)
                                           (plusp pos)
                                           (gm-is-id-char (gm-char chars (1- pos)))))
                             (glued-r (and (char= (char op (1- (length op))) #\o)
                                           (< (+ pos (length op)) (length chars))
                                           (gm-is-id-char
                                            (gm-char chars (+ pos (length op)))))))
                         (unless (or glued-l glued-r)
                           (setf found (list pos op (second entry)
                                             (third entry) (fourth entry)))
                           (return-from outer)))))))))
    (unless found
      (return-from gm-parse-class-relation nil))
    (let* ((pos (first found))
           (op (second found))
           (lhs-raw (gm-trim (gm-list-string (subseq chars 0 pos))))
           (rhs-raw (gm-trim (gm-list-string (subseq chars (+ pos (length op))))))
           (lhs-card (gm-strip-cardinality-suffix lhs-raw))
           (lhs (first lhs-card))
           (card-from (second lhs-card))
           (rhs-card (gm-strip-cardinality-prefix rhs-raw))
           (rhs (first rhs-card))
           (card-to (second rhs-card))
           (split (gm-split-once rhs ":"))
           (to-id (gm-trim (if split (first split) rhs)))
           (rel-label (if split
                          (gm-non-empty
                           (gm-trim (gm-decode-html-entities (second split))))
                          nil)))
      (when (or (string= lhs "") (string= to-id "")
                (gm-has-whitespace lhs) (gm-has-whitespace to-id))
        (return-from gm-parse-class-relation nil))
      (let ((label (gm-non-empty
                    (gm-join-nonempty (list card-from (or rel-label "") card-to)
                                      " "))))
        (list lhs to-id (third found) (fourth found) (fifth found) label)))))

;;; Class "1" — a quoted cardinality trailing the left-hand name.
(defun gm-strip-cardinality-suffix (s)
  (let ((trimmed (gm-trim-end s)))
    (if (and (plusp (length trimmed))
             (char= (char trimmed (1- (length trimmed))) #\"))
        (let* ((rest (subseq trimmed 0 (1- (length trimmed))))
               (q (position #\" rest :from-end t)))
          (if q
              (list (gm-trim-end (subseq rest 0 q)) (subseq rest (1+ q)))
              (list trimmed "")))
        (list trimmed ""))))

;;; "0..*" Class — a quoted cardinality leading the right-hand name.
(defun gm-strip-cardinality-prefix (s)
  (let ((trimmed (gm-trim-start s)))
    (if (and (plusp (length trimmed)) (char= (char trimmed 0) #\"))
        (let* ((rest (subseq trimmed 1))
               (q (position #\" rest)))
          (if q
              (list (gm-trim-start (subseq rest (1+ q))) (subseq rest 0 q))
              (list trimmed "")))
        (list trimmed ""))))

;;; Mermaid writes generics as List~T~; show them as List<T>.
(defun gm-display-generics (s)
  (let ((out (make-string-output-stream))
        (open nil))
    (loop for c across s
          do (cond ((char= c #\~)
                    (write-char (if open #\> #\<) out)
                    (setf open (not open)))
                   (t (write-char c out))))
    (get-output-stream-string out)))

;;; ------------------------------------------------------------------------ ER
(defun gm-parse-er (src)
  (let* ((statements (gm-statements-of src))
         (kind (gm-header-kind statements)))
    (unless (string= kind "erdiagram")
      (return-from gm-parse-er nil))
    (let ((graph (gm-make-graph))
          (infos (make-array 0 :adjustable t :fill-pointer 0))
          (cur-entity nil))
      (labels ((sync ()
                 (loop while (< (length infos) (gm-graph-node-count graph))
                       do (vector-push-extend (gm-empty-class-info) infos)))
               (entity (token)
                 (let ((open (position #\[ token))
                       (idx nil))
                   (setf idx
                         (if open
                             (let ((id (subseq token 0 open))
                                   (label (gm-clean-label
                                           (gm-rstrip-brackets (subseq token (1+ open))))))
                               (if (or (string= id "") (string= label ""))
                                   nil
                                   (gm-node-label graph id label)))
                             (gm-node-index graph token nil "rect")))
                   (when idx (sync))
                   idx)))
        (dolist (st (rest statements))
          (if cur-entity
              (if (string= st "}")
                  (setf cur-entity nil)
                  (gm-push-er-attribute (aref infos cur-entity) st))
              (let ((rel (gm-split-er-relationship st)))
                (if rel
                    (let* ((tokens (gm-words (first rel)))
                           (op (if (= (length tokens) 3)
                                   (gm-parse-er-op (second tokens))
                                   nil)))
                      (unless op
                        (return-from gm-parse-er nil))
                      (let ((f (entity (first tokens)))
                            (tgt (entity (third tokens))))
                        (when (or (null f) (null tgt))
                          (return-from gm-parse-er nil))
                        (when (>= (length (gm-graph-edges graph)) +gm-max-edges+)
                          (return-from gm-parse-er nil))
                        (let* ((rel-label (if (null (second rel))
                                              ""
                                              (gm-clean-label (second rel))))
                               (label (gm-non-empty
                                       (gm-join-nonempty
                                        (list (getf op :card-l) rel-label
                                              (getf op :card-r))
                                        " "))))
                          (vector-push-extend
                           (gm-make-edge :from f :to tgt :label label
                                         :head-to "none" :head-from "none"
                                         :line (getf op :line))
                           (gm-graph-edges graph)))))
                    (let* ((open (and (plusp (length st))
                                      (char= (char st (1- (length st))) #\{)))
                           (decl (if open
                                     (gm-trim (subseq st 0 (1- (length st))))
                                     st)))
                      (when (or (string= decl "")
                                (not (= (length (gm-words decl)) 1)))
                        (return-from gm-parse-er nil))
                      (let ((idx (entity decl)))
                         (when (null idx)
                           (return-from gm-parse-er nil))
                         (when open
                           (setf cur-entity idx))))))))
         (if (zerop (gm-graph-node-count graph))
             nil
            (progn (sync) (list graph infos)))))))

(defun gm-split-er-relationship (st)
  (let* ((split (gm-split-once st ":"))
         (rel (if split (first split) st))
         (label (if split (gm-trim (second split)) nil)))
    (if (some (lambda (tok) (gm-parse-er-op tok)) (gm-words rel))
        (list rel label)
        nil)))

(defun gm-is-ascii (s)
  (loop for c across s
        always (<= (char-code c) #x7f)))

;;; A crow's-foot operator: two cardinality glyphs around -- or ...
(defun gm-parse-er-op (tok)
  (when (and (= (length tok) 6) (gm-is-ascii tok))
    (let* ((mid (subseq tok 2 4))
           (line (cond ((string= mid "--") "solid")
                       ((string= mid "..") "dotted")
                       (t nil))))
      (when line
        (let ((card-l (gm-er-card (subseq tok 0 2)))
              (card-r (gm-er-card (subseq tok 4 6))))
          (when (and card-l card-r)
            (list :card-l card-l :card-r card-r :line line)))))))

(defun gm-er-card (tok)
  (cond ((or (string= tok "|o") (string= tok "o|")) "0..1")
        ((string= tok "||") "1")
        ((or (string= tok "}o") (string= tok "o{")) "0..*")
        ((or (string= tok "}|") (string= tok "|{")) "1..*")
        (t nil)))

;;; ER attributes are `type name`; a trailing quoted comment is dropped.
(defun gm-push-er-attribute (info raw)
  (let ((parts nil))
    (dolist (tok (gm-words raw))
      (when (and (plusp (length tok)) (char= (char tok 0) #\"))
        (return))
      (push tok parts))
    (unless (null parts)
      (let ((line (gm-decode-html-entities
                   (gm-join-strings (nreverse parts) " ")))
            (attrs (getf info :attrs)))
        (cond ((< (length attrs) +gm-max-members+)
               (setf (getf info :attrs) (append attrs (list line))))
              ((= (length attrs) +gm-max-members+)
               (setf (getf info :attrs) (append attrs (list "…")))))))))

;;; ---------------------------------------------------------------- sequence
;;; Message operators, longest-first so -->> wins over -->.
(defparameter +gm-seq-ops+
  '(("-->>" t "arrow")
    ("->>" nil "arrow")
    ("--x" t "cross")
    ("-x" nil "cross")
    ("--)" t "arrow")
    ("-)" nil "arrow")
    ("-->" t "arrow")
    ("->" nil "arrow")))

(defparameter +gm-max-seq-op+ 4)

(defstruct (gm-seq (:constructor gm-make-seq))
  (labels (make-array 0 :adjustable t :fill-pointer 0))
  (index (make-hash-table :test 'equal))
  (items (make-array 0 :adjustable t :fill-pointer 0)))

(defun gm-seq-participant (seq id label)
  (let ((existing (gethash id (gm-seq-index seq))))
    (if existing
        (progn
          (when label
            (setf (aref (gm-seq-labels seq) existing) label))
          existing)
        (progn
          (when (>= (length (gm-seq-labels seq)) +gm-max-nodes+)
            (return-from gm-seq-participant nil))
          (setf (gethash id (gm-seq-index seq))
                (length (gm-seq-labels seq)))
          (vector-push-extend (or label id) (gm-seq-labels seq))
          (1- (length (gm-seq-labels seq)))))))

(defun gm-parse-sequence (src)
  (let* ((statements (gm-statements-of src))
         (kind (gm-header-kind statements)))
    (unless (string= kind "sequencediagram")
      (return-from gm-parse-sequence nil))
    (let ((seq (gm-make-seq))
          (autonumber nil)
          (msg-count 0)
          ;; One entry per open block; T when it draws a divider on `end`.
          (blocks nil))
      (dolist (st (rest statements))
        (let* ((first (gm-first-word st))
               (lower (gm-ascii-lower first)))
          (cond ((or (string= lower "participant") (string= lower "actor"))
                 (let* ((rest (gm-trim (subseq st (length first))))
                        (as (gm-split-once rest " as ")))
                   (when (string= rest "")
                     (return-from gm-parse-sequence nil))
                   (when (null (gm-seq-participant
                                seq
                                (gm-trim (if as (first as) rest))
                                (if as (gm-clean-label (second as)) nil)))
                     (return-from gm-parse-sequence nil))))
                ((string= lower "autonumber")
                 (setf autonumber t))
                ((member lower '("activate" "deactivate" "create" "destroy"
                                 "title" "acctitle" "accdescr" "links" "link"
                                 "properties")
                         :test #'string=)
                 nil)
                ((string= lower "note")
                 (let ((note (gm-parse-note-anchor
                              (gm-trim (subseq st (length first))) seq)))
                   (unless note
                     (return-from gm-parse-sequence nil))
                   (when (>= (length (gm-seq-items seq)) +gm-max-edges+)
                     (return-from gm-parse-sequence nil))
                   (vector-push-extend
                    (list :kind "note" :anchor (second note) :text (first note))
                    (gm-seq-items seq))))
                ((member lower '("loop" "alt" "opt" "par" "critical" "break"
                                 "else" "and" "option")
                         :test #'string=)
                 (if (member lower '("else" "and" "option") :test #'string=)
                     ;; A continuation only divides a block that opened one.
                     (when (and blocks (eq (car blocks) t))
                       (when (>= (length (gm-seq-items seq)) +gm-max-edges+)
                         (return-from gm-parse-sequence nil))
                       (vector-push-extend
                        (list :kind "divider" :text (gm-decode-html-entities st))
                        (gm-seq-items seq)))
                     (progn
                       (push t blocks)
                       (when (>= (length (gm-seq-items seq)) +gm-max-edges+)
                         (return-from gm-parse-sequence nil))
                       (vector-push-extend
                        (list :kind "divider" :text (gm-decode-html-entities st))
                        (gm-seq-items seq)))))
                ((or (string= lower "rect") (string= lower "box"))
                 (push nil blocks))
                ((string= lower "end")
                 (when (eq (pop blocks) t)
                   (when (>= (length (gm-seq-items seq)) +gm-max-edges+)
                     (return-from gm-parse-sequence nil))
                   (vector-push-extend (list :kind "divider" :text "end")
                                       (gm-seq-items seq))))
                (t
                 (let ((msg (gm-parse-seq-message st seq)))
                   (unless msg
                     (return-from gm-parse-sequence nil))
                   (let ((text (getf msg :text)))
                     (when autonumber
                       (incf msg-count)
                       (setf text (if (null text)
                                      (format nil "~D." msg-count)
                                      (format nil "~D. ~A" msg-count text))))
                     (when (>= (length (gm-seq-items seq)) +gm-max-edges+)
                       (return-from gm-parse-sequence nil))
                     (vector-push-extend
                      (list :kind "message" :from (getf msg :from)
                            :to (getf msg :to) :text text
                            :dashed (getf msg :dashed) :head (getf msg :head))
                      (gm-seq-items seq))))))))
      (if (zerop (length (gm-seq-labels seq))) nil seq))))

(defun gm-parse-note-anchor (rest seq)
  (let ((lower (gm-ascii-lower rest))
        (kind nil)
        (ids-and-text nil))
    (cond ((and (>= (length lower) (length "over "))
                (string= lower "over "
                          :end1 (length "over ")
                          :end2 (length "over ")))
           (setf kind "over")
           (setf ids-and-text (subseq rest (length "over "))))
          ((and (>= (length lower) (length "left of "))
                (string= lower "left of "
                          :end1 (length "left of ")
                          :end2 (length "left of ")))
           (setf kind "left")
           (setf ids-and-text (subseq rest (length "left of "))))
          ((and (>= (length lower) (length "right of "))
                (string= lower "right of "
                          :end1 (length "right of ")
                          :end2 (length "right of ")))
           (setf kind "right")
           (setf ids-and-text (subseq rest (length "right of "))))
          (t
           (return-from gm-parse-note-anchor nil)))
    (let ((split (gm-split-once ids-and-text ":")))
      (unless split
        (return-from gm-parse-note-anchor nil))
      (let* ((text (gm-decode-html-entities (gm-trim (second split))))
             (parts (remove-if (lambda (s) (string= s ""))
                               (mapcar (lambda (s) (gm-trim s))
                                       (uiop:split-string (first split)
                                                          :separator '(#\,)))))
             (a (if parts (gm-seq-participant seq (first parts) nil) nil)))
        (when (null a)
          (return-from gm-parse-note-anchor nil))
        (if (not (string= kind "over"))
            (list text (list :kind kind :at a))
            (let ((b a))
              (when (second parts)
                (let ((second-p (gm-seq-participant seq (second parts) nil)))
                  (when (null second-p)
                    (return-from gm-parse-note-anchor nil))
                  (setf b second-p)))
              (list text (list :kind "over" :from (min a b) :to (max a b)))))))))

;;; Returns (:from :to :text :dashed :head) or NIL.
(defun gm-parse-seq-message (st seq)
  (let ((chars (gm-char-list st))
        (found nil))
    (block outer
      (loop for pos from 0 below (length chars)
            do (let* ((tail-end (min (length chars) (+ pos +gm-max-seq-op+)))
                      (tail (gm-list-string (subseq chars pos tail-end))))
                 (dolist (entry +gm-seq-ops+)
                   (when (and (>= (length tail) (length (first entry)))
                              (string= (subseq tail 0 (length (first entry)))
                                       (first entry)))
                     (setf found (list pos (first entry) (second entry)
                                       (third entry)))
                     (return-from outer))))))
    (unless found
      (return-from gm-parse-seq-message nil))
    (let* ((pos (first found))
           (from-id (gm-trim (gm-list-string (subseq chars 0 pos)))))
      (when (string= from-id "")
        (return-from gm-parse-seq-message nil))
      ;; + / - activate and deactivate the target; no layout meaning.
      (let* ((rest (gm-lstrip-pluses
                    (gm-trim-start
                     (gm-list-string
                      (subseq chars (+ pos (length (second found))))))))
             (split (gm-split-once rest ":"))
             (to-id (gm-trim (if split (first split) rest)))
             (text (if split
                       (gm-non-empty
                        (gm-trim (gm-decode-html-entities (second split))))
                       nil)))
        (when (string= to-id "")
          (return-from gm-parse-seq-message nil))
        (let ((from (gm-seq-participant seq from-id nil)))
          (when (null from)
            (return-from gm-parse-seq-message nil))
          (let ((to (gm-seq-participant seq to-id nil)))
            (when (null to)
              (return-from gm-parse-seq-message nil))
            (list :from from :to to :text text
                  :dashed (third found) :head (fourth found))))))))

(defun gm-lstrip-pluses (s)
  (let ((start 0))
    (loop while (and (< start (length s))
                     (or (char= (char s start) #\+)
                         (char= (char s start) #\-)))
          do (incf start))
    (subseq s start)))
