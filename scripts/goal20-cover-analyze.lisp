;;;; Re-analyze goal20 coverage from the saved state file, without
;;;; rerunning the suite. Restores coverage.dat (written by
;;;; scripts/goal20-cover.lisp), rebuilds source locations via sb-cover's
;;;; own source-map machinery, and emits per-branch-record lines plus a
;;;; per-toplevel-form "called" flag:
;;;;   B <package> <relative> <tlf-index> <state> <line>
;;;;   T <package> <relative> <tlf-index> <branch-deciding form text>
;;;;   F <package> <relative> <tlf-index> <called 0|1> <tlf-name>
;;;;
;;;; usage: CADR_COVER_ROOT=... CADR_COVER_OUT=... QUICKLISP_SETUP=... \
;;;;          sbcl --noinform --script scripts/goal20-cover-analyze.lisp
(require :asdf)
(require :sb-cover)

(defpackage #:cadr-goal20-cover-analyze (:use #:cl))
(in-package #:cadr-goal20-cover-analyze)

(defparameter *root*
  (uiop:ensure-directory-pathname
   (pathname (or (uiop:getenv "CADR_COVER_ROOT") "/root/projects/cadr/"))))
(defparameter *out*
  (uiop:ensure-directory-pathname
   (pathname (or (uiop:getenv "CADR_COVER_OUT") "/tmp/goal20-cover/"))))
(defparameter *src-prefix*
  (namestring (truename (merge-pathnames "src/" *root*))))

;;; Package-qualified symbols in the sources must READ during the source
;;; map rebuild below, so the production packages must exist in this
;;; image. Load the systems (uninstrumented; loading adds no coverage
;;; records and does not touch the restored per-file bits).
(let ((*load-verbose* nil)
      (*compile-verbose* nil))
  (load (or (uiop:getenv "QUICKLISP_SETUP") "/root/quicklisp/setup.lisp")))
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
  (asdf:load-asd (truename (merge-pathnames name *root*))))
(dolist (system '("cadr-core" "cadr-ai" "cadr-agent" "cadr-tui" "cadr-cli"
                  "cadr-storage" "cadr-server" "cadr-evals" "cadr-protocol"))
  (asdf:load-system system :verbose nil))

(sb-cover:restore-coverage-from-file (merge-pathnames "coverage.dat" *out*))

(defun file-package (namestring)
  (let* ((relative (subseq namestring (length *src-prefix*)))
         (slash (position #\/ relative)))
    (if slash (subseq relative 0 slash) "?")))

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

(defun offset-line (source offset)
  (1+ (count #\Newline source :end (min offset (length source)))))

(defun plain-read-forms (source)
  (handler-case
      (with-input-from-string (stream source)
        (loop with *package* = (find-package :cl-user)
              with *read-eval* = nil
              for form = (read stream nil :eof-marker)
              until (eq form :eof-marker)
              collect form))
    (error () nil)))

(let ((files '()))
  (maphash
   (lambda (filename file)
     (declare (ignore file))
     (when (and (uiop:string-prefix-p *src-prefix* filename)
                (uiop:string-suffix-p filename ".lisp"))
       (push filename files)))
   (car sb-c::*code-coverage-info*))
  (with-open-file (out (merge-pathnames "analyze.tsv" *out*)
                       :direction :output :if-exists :supersede)
    (dolist (filename (sort files #'string<))
      (handler-case
          (let* ((package (file-package filename))
                 (relative (subseq filename (length *src-prefix*)))
                 (source (sb-cover::read-source filename :default))
                 (maps (sb-cover::read-and-record-source-maps source))
                 (counts (list :branch (sb-cover::make-sample-count :branch)
                               :expression
                               (sb-cover::make-sample-count :expression)))
                 (records (sb-cover::get-records filename counts))
                 ;; tlf-index -> executed-anywhere-below-the-toplevel-p
                 (called (make-hash-table)))
            ;; A tlf "was called" if any record strictly below the
            ;; toplevel form executed. The toplevel record itself
            ;; (path length 1) executes at load time and proves nothing.
            (dolist (record records)
              (destructuring-bind (path state . loc) record
                (declare (ignore loc))
                (when (and (> (length path) 1)
                           (not (logtest state #b1100))
                           (eql state 1))
                  (setf (gethash (car (last path)) called) t))))
            ;; Branch lines, with locations rebuilt from source maps.
            (dolist (record records)
              (destructuring-bind (path state . loc) record
                (declare (ignore loc))
                (when (logtest state #b1100)
                  (let* ((rpath (reverse path))
                         (tlf-index (car rpath))
                         (tlf (nth tlf-index maps))
                         (start
                           (when tlf
                             (multiple-value-bind (s e)
                                 (sb-cover::source-path-source-position
                                  (cons 0 (cdr rpath))
                                  (car tlf) (cdr tlf))
                               (declare (ignore e))
                               s))))
                    (format out "B	~a	~a	~a	~a	~a~%"
                            package relative tlf-index state
                            (if start (offset-line source start) 0))
                    ;; For never-executed branches also dump the text of
                    ;; the branch-deciding form, whitespace-collapsed.
                    (when (and (eql state 10) start)
                      (let ((text (with-output-to-string (chars)
                                    (loop with in-space = t
                                          for i from start
                                          below (min (length source)
                                                     (+ start 160))
                                          for ch = (char source i)
                                          do (if (or (eql ch #\Newline)
                                                     (eql ch #\Space)
                                                     (eql ch #\Tab))
                                                 (unless in-space
                                                   (write-char #\Space chars)
                                                   (setf in-space t))
                                                 (progn
                                                   (write-char ch chars)
                                                   (setf in-space nil)))))))
                        (format out "T	~a	~a	~a	~a~%"
                                package relative tlf-index text)))))))
            (dotimes (tlf-index (length maps))
              (format out "F	~a	~a	~a	~a	~a~%"
                      package relative tlf-index
                      (if (gethash tlf-index called) 1 0)
                      ;; The forms inside MAPS have their atoms replaced
                      ;; by sb-cover's recording monikers, so names come
                      ;; from a plain re-read of the same source; both
                      ;; readers index toplevel forms identically.
                      (let ((plain (plain-read-forms source)))
                        (if (< tlf-index (length plain))
                            (tlf-display-name (nth tlf-index plain))
                            "?")))))
        (error (condition)
          (format t "~&analyze: ~a failed: ~a~%" filename condition))))))
(sb-ext:exit :code 0)
