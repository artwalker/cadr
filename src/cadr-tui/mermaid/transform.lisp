;;; packages/coding-agent/src/modes/interactive/components/mermaid.ts
;;;
;;; Top-level Mermaid fence transformer.  marked 18.0.5 lexes the markdown
;;; and only the top-level `code` tokens whose lang is mermaid are replaced.
;;; Nested fences (blockquote / list item) stay as source.  Two fallbacks:
;;; parse-failure / too-wide -> silent `token.raw`; non-streaming warnings ->
;;; source plus a warning-coloured code span.  Successful art is encoded as
;;; CommonMark code spans joined by markdown hard breaks.

(in-package #:cadr-tui)

(defparameter *mermaid-fences-scanner*
  ;; marked 18.0.5 rules.ts `fences`.  cl-ppcre handles the lookahead and
  ;; the backreference; Unicode property classes are not required here.
  (cl-ppcre:create-scanner
   "^ {0,3}(`{3,}(?=[^`\\n]*(?:\\n|$))|~{3,})([^\\n]*)(?:\\n|$)(?:|([\\s\\S]*?)(?:\\n|$))(?: {0,3}\\1[~`]* *(?=\\n|$)|$)"))

(defparameter *mermaid-space-scanner*
  ;; marked 18.0.5 rules.ts `newline`: /^(?:[ \t]*(?:\n|$))+/
  (cl-ppcre:create-scanner "^(?:[ \\t]*(?:\\n|$))+"))

(defparameter *mermaid-list-start-scanner*
  (cl-ppcre:create-scanner
   "^( {0,3}(?:[*+-]|\\d{1,9}[.)]))(?:[ \\t][^\\n]*)?(?:\\n|$)"))

(defparameter *mermaid-hr-scanner*
  (cl-ppcre:create-scanner
   "^ {0,3}((?:-[\\t ]*){3,}|(?:_[ \\t]*){3,}|(?:\\*[ \\t]*){3,})(?:\\n+|$)"))

(defparameter *mermaid-blockquote-line-scanner*
  (cl-ppcre:create-scanner "^ {0,3}>"))

(defun mermaid-mode-keyword (mode)
  (let ((text
          (string-downcase
           (if (stringp mode)
               mode
               (string mode)))))
    (cond
      ((string= text "off") :off)
      ((string= text "final") :final)
      (t :streaming))))

(defun mermaid-thinking-message-p (message-type)
  (or (eq message-type :assistant-thinking)
      (and (stringp message-type)
           (string= message-type "assistant-thinking"))))

(defun mermaid-should-skip-p (mode message-type streaming-p)
  (let ((mode (mermaid-mode-keyword mode)))
    (or (eq mode :off)
        (mermaid-thinking-message-p message-type)
        (and streaming-p (not (eq mode :streaming))))))

(defun mermaid-punct-or-symbol-p (character)
  ;; Unicode general categories whose names start with P or S
  ;; (punctuation and symbols).
  (let* ((category (sb-unicode:general-category character))
         (name (and category (symbol-name category))))
    (and (stringp name)
         (plusp (length name))
         (or (char= (char name 0) #\P)
             (char= (char name 0) #\S)))))

(defun mermaid-unescape-lang (lang)
  ;; marked: cap[2].trim().replace(/\\([\p{P}\p{S}])/gu, '$1')
  (let* ((trimmed (string-trim '(#\Space #\Tab) lang))
         (out (make-string-output-stream)))
    (loop with i = 0
          with n = (length trimmed)
          while (< i n)
          do (let ((ch (char trimmed i)))
               (if (and (char= ch #\\)
                        (< (1+ i) n)
                        (mermaid-punct-or-symbol-p (char trimmed (1+ i))))
                   (progn
                     (write-char (char trimmed (1+ i)) out)
                     (incf i 2))
                   (progn
                     (write-char ch out)
                     (incf i)))))
    (get-output-stream-string out)))

(defun mermaid-lang-p (lang)
  (when lang
    (let* ((normalized (mermaid-unescape-lang lang))
           (first (or (cl-ppcre:scan-to-strings "^\\S+" normalized)
                      "")))
      (string= (string-downcase first) "mermaid"))))

(defun mermaid-indent-code-compensation (raw text)
  ;; marked Tokenizer.indentCodeCompensation: only ``` fences whose raw
  ;; starts with whitespace, then peel that many leading spaces from each
  ;; content line that has at least as many.
  (multiple-value-bind (start end rs re)
      (cl-ppcre:scan "^(\\s+)(?:```)" raw)
    (declare (ignore end))
    (if (or (null start) (zerop (length text)))
        text
        (let* ((indent (subseq raw (aref rs 0) (aref re 0)))
               (n (length indent)))
          (with-output-to-string (out)
            (let ((pos 0)
                  (len (length text)))
              (loop while (<= pos len)
                    for nl = (position #\Newline text :start pos)
                    for line = (subseq text pos (or nl len))
                    for lead = (or (position-if-not
                                    (lambda (c)
                                      (member c '(#\Space #\Tab #\Page
                                                  #\Return #\Newline)))
                                    line)
                                   (length line))
                    do (if (>= lead n)
                           (write-string (subseq line n) out)
                           (write-string line out))
                       (when nl
                         (write-char #\Newline out))
                       (if nl
                           (setf pos (1+ nl))
                           (return)))))))))

(defun mermaid-leading-space-token (src)
  (multiple-value-bind (start end)
      (cl-ppcre:scan *mermaid-space-scanner* src)
    (when (and start (zerop start) (< start end))
      (subseq src start end))))

(defun mermaid-match-fence (src)
  "Return (values raw text lang) when SRC starts with a marked 18 fence."
  (multiple-value-bind (start end rs re)
      (cl-ppcre:scan *mermaid-fences-scanner* src)
    (when (and start (zerop start))
      (let* ((raw (subseq src start end))
             (lang (if (and rs (aref rs 1))
                       (subseq src (aref rs 1) (aref re 1))
                       ""))
             (text (if (and rs (> (length rs) 2) (aref rs 2))
                       (subseq src (aref rs 2) (aref re 2))
                       ""))
             (rest (subseq src end))
             (space (mermaid-leading-space-token rest)))
        ;; Lexer.ts:135-141 — a single-character newline spacer is folded
        ;; into the previous token's raw.
        (when (and space (= (length space) 1)
                   (char= (char space 0) #\Newline))
          (setf raw (concatenate 'string raw space)))
        (values raw
                (mermaid-indent-code-compensation raw text)
                lang)))))

(defun mermaid-next-line-end (src)
  (let ((nl (position #\Newline src)))
    (if nl
        (1+ nl)
        (length src))))

(defun mermaid-consume-blockquote (src)
  (let ((pos 0)
        (n (length src)))
    (loop while (< pos n)
          for line-end = (mermaid-next-line-end (subseq src pos))
          for line = (subseq src pos (+ pos line-end))
          do (unless (cl-ppcre:scan *mermaid-blockquote-line-scanner* line)
               (return))
             (incf pos line-end))
    (when (plusp pos)
      (subseq src 0 pos))))

(defun mermaid-indent-prefix-pattern (indent suffix)
  (let ((cache-index (max 0 (min 3 (1- indent)))))
    (concatenate 'string "^ {0," (write-to-string cache-index) "}" suffix)))

(defun mermaid-fences-begin-p (line indent)
  (and (cl-ppcre:scan
        (mermaid-indent-prefix-pattern indent "(?:```|~~~)")
        line)
       t))

(defun mermaid-heading-begin-p (line indent)
  (and (cl-ppcre:scan
        (mermaid-indent-prefix-pattern indent "#")
        line)
       t))

(defun mermaid-blockquote-begin-p (line indent)
  (and (cl-ppcre:scan
        (mermaid-indent-prefix-pattern indent ">")
        line)
       t))

(defun mermaid-next-bullet-p (line indent bull)
  (and (cl-ppcre:scan
        (mermaid-indent-prefix-pattern
         indent
         (concatenate 'string "(?:" bull ")(?:[ \t][^\n]*)?(?:\n|$)"))
        line)
       t))

(defun mermaid-first-nonspace (line)
  (or (position-if-not
       (lambda (c) (member c '(#\Space #\Tab)))
       line)
      (length line)))

(defun mermaid-consume-list (src)
  (multiple-value-bind (start end)
      (cl-ppcre:scan *mermaid-list-start-scanner* src)
    (declare (ignore end))
    (unless (and start (zerop start))
      (return-from mermaid-consume-list nil))
    (when (cl-ppcre:scan *mermaid-hr-scanner* src)
      (return-from mermaid-consume-list nil))
    (let* ((first (cl-ppcre:scan-to-strings
                   "^( {0,3}(?:[*+-]|\\d{1,9}[.)]))" src))
           (marker (string-trim '(#\Space) first))
           (ordered-p (> (length marker) 1))
           (bull (if ordered-p
                     (format nil "\\d{1,9}\\~A"
                             (char marker (1- (length marker))))
                     (format nil "\\~A" marker)))
           (item-re (cl-ppcre:create-scanner
                     (format nil "^( {0,3}~A)((?:[\\t ][^\\n]*)?(?:\\n|$))"
                             bull)))
           (pos 0)
           (raw-stream (make-string-output-stream)))
      (loop while (< pos (length src))
            for rest = (subseq src pos)
            do (when (cl-ppcre:scan *mermaid-hr-scanner* rest)
                 (loop-finish))
               (multiple-value-bind (istart iend irs ire)
                   (cl-ppcre:scan item-re rest)
                 (unless (and istart (zerop istart))
                   (loop-finish))
                 (let* ((item-raw (subseq rest istart iend))
                        (cap1 (subseq rest (aref irs 0) (aref ire 0)))
                        (cap2 (if (and irs (aref irs 1))
                                  (subseq rest (aref irs 1) (aref ire 1))
                                  ""))
                        (line (let ((nl (position #\Newline cap2)))
                                (if nl (subseq cap2 0 nl) cap2)))
                        (blank-p (zerop (length
                                         (string-trim '(#\Space #\Tab) line))))
                        (indent
                          (if blank-p
                              (1+ (length cap1))
                              (let ((idx (mermaid-first-nonspace line)))
                                (+ (length cap1)
                                   (if (> idx 4) 1 idx)))))
                        (cur-src (subseq rest iend))
                        (cur-raw
                          (with-output-to-string (cur-stream)
                            (write-string item-raw cur-stream)
                            (loop while (plusp (length cur-src))
                                  do (let* ((nl (position #\Newline cur-src))
                                            (raw-line (if nl
                                                          (subseq cur-src 0 nl)
                                                          cur-src))
                                            (next-line raw-line))
                                       (when (or (mermaid-fences-begin-p next-line indent)
                                                 (mermaid-heading-begin-p next-line indent)
                                                 (mermaid-blockquote-begin-p next-line indent)
                                                 (mermaid-next-bullet-p next-line indent bull)
                                                 (cl-ppcre:scan
                                                  *mermaid-hr-scanner*
                                                  (concatenate 'string next-line
                                                               (string #\Newline))))
                                         (loop-finish))
                                       (let ((nonspace (mermaid-first-nonspace next-line)))
                                         (when (and (plusp (length
                                                            (string-trim '(#\Space #\Tab)
                                                                         next-line)))
                                                    (< nonspace indent)
                                                    blank-p)
                                           (loop-finish)))
                                       (write-string raw-line cur-stream)
                                       (when nl (write-char #\Newline cur-stream))
                                       (setf cur-src
                                             (if nl (subseq cur-src (1+ nl)) ""))
                                       (setf blank-p
                                             (zerop (length
                                                     (string-trim '(#\Space #\Tab)
                                                                  next-line)))))))))
                   (incf pos (length cur-raw))
                   (write-string cur-raw raw-stream))))
      (let ((raw (get-output-stream-string raw-stream)))
        (when (plusp (length raw))
          (string-right-trim '(#\Newline #\Return #\Space #\Tab) raw))))))

(defun mermaid-lex-top-level (src)
  "Return a list of (:code raw text lang) or (:raw raw) top-level tokens."
  (let ((pos 0)
        (n (length src))
        (tokens nil))
    (loop while (< pos n)
          do (let ((rest (subseq src pos)))
               (multiple-value-bind (raw text lang)
                   (mermaid-match-fence rest)
                 (cond
                   (raw
                    (push (list :code raw text lang) tokens)
                    (incf pos (length raw)))
                   (t
                    (let ((bq (mermaid-consume-blockquote rest)))
                      (if bq
                          (progn
                            (push (list :raw bq) tokens)
                            (incf pos (length bq)))
                          (let ((lst (mermaid-consume-list rest)))
                            (if lst
                                (progn
                                  (push (list :raw lst) tokens)
                                  (incf pos (length lst)))
                                (let ((take (mermaid-next-line-end rest)))
                                  (when (zerop take)
                                    (loop-finish))
                                  (push (list :raw (subseq rest 0 take))
                                        tokens)
                                  (incf pos take)))))))))))
    (nreverse tokens)))

(defun mermaid-code-span (line)
  ;; mermaid.ts:19-36
  (let* ((content (if (plusp (length line))
                      line
                      (string (code-char #x00A0))))
         (longest 0)
         (run 0))
    (loop for ch across content
          do (if (char= ch #\`)
                 (progn
                   (incf run)
                   (setf longest (max longest run)))
                 (setf run 0)))
    (let* ((fence (make-string (1+ longest) :initial-element #\`))
           (padding (if (or (char= (char content 0) #\`)
                            (char= (char content (1- (length content))) #\`))
                        " "
                        "")))
      (concatenate 'string fence padding content padding fence))))

(defun mermaid-style-span (text cls &key (theme-p t))
  (if (not theme-p)
      text
      (ecase (intern (string-upcase cls) :keyword)
        (:border
         (theme-foreground :border-muted text :enabled-p t))
        (:text
         (theme-foreground :text text :enabled-p t))
        (:edge
         (theme-foreground :accent text :enabled-p t))
        (:edgelabel
         (theme-foreground :muted text :enabled-p t))
        (:title
         (theme-foreground
          :accent
          (theme-bold text :enabled-p t)
          :enabled-p t))
        (:none text))))

(defun mermaid-themed-lines (art &key (theme-p t))
  (if (not theme-p)
      (getf art :plain)
      (mapcar
       (lambda (row)
         (apply #'concatenate 'string
                (mapcar
                 (lambda (span)
                   (mermaid-style-span (first span) (second span)
                                       :theme-p t))
                 row)))
       (getf art :styled))))

(defun mermaid-warning-text (warnings)
  (let ((suffix
          (if (> (length warnings) 1)
              (format nil " (+~D more)" (1- (length warnings)))
              "")))
    (format nil "Mermaid diagram not rendered: ~A~A"
            (first warnings) suffix)))

(defun mermaid-transform-token (raw text available-width streaming-p
                                &key (theme-p t))
  (let ((art (ignore-errors (gm-render text))))
    (cond
      ((or (null art)
           (> (getf art :width) available-width))
       raw)
      ((and (not streaming-p) (getf art :warnings))
       (let* ((warning (mermaid-warning-text (getf art :warnings)))
              (styled (if theme-p
                          (theme-foreground :warning warning :enabled-p t)
                          warning)))
         (concatenate 'string raw (string #\Newline)
                      (mermaid-code-span styled)
                      "  " (string #\Newline))))
      (t
       (let ((lines (mermaid-themed-lines art :theme-p theme-p)))
         (concatenate 'string
                      (format nil "~{~A~^  ~%~}"
                              (mapcar #'mermaid-code-span lines))
                      (string #\Newline)))))))

(defun transform-mermaid-markdown
    (markdown &key (mode "streaming")
                   message-type
                   streaming-p
                   (available-width 80)
                   (theme-p t))
  "Replace top-level mermaid fences.  Baseline mermaid.ts:61-88."
  (when (or (null markdown)
            (zerop (length markdown))
            (mermaid-should-skip-p mode message-type streaming-p))
    (return-from transform-mermaid-markdown (or markdown "")))
  (with-output-to-string (out)
    (dolist (token (mermaid-lex-top-level markdown))
      (ecase (first token)
        (:raw
         (write-string (second token) out))
        (:code
         (destructuring-bind (raw text lang) (rest token)
           (write-string
            (if (mermaid-lang-p lang)
                (mermaid-transform-token
                 raw text available-width streaming-p
                 :theme-p theme-p)
                raw)
            out)))))))
