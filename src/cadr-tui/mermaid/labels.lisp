;;; grok-mermaid@0.2.2 dist/labels.js:1-323 - direct port.
;;;
;;; Copyright 2023-2026 SpaceXAI
;;; Copyright 2026 Alexey Zaytsev
;;; Licensed under the Apache License, Version 2.0.
;;; This file is a Common Lisp port by the cadr authors; it is a
;;; modified version of the original work.  License text:
;;; docs/third-party/grok-mermaid-LICENSE.txt
;;;
;;; Label normalisation: ASCII case folding, control stripping, HTML entity
;;; decoding, markdown/tag stripping, wrapping and truncation.

(in-package #:cadr-tui)

(defparameter +gm-wrap-width+ 24)
(defparameter +gm-max-lines+ 4)
(defparameter +gm-max-label+ 28)
(defparameter +gm-label-break-chars+ (list #\_ #\- #\. #\/))

(defun gm-ascii-lower (s)
  (map 'string
       (lambda (c)
         (if (and (char>= c #\A) (char<= c #\Z))
             (code-char (+ (char-code c) 32))
             c))
       s))

(defun gm-ascii-upper (s)
  (map 'string
       (lambda (c)
         (if (and (char>= c #\a) (char<= c #\z))
             (code-char (- (char-code c) 32))
             c))
       s))

;;; C0 and C1 controls, less the \t\n\r the parsers and srcLines read.
(defun gm-control-p (c)
  (let ((v (char-code c)))
    (or (<= v #x08)
        (= v #x0b)
        (= v #x0c)
        (and (<= #x0e v #x1f))
        (and (<= #x7f v #x9f)))))

;;; Applied by every public entry point that takes untrusted source.
(defun gm-strip-controls (src)
  (remove-if #'gm-control-p src))

;;; Split source into lines the way Rust's str::lines() does: on \n, with a
;;; trailing \r stripped, and without a final empty line when the input ends
;;; in a newline.
(defun gm-src-lines (src)
  (let ((out (mapcar (lambda (l)
                       (if (and (plusp (length l))
                                (char= (char l (1- (length l))) #\Return))
                           (subseq l 0 (1- (length l)))
                           l))
                     (uiop:split-string src :separator '(#\Newline)))))
    (if (and out (equal (car (last out)) ""))
        (butlast out)
        out)))

;;; Matches Rust's char::is_alphanumeric.
(defun gm-is-alphanumeric (c)
  (or (sb-unicode:alphabetic-p c)
      (digit-char-p c 10)))

;;; Characters allowed in a bare node/state/class identifier.
(defun gm-is-id-char (c)
  (or (gm-is-alphanumeric c) (char= c #\_)))

(defparameter +gm-entity-lookahead+ 10)

(defun gm-decode-entity-body (body)
  (let ((named (cond ((string= body "lt") #\<)
                     ((string= body "gt") #\>)
                     ((string= body "amp") #\&)
                     ((string= body "quot") #\")
                     ((string= body "apos") #\'))))
    (when named (return-from gm-decode-entity-body named)))
  (unless (and (plusp (length body)) (char= (char body 0) #\#))
    (return-from gm-decode-entity-body nil))
  (let* ((num (subseq body 1))
         (hex (and (plusp (length num))
                   (or (char= (char num 0) #\x) (char= (char num 0) #\X))))
         (digits (if hex (subseq num 1) num))
         (ok (if hex
                 (and (plusp (length digits))
                      (every (lambda (c)
                               (or (and (char>= c #\0) (char<= c #\9))
                                   (and (char>= c #\a) (char<= c #\f))
                                   (and (char>= c #\A) (char<= c #\F))))
                             digits))
                 (and (plusp (length digits))
                      (every (lambda (c) (and (char>= c #\0) (char<= c #\9))) digits)))))
    (unless ok (return-from gm-decode-entity-body nil))
    (let ((code (parse-integer digits :radix (if hex 16 10))))
      (when (or (> code #x10ffff) (<= #xd800 code #xdfff))
        (return-from gm-decode-entity-body nil))
      (when (or (< code #x20) (<= #x7f code #x9f))
        (return-from gm-decode-entity-body nil))
      (code-char code))))

;;; Decode HTML entities in label text.  Called once per label.
(defun gm-decode-html-entities (s)
  (unless (find #\& s) (return-from gm-decode-html-entities s))
  (let* ((chars (coerce s 'list))
         (out (make-string-output-stream))
         (i 0)
         (len (length chars)))
    (loop while (< i len)
          do (let ((c (nth i chars)))
               (if (not (char= c #\&))
                   (progn (write-char c out) (incf i))
                   (let* ((hi (min (+ i 1 +gm-entity-lookahead+) len))
                          (semi -1))
                     (loop for j from (1+ i) below hi
                           when (char= (nth j chars) #\;)
                             do (setf semi j) (return))
                     (let ((decoded (if (= semi -1)
                                        nil
                                        (gm-decode-entity-body
                                         (coerce (subseq chars (1+ i) semi) 'string)))))
                       (if (null decoded)
                           (progn (write-char #\& out) (incf i))
                           (progn (write-string (string decoded) out)
                                  (setf i (1+ semi))))))))
          finally (return (get-output-stream-string out)))))

;;; String replace of every non-overlapping literal occurrence, left to right
;;; (JS String.prototype.replaceAll with a string pattern).
(defun gm-replace-all-literal (s pattern)
  (let ((plen (length pattern)))
    (if (zerop plen)
        s
        (let ((out (make-string-output-stream))
              (i 0)
              (len (length s)))
          (loop while (< i len)
                do (if (and (<= (+ i plen) len)
                            (string= pattern s :start2 i :end2 (+ i plen)))
                       (incf i plen)
                       (progn (write-char (char s i) out) (incf i))))
          (get-output-stream-string out)))))

;;; Whitespace test matching JS \s (WhiteSpace + LineTerminator).
(defun gm-whitespace-p (c)
  ;; sb-unicode:whitespace-p returns the code point (truthy) or NIL; JS \s
  ;; covers the same WhiteSpace+LineTerminator set.
  (not (null (sb-unicode:whitespace-p c))))

;;; Trim leading/trailing whitespace by the JS \s definition (not just ASCII).
(defun gm-trim (s)
  (let ((start 0)
        (end (length s)))
    (loop while (and (< start end) (gm-whitespace-p (char s start)))
          do (incf start))
    (loop while (and (< start end) (gm-whitespace-p (char s (1- end))))
          do (decf end))
    (subseq s start end)))

;;; Strip markdown emphasis from a `backtick` label string.
(defun gm-strip-markdown (s)
  (let* ((no-code (remove #\` s))
         (no-strong (gm-replace-all-literal
                     (gm-replace-all-literal no-code "**")
                     "__"))
         (chars (coerce no-strong 'list))
         (out (make-string-output-stream)))
    (loop for i from 0 below (length chars)
          for c = (nth i chars)
          for in-word = (and (plusp i)
                             (gm-is-alphanumeric (nth (1- i) chars))
                             (and (< (1+ i) (length chars))
                                  (gm-is-alphanumeric (nth (1+ i) chars))))
          do (if (and (or (char= c #\*) (char= c #\_)) (not in-word))
                 nil
                 (write-char c out)))
    (gm-trim (get-output-stream-string out))))

(defun gm-split-words (s)
  (let ((words nil)
        (cur nil))
    (loop for c across s
          do (if (gm-whitespace-p c)
                 (when cur
                   (push (coerce (nreverse cur) 'string) words)
                   (setf cur nil))
                 (push c cur)))
    (when cur (push (coerce (nreverse cur) 'string) words))
    (nreverse words)))

(defparameter +gm-html-format-tags+
  '("b" "strong" "i" "em" "u" "s" "strike" "del" "ins" "mark" "small" "big"
    "sub" "sup" "code" "kbd" "samp" "var" "tt" "span" "font" "q" "abbr"
    "cite" "pre"))

(defun gm-ascii-alnum-p (c)
  (or (and (char>= c #\0) (char<= c #\9))
      (and (char>= c #\a) (char<= c #\z))
      (and (char>= c #\A) (char<= c #\Z))))

;;; Read a tag starting at start, returning (values name end) or NIL.
(defun gm-html-tag-at (chars start)
  (let* ((i (1+ start))
         (len (length chars)))
    (when (and (< i len) (char= (nth i chars) #\/)) (incf i))
    (let ((name-start i))
      (loop while (and (< i len) (gm-ascii-alnum-p (nth i chars)))
            do (incf i))
      (when (= i name-start) (return-from gm-html-tag-at nil))
      (let ((name (coerce (subseq chars name-start i) 'string)))
        (loop while (and (< i len) (not (char= (nth i chars) #\>)))
              do (when (char= (nth i chars) #\<)
                   (return-from gm-html-tag-at nil))
                 (incf i))
        (if (and (< i len) (char= (nth i chars) #\>))
            (values name (1+ i))
            nil)))))

(defun gm-strip-html-tags (s)
  (let* ((chars (coerce s 'list))
         (out (make-string-output-stream))
         (i 0)
         (len (length chars)))
    (loop while (< i len)
          do (let ((c (nth i chars)))
               (if (char= c #\<)
                   (multiple-value-bind (name end)
                       (gm-html-tag-at chars i)
                     (if name
                         (let ((lower (gm-ascii-lower name)))
                           (cond ((string= lower "br")
                                  (write-char #\Space out)
                                  (setf i end))
                                 ((member lower +gm-html-format-tags+ :test #'string=)
                                  (setf i end))
                                 (t (write-char c out) (incf i))))
                         (progn (write-char c out) (incf i))))
                   (progn (write-char c out) (incf i)))))
    (get-output-stream-string out)))

;;; Strip one matching pair of wrapping delimiters, if present.
(defun gm-unwrap (s open close)
  (if (and (>= (length s) (+ (length open) (length close)))
           (string= open s :end2 (length open))
           (string= close s :start2 (- (length s) (length close))))
      (subseq s (length open) (- (length s) (length close)))
      nil))

;;; Normalise raw label text: strip markup, unquote, and decode entities.
(defun gm-clean-label (raw)
  (let* ((trimmed (gm-trim
                   (gm-strip-html-tags (gm-trim raw))))
         (unquoted (or (gm-unwrap trimmed "\"" "\"")
                       (gm-unwrap trimmed "'" "'")
                       trimmed))
         (unquoted (gm-trim unquoted))
         (md (gm-unwrap unquoted "`" "`")))
    (gm-decode-html-entities
     (if (null md)
         unquoted
         (gm-strip-markdown (gm-trim md))))))

;;; Index of the last identifier-boundary character, or -1.
(defun gm-last-break (s)
  (let ((best -1))
    (dolist (c +gm-label-break-chars+)
      (let ((p (position c s :from-end t)))
        (when (and p (> p best)) (setf best p))))
    best))

;;; Wrap a label to width columns over at most max-lines lines, truncating
;;; the last line with an ellipsis if it overflows.
(defun gm-wrap-label (label width max-lines)
  (setf width (max 1 width))
  (let ((lines nil)
        (cur "")
        (cur-w 0))
    (dolist (word (gm-split-words label))
      (let ((ww (gm-string-width word)))
        (cond ((> ww width)
               (unless (string= cur "")
                 (push cur lines)
                 (setf cur ""))
               (let ((chunk "")
                     (chunk-w 0))
                 (dolist (pair (gm-measured word))
                   (let ((ch (car pair)) (cw (cdr pair)))
                     (when (and (> (+ chunk-w cw) width) (not (string= chunk "")))
                       (let* ((p (gm-last-break chunk))
                               (carry (if (= p -1) "" (subseq chunk (1+ p)))))
                         (push (if (= p -1) chunk (subseq chunk 0 (1+ p))) lines)
                         (setf chunk carry)
                          (setf chunk-w (gm-string-width carry))))
                     (setf chunk (concatenate 'string chunk ch))
                     (incf chunk-w cw)))
                 (setf cur chunk)
                 (setf cur-w chunk-w)))
              ((string= cur "") (setf cur word) (setf cur-w ww))
              ((<= (+ cur-w 1 ww) width)
               (setf cur (concatenate 'string cur " " word))
               (incf cur-w (1+ ww)))
              (t (push cur lines)
                 (setf cur word)
                 (setf cur-w ww)))))
    (unless (string= cur "") (push cur lines))
    (when (null lines) (push "" lines))
    (setf lines (nreverse lines))
    (when (> (length lines) max-lines)
      (setf lines (subseq lines 0 max-lines))
      (let ((target (max 1 (1- width)))
            (sw 0)
            (s (with-output-to-string (stream)
                 (dolist (pair (gm-measured (car (last lines))))
                   (let ((ch (car pair)) (cw (cdr pair)))
                     (when (> (+ sw cw) target) (return))
                     (write-string ch stream)
                     (incf sw cw))))))
        (setf (car (last lines)) (concatenate 'string s "…"))))
    lines))

;;; Truncate to inner columns, leaving room for the ellipsis.
(defun gm-fit-label (label inner)
  (if (<= (gm-string-width label) inner)
      label
      (let ((used 0)
            (out (with-output-to-string (stream)
                   (dolist (pair (gm-measured label))
                     (let ((c (car pair)) (cw (cdr pair)))
                       (when (> (+ used cw 1) inner) (return))
                       (write-string c stream)
                       (incf used cw))))))
        (concatenate 'string out "…"))))
