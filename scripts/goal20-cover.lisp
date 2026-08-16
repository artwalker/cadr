;;;; Goal 20 Part N (N2.7): full-tree sb-cover branch coverage measurement.
;;;; Diagnostic only, not a gate; do not wire into test-cl.sh or verify.sh.
;;;;
;;;; Mirrors scripts/test-cl.sh's asd registration and test-system order.
;;;; One deliberate deviation: no :force t. The wrapper points
;;;; ASDF_OUTPUT_TRANSLATIONS at a fresh empty cache, so every file is
;;;; compiled exactly once with coverage instrumentation. Recompiling a
;;;; file replaces its per-file sb-cover record, which would drop coverage
;;;; marks accumulated by earlier test suites.
;;;;
;;;; usage: scripts/goal20-cover.sh [output-directory]
;;;; direct:  CADR_COVER_ROOT=... CADR_COVER_OUT=... QUICKLISP_SETUP=... \
;;;;            sbcl --noinform --script scripts/goal20-cover.lisp
;;;;
;;;; sb-cover 2.6.7 internals used below (verified against
;;;; contrib/sb-cover/cover.lisp of the running SBCL and calibrated
;;;; against sb-cover:lcov-report on synthetic ground truth):
;;;;   sb-c::*code-coverage-info*    cons of EQUAL hashtable (namestring ->
;;;;                                 covered-file) and weak code vectors
;;;;   sb-cover::refresh-coverage-bits
;;;;   sb-cover::get-records         filename counts -> (path state . loc)*
;;;;   sb-cover::make-sample-count / ok-of / all-of
;;;;   sb-cover::unpack-pair         loc -> 0-based char start/end into the
;;;;                                 detabified source
;;;;   sb-cover::covered-file-lines  per-line length vector (for line math)
;;;;
;;;; Branch record states (4 bits: else-pair then-pair, 2 = not executed,
;;;; 1 = executed): #b1010 = neither way ever taken ("zero"), #b0110 /
;;;; #b1001 = one way taken ("partial"), #b0101 = both ways taken.

(require :asdf)
(require :sb-cover)

