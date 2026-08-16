;;;; Goal 20 Part N0: derive the cadr-side file:line mappings of
;;;; docs/source-parity.md from the loaded image instead of trusting
;;;; hand-maintained positions.
;;;;
;;;; The ledger's fourth column (Cadr mapping) carries entries of the form
;;;;   src/cadr-ai/model-data.lisp:148 validate-model-data-directory
;;;; The human contract is the symbol name; the file:line position is what
;;;; the image answers.  This script loads the nine production systems,
;;;; resolves every symbol entry through sb-introspect, converts the
;;;; definition's character offset to a line number, and diffs the derived
;;;; position against the ledger text.
;;;;
;;;; Files no production system loads (scripts/, test/, examples/) cannot be
;;;; answered by the image; for those the script falls back to a reader-based
;;;; textual scan of the entry's own file and marks the result :file-scan.
;;;; Entries whose descriptor is prose ("CLI", "ASDF serial image", line
;;;; ranges, slash compounds like login/refresh) carry no symbol and are
;;;; skipped and counted, not resolved.
;;;;
;;;; usage:
;;;;   sbcl --script scripts/derive-source-parity-mappings.lisp [--check]
;;;;   sbcl --script scripts/derive-source-parity-mappings.lisp --write
;;;;
;;;; --check (default) only reports.  Exit codes: 0 = every resolved entry
;;;; matches the ledger, 1 = drift found, 2 = at least one ledger symbol
;;;; could not be resolved (implementation gone or renamed).
;;;; --write splices the derived positions back into the ledger text,
;;;; leaving every other byte untouched.

(require :asdf)

(defparameter cl-user::*cadr-project-directory*
  (uiop:ensure-directory-pathname
   (pathname
    (or (uiop:getenv "CADR_PROJECT_DIRECTORY")
        (namestring
         (uiop:pathname-parent-directory-pathname
          (uiop:pathname-directory-pathname
           (truename *load-truename*))))))))

(let ((*standard-output* *error-output*)
      (*load-verbose* nil)
      (*compile-verbose* nil))
  (let ((setup
          (or (uiop:getenv "QUICKLISP_SETUP")
              (namestring
               (merge-pathnames "quicklisp/setup.lisp"
                                (user-homedir-pathname))))))
    (unless (probe-file setup)
      (error "Quicklisp setup not found: ~A" setup))
    (load setup))
  (dolist (name '("cadr-core.asd"
                  "cadr-ai.asd"
                  "cadr-agent.asd"
                  "cadr-tui.asd"
                  "cadr-cli.asd"
                  "cadr-storage.asd"
                  "cadr-protocol.asd"
                  "cadr-server.asd"
                  "cadr-evals.asd"
                  "cadr-live-test-support.asd"
                  "cadr-live-tests.asd"))
    (asdf:load-asd
     (truename
      (merge-pathnames name cl-user::*cadr-project-directory*))))
  (dolist (system '("cadr-core"
                    "cadr-ai"
                    "cadr-agent"
                    "cadr-tui"
                    "cadr-cli"
                    "cadr-storage"
                    "cadr-protocol"
                    "cadr-server"
                    "cadr-evals"))
    (asdf:load-system system :verbose nil))
  (require :sb-introspect))