(defpackage #:cadr-goal20-cover
  (:use #:cl))

(in-package #:cadr-goal20-cover)

(defparameter *project-root*
  (uiop:ensure-directory-pathname
   (pathname
    (or (uiop:getenv "CADR_COVER_ROOT")
        (error "CADR_COVER_ROOT is not set")))))

(defparameter *output-directory*
  (uiop:ensure-directory-pathname
   (pathname
    (or (uiop:getenv "CADR_COVER_OUT")
        (error "CADR_COVER_OUT is not set")))))

(ensure-directories-exist *output-directory*)

(defparameter *src-prefix*
  (namestring
   (truename
    (merge-pathnames "src/" *project-root*))))

;;; The coverage policy must be proclaimed and the augmentation hook must
;;; be installed before anything under src/ is compiled.
(sb-cover:enable-coverage-logging)
(proclaim '(optimize sb-cover:store-coverage-data))

(let ((*load-verbose* nil)
      (*compile-verbose* nil))
  (load
   (or (uiop:getenv "QUICKLISP_SETUP")
       (error "QUICKLISP_SETUP is not set"))))

;;; Same asd registration order as scripts/test-cl.sh.
(dolist (name '("cadr-core.asd"
                "cadr-ai.asd"
                "cadr-agent.asd"
                "cadr-tui.asd"
                "cadr-cli.asd"
                "cadr-live-test-support.asd"
                "cadr-storage.asd"
                "cadr-server.asd"
                "cadr-evals.asd"
                "cadr-protocol.asd"))
  (asdf:load-asd (truename (merge-pathnames name *project-root*))))

;;; Same test-system order as scripts/test-cl.sh. No :force: the wrapper's
;;; ASDF_OUTPUT_TRANSLATIONS is a fresh empty cache, so each file compiles
;;; once with the coverage policy already in effect.
(defparameter *test-failures* '())

(format t "~&goal20-cover: running FiveAM suites (coverage instrumented)~%")
(dolist (system '("cadr-core"
                  "cadr-ai"
                  "cadr-agent"
                  "cadr-tui"
                  "cadr-cli"
                  "cadr-storage"
                  "cadr-server"
                  "cadr-evals"
                  "cadr-protocol"))
  (format t "~&goal20-cover: test-system ~a~%" system)
  (finish-output)
  (handler-case
      (asdf:test-system system)
    (error (condition)
      (push (cons system (princ-to-string condition)) *test-failures*)
      (format t "~&goal20-cover: test-system ~a signalled ~a~%"
              system condition)))
  (finish-output))

(format t "~&goal20-cover: extracting coverage data~%")

(sb-cover::refresh-coverage-bits)

(defun source-file-p (namestring)
  (and (uiop:string-prefix-p *src-prefix* namestring)
       (uiop:string-suffix-p namestring ".lisp")))

(defun file-package (namestring)
  "The ASDF system owning NAMESTRING, derived from the directory below src/."
  (let* ((relative (subseq namestring (length *src-prefix*)))
         (slash (position #\/ relative)))
    (if slash
        (subseq relative 0 slash)
        "?")))

(defun detabify (string)
  "Same tab expansion sb-cover applies before computing positions."
  (with-output-to-string (stream)
    (loop for char across string
          for col from 0
          for i from 0
          do (if (eql char #\Tab)
                 (loop repeat (- 8 (mod col 8))
                       do (write-char #\Space stream)
                       do (incf col))
                 (progn
                   (when (eql char #\Newline)
                     (when (eql i (1- (length string)))
                       (return))
                     (setf col -1))
                   (write-char char stream))))))

(defun slurp (namestring)
  (with-open-file (stream namestring :direction :input)
    (let ((string (make-string (file-length stream))))
      (sb-kernel:%shrink-vector string (read-sequence string stream))
      string)))

(defun tlf-display-name (form)
  (cond
    ((atom form) "toplevel-atom")
    ((symbolp (first form))
     (let ((operator (string-downcase (symbol-name (first form)))))
       (if (and (>= (length operator) 3)
                (string= "def" operator :end2 3)
                (second form))
           (format nil "~a ~{~a~^ ~}"
                   operator
                   (mapcar (lambda (part)
                             (string-downcase (princ-to-string part)))
                           (if (listp (second form))
                               (second form)
                               (list (second form)))))
           operator)))
    (t "toplevel-form")))

(defun tlf-ranges (source)
  "List of (start end name) for each top-level form in SOURCE.
START is the stream position before READ skips leading trivia, END the
position after the form, so the ranges partition the file."
  (handler-case
      (with-input-from-string (stream source)
        (loop with *package* = (find-package :cl-user)
              with *read-eval* = nil
              for start = (file-position stream)
              for form = (read stream nil :eof-marker)
              until (eq form :eof-marker)
              collect (list start (file-position stream)
                            (tlf-display-name form))))
    (error () nil)))

(defun find-tlf-name (ranges offset)
  (dolist (range ranges "?")
    (destructuring-bind (start end name) range
      (when (and (<= start offset) (< offset end))
        (return name)))))

(defun offset-line (source offset)
  "1-based line of the 0-based char OFFSET in SOURCE."
  (1+ (count #\Newline source :end (min offset (length source)))))

(defstruct file-row
  package
  relative
  (branch-ok 0)
  (branch-all 0)
  (expr-ok 0)
  (expr-all 0)
  (partial 0))

(defun emit-record-lines (filename out)
  "Write C/Z/P lines for FILENAME to OUT. Returns a FILE-ROW."
  (let* ((counts (list :branch (sb-cover::make-sample-count :branch)
                       :expression (sb-cover::make-sample-count :expression)))
         (records (sb-cover::get-records filename counts))
         (row (make-file-row
               :package (file-package filename)
               :relative (subseq filename (length *src-prefix*))
               :branch-ok (sb-cover::ok-of (getf counts :branch))
               :branch-all (sb-cover::all-of (getf counts :branch))
               :expr-ok (sb-cover::ok-of (getf counts :expression))
               :expr-all (sb-cover::all-of (getf counts :expression))))
         (source (detabify (slurp filename)))
         (ranges (tlf-ranges source)))
    (dolist (record records)
      (destructuring-bind (path state . loc) record
        (declare (ignore path))
        ;; Branch records carry both high bits; expression states are 1/2.
        (when (logtest state #b1100)
          (let* ((has-loc (and loc (not (eql loc 0))))
                 (start (if has-loc (sb-cover::unpack-pair loc) 0)))
            (cond
              ((eql state #b1010)
               (format out "Z	~a	~a	~a	~a~%"
                       (file-row-package row)
                       (file-row-relative row)
                       (if has-loc (offset-line source start) 0)
                       (if has-loc (find-tlf-name ranges start) "?")))
              ((member state '(#b0110 #b1001))
               (incf (file-row-partial row))
               (format out "P	~a	~a	~a	~a	~a~%"
                       (file-row-package row)
                       (file-row-relative row)
                       (if has-loc (offset-line source start) 0)
                       (if (eql state #b1001) "then-taken" "else-taken")
                       (if has-loc (find-tlf-name ranges start) "?"))))))))
    (format out "C	~a	~a	~a	~a	~a	~a	~a~%"
            (file-row-package row)
            (file-row-relative row)
            (file-row-branch-ok row)
            (file-row-branch-all row)
            (file-row-expr-ok row)
            (file-row-expr-all row)
            (file-row-partial row))
    row))

(defparameter *rows* '())

(let ((data-path (merge-pathnames "data.tsv" *output-directory*)))
  (with-open-file (out data-path :direction :output :if-exists :supersede)
    (let ((files '()))
      (maphash
       (lambda (filename file)
         (declare (ignore file))
         (when (source-file-p filename)
           (push filename files)))
       (car sb-c::*code-coverage-info*))
      (dolist (filename (sort files #'string<))
        (handler-case
            (push (emit-record-lines filename out) *rows*)
          (error (condition)
            (format t "~&goal20-cover: extraction failed for ~a: ~a~%"
                    filename condition))))))
  (format t "~&goal20-cover: wrote ~a (~d files)~%"
          (namestring data-path) (length *rows*)))

;;; Raw artifacts for later re-inspection without rerunning the suite.
(handler-case
    (sb-cover:save-coverage-in-file
     (merge-pathnames "coverage.dat" *output-directory*))
  (error (condition)
    (format t "~&goal20-cover: save-coverage-in-file failed: ~a~%" condition)))
(handler-case
    (sb-cover:lcov-report
     (merge-pathnames "coverage.lcov" *output-directory*))
  (error (condition)
    (format t "~&goal20-cover: lcov-report failed: ~a~%" condition)))

;;; Quick per-package totals for the log.
(format t "~&goal20-cover: per-package branch ways (taken/total)~%")
(let ((totals (make-hash-table :test 'equal)))
  (dolist (row *rows*)
    (let ((cell (or (gethash (file-row-package row) totals)
                    (setf (gethash (file-row-package row) totals)
                          (list 0 0 0 0 0)))))
      (incf (first cell) (file-row-branch-ok row))
      (incf (second cell) (file-row-branch-all row))
      (incf (third cell) (file-row-expr-ok row))
      (incf (fourth cell) (file-row-expr-all row))
      (incf (fifth cell) (file-row-partial row))))
  (maphash
   (lambda (package cell)
     (format t "  ~a: branch ~d/~d expr ~d/~d partial ~d~%"
             package
             (first cell) (second cell)
             (third cell) (fourth cell)
             (fifth cell)))
   totals))

(if *test-failures*
    (progn
      (format t "~&goal20-cover: ~d suite(s) failed:~%" (length *test-failures*))
      (dolist (failure *test-failures*)
        (format t "  ~a: ~a~%" (car failure) (cdr failure)))
      (sb-ext:exit :code 1))
    (format t "~&goal20-cover: all suites passed~%"))
(sb-ext:exit :code 0)