(defpackage #:derive-source-parity-mappings
  (:use #:cl))

(in-package #:derive-source-parity-mappings)

(defparameter *root* cl-user::*cadr-project-directory*)
(defparameter *root-namestring* (namestring (truename *root*)))

(defparameter *production-system-packages*
  '("CADR-CORE" "CADR-AI" "CADR-AGENT" "CADR-TUI" "CADR-CLI" "CADR-STORAGE"
    "CADR-PROTOCOL" "CADR-SERVER" "CADR-EVALS"))

;;; ---------------------------------------------------------------------
;;; Ledger parsing
;;; ---------------------------------------------------------------------

(defstruct piece
  row              ; 1-based ledger line number
  pi-file          ; trimmed first-column pi path
  path             ; ledger cadr-side path text
  line             ; ledger line number (integer)
  range-end        ; integer when the entry is a :N-M range, else nil
  token            ; cleaned last word of the descriptor ("" when absent)
  single-word-p    ; t when the whole descriptor is exactly TOKEN
  span-start       ; line-relative start of the path:line / :line text
  span-end         ; line-relative end (exclusive)
  absolute-start   ; file-relative span start, for --write
  first-p)         ; t when the piece carries the path, nil for :N continuations

(defun split-lines-with-offsets (text)
  (let ((lines '())
        (start 0)
        (count (length text)))
    (dotimes (index count)
      (when (char= (char text index) #\Newline)
        (push (list (subseq text start index) start) lines)
        (setf start (1+ index))))
    (when (< start count)
      (push (list (subseq text start count) start) lines))
    (nreverse lines)))

(defun pipe-positions (line)
  (loop for index from 0 below (length line)
        when (char= (char line index) #\|)
        collect index))

(defun path-token-char-p (character)
  (or (alphanumericp character)
      (find character "/_.-")))

(defun mapping-path-p (token)
  (and (plusp (length token))
       (let ((dot (position #\. token :from-end t)))
         (and dot
              (member (subseq token (1+ dot)) '("lisp" "sexp" "asd" "py" "sh")
                      :test #'string=)
              (or (some (lambda (prefix)
                          (and (>= (length token) (length prefix))
                               (string= prefix token :end2 (length prefix))))
                        '("src/" "test/" "examples/" "scripts/"))
                  ;; root-level system definitions: cadr-ai.asd etc.
                  (and (not (find #\/ token))
                       (string= "asd" (subseq token (1+ dot)))))))))

(defun mapping-path-kind (path)
  (let ((dot (position #\. path :from-end t)))
    (cond
      ((and dot (string= "lisp" (subseq path (1+ dot)))) :lisp)
      ((and dot (string= "asd" (subseq path (1+ dot)))) :asd)
      (t :other))))

;;; Find the next piece boundary in the cell: a ';' ends the entry, and a
;;; ':' preceded by whitespace or a comma and followed by a digit is a
;;; same-path continuation ("...:21 foo, :98 bar").
(defun find-piece-boundary (line from end)
  (loop for index from from below end
        do (let ((character (char line index)))
             (cond
               ((char= character #\;)
                (return (values index :segment)))
               ((and (char= character #\:)
                     (< (1+ index) end)
                     (digit-char-p (char line (1+ index)))
                     (> index from)
                     (member (char line (1- index)) '(#\Space #\Tab #\,)))
                (return (values index :continuation)))))
        finally (return (values end :segment))))

(defun parse-integer-at (line start end)
  ;; Returns (values integer position-after-digits) or (values nil start).
  (let ((index start))
    (loop while (and (< index end) (digit-char-p (char line index)))
          do (incf index))
    (if (= index start)
        (values nil start)
        (values (parse-integer line :start start :end index) index))))

(defun whitespacep (character)
  (member character '(#\Space #\Tab #\Return)))

(defun clean-descriptor-token (descriptor)
  ;; The symbol an entry names is the last word of its descriptor.
  ;; Returns (values token single-word-p): the cleaned last word, and
  ;; whether the whole descriptor is exactly that word.  Continuation
  ;; splitting leaves a trailing "and" behind ("foo and :98 bar"), which
  ;; is stripped first.
  (let ((text (string-trim '(#\Space #\Tab #\,) descriptor)))
    (loop for length = (length text)
          while (and (> length 4)
                     (string-equal " and" text :start2 (- length 4)))
          do (setf text (string-trim '(#\Space #\Tab #\,)
                                     (subseq text 0 (- length 4)))))
    (let ((end (position-if-not #'whitespacep text :from-end t)))
      (if (null end)
          (values "" nil)
          (let ((start (1+ (or (position-if #'whitespacep text
                                            :end end
                                            :from-end t)
                               -1))))
            (values (string-trim '(#\` #\, #\. #\Space #\Tab)
                                 (subseq text start (1+ end)))
                    (and (zerop start)
                         (= (1+ end) (length text)))))))))

(defun parse-mapping-cell (line cell-start cell-end row pi-file line-start)
  (let ((pieces '())
        (index cell-start))
    (labels ((read-position (first-p path position-start)
               ;; position-start points at path[0] (first piece) or at ':'
               ;; (continuation).  Parses :N(-M)? and conses the piece.
               (let ((digits-start (1+ (position #\: line
                                                 :start position-start
                                                 :end cell-end))))
                 (multiple-value-bind (line-number after-digits)
                     (parse-integer-at line digits-start cell-end)
                   (unless line-number
                     (return-from read-position (values digits-start
                                                        :segment path)))
                   (let ((range-end nil)
                         (after after-digits))
                     (when (and (< after cell-end)
                                (char= (char line after) #\-)
                                (< (1+ after) cell-end)
                                (digit-char-p (char line (1+ after))))
                       (multiple-value-bind (value past)
                           (parse-integer-at line (1+ after) cell-end)
                         (setf range-end value
                               after past)))
                     (multiple-value-bind (boundary kind)
                         (find-piece-boundary line after cell-end)
                       (multiple-value-bind (token single-word-p)
                           (clean-descriptor-token
                            (subseq line after boundary))
                         (push (make-piece :row row
                                           :pi-file pi-file
                                           :path path
                                           :line line-number
                                           :range-end range-end
                                           :token token
                                           :single-word-p single-word-p
                                           :span-start position-start
                                           :span-end after
                                           :absolute-start (+ line-start
                                                              position-start)
                                           :first-p first-p)
                               pieces))
                       (values boundary kind path)))))))
      (loop while (< index cell-end)
            do (let ((character (char line index)))
                 (if (member character
                             '(#\; #\` #\, #\Space #\Tab #\*))
                     (incf index)
                     (let ((token-end index))
                       (loop while (and (< token-end cell-end)
                                        (path-token-char-p
                                         (char line token-end)))
                             do (incf token-end))
                       (let ((token (subseq line index token-end)))
                         (if (and (mapping-path-p token)
                                  (< token-end cell-end)
                                  (char= (char line token-end) #\:)
                                  (< (1+ token-end) cell-end)
                                  (digit-char-p (char line (1+ token-end))))
                             (multiple-value-bind (boundary kind path)
                                 (read-position t token index)
                               ;; follow same-path continuations
                               (loop while (eq kind :continuation)
                                     do (multiple-value-setq
                                            (boundary kind path)
                                          (read-position nil path boundary)))
                               (setf index boundary))
                             ;; prose segment: skip to the next entry
                             (let ((semi (position #\; line
                                                   :start token-end
                                                   :end cell-end)))
                               (setf index (or semi cell-end))))))))))
    (nreverse pieces)))

;;; ---------------------------------------------------------------------
;;; Token classification
;;; ---------------------------------------------------------------------

(defun classify-token (token)
  (cond
    ((zerop (length token)) :empty)
    ;; slash compounds ("login/refresh"), package syntax, quotes/parens and
    ;; non-ASCII are prose, never a single symbol name
    ((some (lambda (character)
             (or (> (char-code character) 127)
                 (find character "/:()\"#[]{}")))
           token)
     :prose)
    ((some (lambda (character) (find character "-*+<>=!$%&?~")) token)
     :symbol)
    (t :word)))

;;; ---------------------------------------------------------------------
;;; Image resolution
;;; ---------------------------------------------------------------------

(defparameter *definition-types*
  '(:function :generic-function :macro :compiler-macro :variable :constant
    :type :condition :structure :class :package :setf-expander
    :symbol-macro))

(defun cadr-package-p (package)
  (let ((name (package-name package)))
    (and (>= (length name) 4)
         (string= "CADR" name :end2 4))))

(defun cadr-packages ()
  (sort (remove-if-not #'cadr-package-p (list-all-packages))
        (lambda (a b)
          (let ((ia (position (package-name a) *production-system-packages*
                              :test #'string=))
                (ib (position (package-name b) *production-system-packages*
                              :test #'string=)))
            (cond ((and ia ib) (< ia ib))
                  (ia t)
                  (ib nil)
                  (t (string< (package-name a) (package-name b))))))))

(defparameter *cadr-packages* (cadr-packages))

(defun candidate-symbols (name)
  ;; Distinct symbols named NAME whose home package is a cadr package, in
  ;; canonical package order.
  (let ((found '()))
    (dolist (package *cadr-packages* (nreverse found))
      (multiple-value-bind (symbol status) (find-symbol name package)
        (when (and status
                   (symbol-package symbol)
                   (cadr-package-p (symbol-package symbol)))
          (pushnew symbol found))))))

(defun image-definition (symbol)
  (dolist (type *definition-types*)
    (let ((sources
            (handler-case
                (sb-introspect:find-definition-sources-by-name symbol type)
              (error () nil))))
      (when sources
        (return-from image-definition (values (first sources) type)))))
  (values nil nil))

(defun method-source-in-file (symbol entry-path)
  ;; A ledger entry that names a generic function means the method in the
  ;; entry's own file (one provider per file), not the DEFGENERIC.
  (when (fboundp symbol)
    (let ((function (fdefinition symbol)))
      (when (typep function 'generic-function)
        (dolist (method (sb-mop:generic-function-methods function))
          (let ((source
                  (handler-case
                      (sb-introspect:find-definition-source method)
                    (error () nil))))
            (when (and source
                       (sb-introspect:definition-source-pathname source)
                       (let ((relative
                               (repo-relative
                                (sb-introspect:definition-source-pathname
                                 source))))
                         (and relative (string= relative entry-path))))
              (return-from method-source-in-file source))))))))

;;; ---------------------------------------------------------------------
;;; File text cache, offset -> line, textual fallback scan
;;; ---------------------------------------------------------------------

(defparameter *file-texts* (make-hash-table :test #'equal))

(defun file-text (path)
  (let ((key (namestring path)))
    (multiple-value-bind (cached present-p) (gethash key *file-texts*)
      (if present-p
          cached
          (setf (gethash key *file-texts*)
                (handler-case
                    (uiop:read-file-string path :external-format :utf-8)
                  (error () nil)))))))

(defun offset-line (text offset)
  (1+ (count #\Newline text :end (min offset (length text)))))

(defun definition-start-offset (text offset)
  ;; SBCL records where reading the toplevel form began, which includes
  ;; leading blank and comment lines; advance past them to the form itself.
  (let ((index offset)
        (count (length text)))
    (loop
      (when (>= index count)
        (return index))
      (let ((character (char text index)))
        (cond
          ((member character
                   '(#\Space #\Tab #\Newline #\Return #\Page))
           (incf index))
          ((char= character #\;)
           (let ((newline (position #\Newline text :start index)))
             (if newline
                 (setf index (1+ newline))
                 (return count))))
          (t (return index)))))))

(defparameter *definition-heads*
  '("DEFUN" "DEFMACRO" "DEFGENERIC" "DEFMETHOD" "DEFVAR" "DEFPARAMETER"
    "DEFCONSTANT" "DEFSTRUCT" "DEFCLASS" "DEFINE-CONDITION" "DEFTYPE"
    "DEFPACKAGE" "SETF" "TEST" "DEF-SUITE"))

(defun definition-form-names-p (form name)
  (and (consp form)
       (symbolp (car form))
       (member (symbol-name (car form)) *definition-heads* :test #'string=)
       (let ((designator (cadr form)))
         (cond
           ((symbolp designator)
            (string= (symbol-name designator) name))
           ((stringp designator)
            (string-equal designator name))
           ;; (defstruct (name (:conc-prefix ...))) etc.
           ((and (consp designator) (symbolp (car designator)))
            (string= (symbol-name (car designator)) name))
           (t nil)))))

(defun textual-definition-line (path name)
  ;; Reader-based fallback for files no loaded system defines (scripts/,
  ;; test/, examples/) and for definitions whose recorded character offset
  ;; is NIL (variables, structures, classes).  Returns (values line status)
  ;; with status :found, :not-found or :read-error.  Nothing is evaluated.
  (let ((text (file-text path)))
    (if (null text)
        (values nil :not-found)
        (with-input-from-string (stream text)
          (when (and (> (length text) 1)
                     (char= (char text 0) #\#)
                     (char= (char text 1) #\!))
            (read-line stream))      ; shebang line of executable scripts
          (let ((*read-eval* nil)
                (*package* (find-package "CL-USER")))
            (loop
              (let ((position (file-position stream)))
                (let ((form (handler-case (read stream nil :eof)
                              (error () :read-error))))
                  (cond
                    ((eq form :eof) (return (values nil :not-found)))
                    ((eq form :read-error)
                     (return (values nil :read-error)))
                    ((definition-form-names-p form name)
                     (return (values (offset-line
                                      text
                                      (definition-start-offset text position))
                                     :found))))))))))))

;;; ---------------------------------------------------------------------
;;; Resolution
;;; ---------------------------------------------------------------------

(defstruct resolution
  status          ; :ok or :failed
  symbol
  type            ; sb-introspect definition type used
  path            ; repo-relative derived path
  line            ; derived line
  method          ; :image | :image+scan | :file-scan
  note)           ; ambiguity / failure detail string

(defparameter *resolution-cache* (make-hash-table :test #'equal))
(defparameter *textual-cache* (make-hash-table :test #'equal))

(defun cached-textual-line (full-path name)
  (let ((key (cons full-path name)))
    (multiple-value-bind (cached present-p) (gethash key *textual-cache*)
      (if present-p
          (values (first cached) (second cached))
          (multiple-value-bind (line status)
              (textual-definition-line full-path name)
            (setf (gethash key *textual-cache*) (list line status))
            (values line status))))))

(defun repo-relative (pathname)
  (handler-case
      (let ((relative (enough-namestring (truename pathname)
                                         *root-namestring*)))
        (and (plusp (length relative))
             (not (char= (char relative 0) #\/))
             (not (and (>= (length relative) 3)
                       (string= "../" relative :end2 3)))
             relative))
    (error () nil)))

(defun inferred-package-name (path)
  ;; src/cadr-ai/... -> "CADR-AI", and so on.  scripts/, test/, examples/
  ;; and root .asd files have no package of their own.
  (when (and (>= (length path) 4)
             (string= "src/" path :end2 4))
    (let ((slash (position #\/ path :start 4)))
      (when slash
        (let ((name (string-upcase (subseq path 4 slash))))
          (and (member name *production-system-packages* :test #'string=)
               name))))))

(defun resolve-image (candidates)
  ;; First candidate (ordered: inferred package, then canonical order)
  ;; that yields a definition source wins.
  (dolist (symbol candidates)
    (multiple-value-bind (source type) (image-definition symbol)
      (when source
        (return-from resolve-image (values symbol source type)))))
  (values nil nil nil))

(defun source-to-resolution (symbol source type ambiguous-note)
  (let ((pathname (sb-introspect:definition-source-pathname source))
        (offset (sb-introspect:definition-source-character-offset source)))
    (cond
      ((null pathname)
       (make-resolution :status :failed
                        :symbol symbol
                        :type type
                        :note "definition source has no pathname"))
      ((null (repo-relative pathname))
       (make-resolution :status :failed
                        :symbol symbol
                        :type type
                        :note (format nil "definition outside repo: ~A"
                                      (namestring pathname))))
      (t
       (let* ((relative (repo-relative pathname))
              (text (file-text (merge-pathnames relative *root*))))
         (cond
           ((null text)
            (make-resolution :status :failed
                             :symbol symbol
                             :type type
                             :note (format nil "derived file unreadable: ~A"
                                           relative)))
           ((integerp offset)
            (if (<= offset (length text))
                (make-resolution :status :ok
                                 :symbol symbol
                                 :type type
                                 :path relative
                                 :line (offset-line
                                        text
                                        (definition-start-offset text offset))
                                 :method :image
                                 :note ambiguous-note)
                (make-resolution
                 :status :failed
                 :symbol symbol
                 :type type
                 :note (format nil
                               "character offset ~D beyond file length ~D (stale fasl?)"
                               offset (length text)))))
           (t
            ;; Variables/structures/classes record the pathname but a NIL
            ;; offset; locate the defining form textually in the same file.
            (multiple-value-bind (line scan-status)
                (cached-textual-line
                 (namestring (merge-pathnames relative *root*))
                 (symbol-name symbol))
              (if (eq scan-status :found)
                  (make-resolution :status :ok
                                   :symbol symbol
                                   :type type
                                   :path relative
                                   :line line
                                   :method :image+scan
                                   :note ambiguous-note)
                  (make-resolution
                   :status :failed
                   :symbol symbol
                   :type type
                   :note (format nil
                                 "NIL character offset and textual scan of ~A ~A"
                                 relative
                                 (if (eq scan-status :read-error)
                                     "hit a reader error"
                                     "found no defining form"))))))))))))

(defun resolve-entry (token entry-path)
  (let* ((name (string-upcase token))
         (inferred (inferred-package-name entry-path))
         ;; The entry path is part of the key: for a generic function the
         ;; answer is the method in the entry's own file.
         (key (list name inferred entry-path)))
    (multiple-value-bind (cached present-p) (gethash key *resolution-cache*)
      (when present-p
        (return-from resolve-entry cached))
      (let* ((all (candidate-symbols name))
             (ordered (if (and inferred (find-package inferred))
                          (stable-sort
                           (copy-list all)
                           (lambda (a b)
                             (declare (ignore b))
                             (string= (package-name (symbol-package a))
                                      inferred)))
                          all))
             (ambiguous-packages
               (when (> (length all) 1)
                 (mapcar (lambda (symbol)
                           (package-name (symbol-package symbol)))
                         all))))
        (multiple-value-bind (symbol source type) (resolve-image ordered)
          (let ((resolution
                  (cond
                    (source
                     ;; Entries point at methods, not the DEFGENERIC: when the
                     ;; name is generic and lands in another file, prefer the
                     ;; method defined in the entry's own file.
                     (let ((chosen source)
                           (chosen-type type))
                       (let ((pathname
                               (sb-introspect:definition-source-pathname
                                source)))
                         (when pathname
                           (let ((relative (repo-relative pathname)))
                             (when (and relative
                                        (not (string= relative entry-path)))
                               (let ((method-source
                                       (method-source-in-file symbol
                                                              entry-path)))
                                 (when method-source
                                   (setf chosen method-source
                                         chosen-type :method)))))))
                       (source-to-resolution
                        symbol chosen chosen-type
                        (when ambiguous-packages
                          (format nil "ambiguous: ~{~A~^, ~} (used ~A)"
                                  ambiguous-packages
                                  (package-name (symbol-package symbol)))))))
                    ;; No loaded system defines the name.  Files outside the
                    ;; production image can still answer textually.
                    ((some (lambda (prefix)
                             (and (>= (length entry-path) (length prefix))
                                  (string= prefix entry-path
                                           :end2 (length prefix))))
                           '("scripts/" "test/" "examples/"))
                     (let ((full (merge-pathnames entry-path *root*)))
                       (if (null (file-text full))
                           (make-resolution
                            :status :failed
                            :note (format nil
                                          "~A names no symbol in the loaded image; ledger path ~A does not exist on disk"
                                          name entry-path))
                           (multiple-value-bind (line scan-status)
                               (cached-textual-line (namestring full) name)
                             (case scan-status
                               (:found
                                (make-resolution :status :ok
                                                 :path entry-path
                                                 :line line
                                                 :method :file-scan))
                               (:read-error
                                (make-resolution
                                 :status :failed
                                 :note (format nil
                                               "~A not in image; reader error while scanning ~A"
                                               name entry-path)))
                               (t
                                (make-resolution
                                 :status :failed
                                 :note (format nil
                                               "~A not in image; no defining form in ~A"
                                               name entry-path))))))))
                    (t
                     (make-resolution
                      :status :failed
                      :note (format nil
                                    "~A names no symbol in any loaded cadr package"
                                    name))))))
            (setf (gethash key *resolution-cache*) resolution)))))))

;;; ---------------------------------------------------------------------
;;; Report
;;; ---------------------------------------------------------------------

(defparameter *ledger-line-count* 0)
(defparameter *data-rows* 0)
(defparameter *non-data-rows* 0)
(defparameter *rows-with-pieces* 0)
(defparameter *pieces* 0)
(defparameter *resolved* 0)
(defparameter *resolved-image* 0)
(defparameter *resolved-image-scan* 0)
(defparameter *resolved-file-scan* 0)
(defparameter *matched* 0)
(defparameter *drifted* 0)
(defparameter *failed* 0)
(defparameter *skipped* (make-hash-table :test #'eq))
(defparameter *ambiguous* 0)
(defparameter *drift-records* '())
(defparameter *failure-records* '())
(defparameter *edits* '())

(defparameter *skip-reason-order*
  '(:line-range :non-lisp-path :asd-entry :no-symbol :prose))

(defun record-skip (reason)
  (incf (gethash reason *skipped* 0)))

(defun piece-flags (piece resolution)
  (let ((flags '()))
    (when (not (string= (piece-path piece) (resolution-path resolution)))
      (push "moved" flags))
    (unless (probe-file (merge-pathnames (piece-path piece) *root*))
      (push "ledger-path-missing" flags))
    (when (eq (resolution-method resolution) :file-scan)
      (push "file-scan" flags))
    (when (eq (resolution-method resolution) :image+scan)
      (push "scan-line" flags))
    (nreverse flags)))

(defun process-piece (piece)
  (incf *pieces*)
  (let ((kind (mapping-path-kind (piece-path piece))))
    (cond
      ((piece-range-end piece)
       (record-skip :line-range))
      ((eq kind :asd)
       (record-skip :asd-entry))
      ((not (eq kind :lisp))
       (record-skip :non-lisp-path))
      (t
       (case (classify-token (piece-token piece))
         (:empty (record-skip :no-symbol))
         (:prose (record-skip :prose))
         (:word
          ;; A bare word is a symbol only when it is the entire descriptor
          ;; and the inferred package owns a symbol that actually has a
          ;; definition; otherwise it is English ("port", "row", "wiring").
          (let ((inferred (inferred-package-name (piece-path piece))))
            (multiple-value-bind (symbol status)
                (and (piece-single-word-p piece)
                     inferred
                     (find-package inferred)
                     (find-symbol (string-upcase (piece-token piece))
                                  (find-package inferred)))
              (if (and status
                       (symbol-package symbol)
                       (cadr-package-p (symbol-package symbol))
                       (image-definition symbol))
                  (resolve-and-compare piece)
                  (record-skip :prose)))))
         (:symbol
          (resolve-and-compare piece)))))))

(defun resolve-and-compare (piece)
  (let ((resolution (resolve-entry (piece-token piece) (piece-path piece))))
    (when (and (resolution-note resolution)
               (search "ambiguous" (resolution-note resolution)))
      (incf *ambiguous*))
    (if (eq (resolution-status resolution) :failed)
        (progn
          (incf *failed*)
          (push (list piece resolution) *failure-records*))
        (progn
          (incf *resolved*)
          (ecase (resolution-method resolution)
            (:image (incf *resolved-image*))
            (:image+scan (incf *resolved-image-scan*))
            (:file-scan (incf *resolved-file-scan*)))
          (if (and (string= (piece-path piece) (resolution-path resolution))
                   (= (piece-line piece) (resolution-line resolution)))
              (incf *matched*)
              (progn
                (incf *drifted*)
                (push (list piece resolution (piece-flags piece resolution))
                      *drift-records*)
                (push (list (piece-absolute-start piece)
                            (+ (piece-absolute-start piece)
                               (- (piece-span-end piece)
                                  (piece-span-start piece)))
                            (if (and (not (piece-first-p piece))
                                     (string= (piece-path piece)
                                              (resolution-path resolution)))
                                (format nil ":~D" (resolution-line resolution))
                                (format nil "~A:~D"
                                        (resolution-path resolution)
                                        (resolution-line resolution))))
                      *edits*)))))))

(defun analyze-ledger (text)
  (dolist (line+offset (split-lines-with-offsets text))
    (destructuring-bind (line line-start) line+offset
      (incf *ledger-line-count*)
      (when (and (>= (length line) 12)
                 (string= "| `packages/" line :end2 12))
        (let ((pipes (pipe-positions line)))
          (if (< (length pipes) 7)
              (incf *non-data-rows*)
              (progn
                (incf *data-rows*)
                (let* ((cell-start (1+ (nth 3 pipes)))
                       (cell-end (nth 4 pipes))
                       (pi-file (string-trim
                                 '(#\Space #\Tab #\`)
                                 (subseq line (1+ (nth 0 pipes))
                                         (nth 1 pipes))))
                       (pieces (parse-mapping-cell line cell-start cell-end
                                                   *ledger-line-count*
                                                   pi-file line-start)))
                  (when pieces
                    (incf *rows-with-pieces*))
                  (mapc #'process-piece pieces)))))))))

(defun print-report (stream)
  (format stream "~&derive-source-parity-mappings dry-run~%")
  (format stream "ledger lines: ~D  data rows: ~D  non-data rows skipped: ~D  rows with mapping entries: ~D~%"
          *ledger-line-count* *data-rows* *non-data-rows* *rows-with-pieces*)
  (format stream "entries (path:line pieces): ~D~%" *pieces*)
  (format stream "  resolved: ~D (image: ~D, image+scan: ~D, file-scan: ~D)~%"
          *resolved* *resolved-image* *resolved-image-scan*
          *resolved-file-scan*)
  (format stream "    in sync with ledger: ~D~%" *matched*)
  (format stream "    drifted: ~D~%" *drifted*)
  (format stream "  unresolved (hard failure): ~D~%" *failed*)
  (format stream "  ambiguous names (resolved, note attached): ~D~%"
          *ambiguous*)
  (format stream "  skipped: ~D~%"
          (loop for reason being the hash-keys of *skipped*
                using (hash-value count)
                sum count))
  (dolist (reason *skip-reason-order*)
    (when (gethash reason *skipped*)
      (format stream "    ~A: ~D~%" reason (gethash reason *skipped*))))
  (format stream "~%== drift (~D) ==~%" *drifted*)
  (dolist (record (nreverse *drift-records*))
    (destructuring-bind (piece resolution flags) record
      (format stream "L~D  ~A:~D -> ~A:~D  ~A  (~A)~@[  [~{~A~^ ~}]~]~@[  note: ~A~]~%"
              (piece-row piece)
              (piece-path piece) (piece-line piece)
              (resolution-path resolution) (resolution-line resolution)
              (piece-token piece)
              (piece-pi-file piece)
              flags
              (resolution-note resolution))))
  (format stream "~%== unresolved (~D) ==~%" *failed*)
  (dolist (record (nreverse *failure-records*))
    (destructuring-bind (piece resolution) record
      (format stream "L~D  ~A:~D  ~A  (~A)~%    ~A~%"
              (piece-row piece)
              (piece-path piece) (piece-line piece)
              (piece-token piece)
              (piece-pi-file piece)
              (resolution-note resolution)))))

;;; ---------------------------------------------------------------------
;;; --write
;;; ---------------------------------------------------------------------

(defun apply-edits (text)
  (let ((sorted (sort (copy-list *edits*) #'> :key #'first))
        (result text))
    (dolist (edit sorted)
      (destructuring-bind (start end replacement) edit
        (setf result
              (concatenate 'string
                           (subseq result 0 start)
                           replacement
                           (subseq result end)))))
    result))

(defun write-ledger (text)
  (let ((updated (apply-edits text)))
    (if (string= updated text)
        (format *error-output* "~&no positions needed rewriting~%")
        (let ((path (merge-pathnames "docs/source-parity.md" *root*)))
          (with-open-file (stream path
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :error
                                  :external-format :utf-8)
            (write-string updated stream))
          (format *error-output* "~&rewrote ~D position~:P in ~A~%"
                  (length *edits*)
                  (enough-namestring path *root-namestring*))))))

;;; ---------------------------------------------------------------------

(defun main (arguments)
  (let ((mode :check))
    (dolist (argument arguments)
      (cond
        ((string= argument "--check") (setf mode :check))
        ((string= argument "--write") (setf mode :write))
        ((string= argument "--gate") (setf mode :gate))
        (t
         (format *error-output* "Unknown option: ~A~%" argument)
         (format *error-output*
                 "usage: sbcl --script scripts/derive-source-parity-mappings.lisp [--check|--gate|--write]~%")
         (sb-ext:exit :code 64))))
    (let* ((ledger-path (merge-pathnames "docs/source-parity.md" *root*))
           (text (uiop:read-file-string ledger-path :external-format :utf-8)))
      (analyze-ledger text)
      (print-report *standard-output*)
      (when (eq mode :write)
        (write-ledger text))
      ;; --gate fails only on unresolvable symbols or missing paths (the
      ;; 108-class defect); line drift is reported but does not fail, and
      ;; is healed by explicit --write runs.  --check also fails on drift.
      (sb-ext:exit
       :code (cond ((plusp *failed*) 2)
                   ((and (eq mode :check) (plusp *drifted*)) 1)
                   (t 0))))))

(main (uiop:command-line-arguments))
