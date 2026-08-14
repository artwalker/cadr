;;;; Goal 20 Part O: sb-sprof capture for paired paths that still miss 1.0x.
;;;;
;;;; Diagnostic only, not a gate. Reuses the paired-path fixtures and the
;;;; same CADR_CODING_AGENT_DIR staging as scripts/goal20-paired-paths.lisp.
;;;;
;;;; usage:
;;;;   CADR_BENCH_PROJECT_DIRECTORY=... QUICKLISP_SETUP=... \
;;;;     sbcl --script scripts/goal20-profile.lisp \
;;;;       [--seconds N] [--output PATH]

(require :asdf)
(require :sb-sprof)

(defparameter cl-user::*cadr-bench-project-directory*
  (uiop:ensure-directory-pathname
   (pathname
    (or (uiop:getenv "CADR_BENCH_PROJECT_DIRECTORY")
        (error "CADR_BENCH_PROJECT_DIRECTORY is not set")))))

(let ((*standard-output* *error-output*)
      (*load-verbose* nil)
      (*compile-verbose* nil))
  (load
   (or (uiop:getenv "QUICKLISP_SETUP")
       (error "QUICKLISP_SETUP is not set")))
  (dolist (name '("cadr-core.asd"
                  "cadr-ai.asd"
                  "cadr-agent.asd"
                  "cadr-tui.asd"
                  "cadr-cli.asd"))
    (asdf:load-asd
     (truename
      (merge-pathnames
       name cl-user::*cadr-bench-project-directory*))))
  (asdf:load-system "cadr-cli" :verbose nil))

(defpackage #:cadr-goal20-profile
  (:use #:cl))

(in-package #:cadr-goal20-profile)

(defparameter *seconds* 4)
(defparameter *output-path* "-")
(defparameter *sink* nil)
(defparameter *journal-append-entry-count* 128)
(defparameter *journal-write-index* 0)

(defparameter *fixture-directory*
  (merge-pathnames
   "test/fixtures/goal20-paired-paths/"
   cl-user::*cadr-bench-project-directory*))

(defparameter *scratch-directory*
  (uiop:ensure-directory-pathname
   (format nil "/tmp/goal20-cadr-profile-~D" (sb-posix:getpid))))

(defparameter *agent-directory*
  (merge-pathnames "agent/" *scratch-directory*))

(defun parse-options ()
  (let ((arguments (uiop:command-line-arguments)))
    (loop while arguments
          for argument = (pop arguments)
          do
          (cond
            ((string= argument "--seconds")
             (unless arguments
               (error "--seconds requires a value"))
             (setf *seconds* (parse-integer (pop arguments))))
            ((string= argument "--output")
             (unless arguments
               (error "--output requires a value"))
             (setf *output-path* (pop arguments)))
            (t
             (error "Unknown option: ~A" argument))))))

(defun fixture-path (name)
  (merge-pathnames name *fixture-directory*))

(defun read-fixture-json (name)
  (cadr-ai::parse-json
   (uiop:read-file-string (fixture-path name)
                          :external-format :utf-8)))

(defun argv-fixture (key)
  (let ((value (cadr-ai::json-get (read-fixture-json "cli-argv.json") key)))
    (coerce value 'list)))

(defun journal-cwd ()
  (let ((declared
          (cadr-ai::json-get
           (cadr-ai::json-get (read-fixture-json "manifest.json")
                              "parameters")
           "journal_cwd")))
    (ensure-directories-exist
     (uiop:ensure-directory-pathname declared))
    declared))

(defun stage-agent-directory ()
  (ensure-directories-exist *agent-directory*)
  (dolist (name '("models.json" "auth.json"))
    (uiop:copy-file (fixture-path name)
                    (merge-pathnames name *agent-directory*)))
  (sb-posix:setenv "CADR_CODING_AGENT_DIR"
                   (namestring *agent-directory*)
                   1))

(defun journal-append-messages ()
  (let ((messages nil)
        (remaining *journal-append-entry-count*))
    (dolist (object (cadr-agent::read-session-objects
                     (fixture-path "session.jsonl")))
      (when (zerop remaining)
        (return))
      (when (string= "message" (cadr-ai::json-get object "type"))
        (push (cadr-agent::message-from-json
               (cadr-ai::json-get object "message"))
              messages)
        (decf remaining)))
    (nreverse messages)))

(defun append-journal-once (messages cwd)
  (incf *journal-write-index*)
  (let* ((directory
           (merge-pathnames
            (format nil "journal/~D/" *journal-write-index*)
            *scratch-directory*))
         (session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id (format nil "019f0000-0000-7000-8000-~12,'0D"
                        *journal-write-index*)
            :timestamp 1786665600000)))
    (dolist (message messages)
      (cadr-agent:session-append-message session message))
    session))

(defun git-head ()
  (handler-case
      (string-trim
       '(#\Space #\Tab #\Newline #\Return)
       (uiop:run-program
        (list "git" "-C"
              (namestring cl-user::*cadr-bench-project-directory*)
              "rev-parse" "--short=12" "HEAD")
        :output :string
        :error-output :string))
    (error () "unknown")))

(defun profile-thunk (label thunk)
  (format *error-output* "goal20 sprof: ~A~%" label)
  (sb-ext:gc :full t)
  (funcall thunk)
  (sb-sprof:reset)
  (let* ((started (get-internal-real-time))
         (units internal-time-units-per-second)
         (limit (* *seconds* units)))
    (sb-sprof:start-profiling :max-samples 50000 :sample-interval 0.001d0)
    (loop while (< (- (get-internal-real-time) started) limit)
          do (setf *sink* (funcall thunk)))
    (sb-sprof:stop-profiling))
  (let ((report
          (with-output-to-string (stream)
            (let ((*standard-output* stream)
                  (*trace-output* stream))
              (sb-sprof:report :type :flat :min-percent 1.0)))))
    (format *error-output* "goal20 sprof: ~A done (~D chars)~%"
            label (length report))
    report))

(defun write-markdown (sections)
  (let ((text
          (with-output-to-string (out)
            (format out "# Goal 20 Part O remaining-path sb-sprof~%~%")
            (format out "Diagnostic capture, not a gate. Same fixtures as~%")
            (format out "`scripts/goal20-paired-paths.lisp`. Recorded because~%")
            (format out "the four Part O paths are still above 1.0x after~%")
            (format out "probes 7a-7d.~%~%")
            (format out "- recordedAt: ~A~%"
                    (cadr-core:milliseconds-to-utc-iso8601
                     (cadr-core:unix-milliseconds)
                     :fraction-digits 0))
            (format out "- git: `~A`~%" (git-head))
            (format out "- machine: ~A~%" (machine-instance))
            (format out "- lisp: ~A ~A~%"
                    (lisp-implementation-type)
                    (lisp-implementation-version))
            (format out "- seconds per path: ~D~%" *seconds*)
            (format out "- sample-interval: 0.001s~%~%")
            (dolist (section sections)
              (format out "## `~A`~%~%```~%" (first section))
              (write-string (second section) out)
              (format out "```~%~%")))))
    (if (string= *output-path* "-")
        (write-string text)
        (progn
          (ensure-directories-exist
           (uiop:pathname-directory-pathname
            (uiop:ensure-pathname *output-path*)))
          (with-open-file (stream *output-path*
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create
                                  :external-format :utf-8)
            (write-string text stream))
          (format *error-output* "goal20 sprof: wrote ~A~%" *output-path*)))))

(defun run-profiles ()
  (stage-agent-directory)
  (let* ((pattern (second (argv-fixture "list_models")))
         (session-path (fixture-path "session.jsonl"))
         (cwd (journal-cwd))
         (messages (journal-append-messages))
         (sections nil))
    (push
     (list "cli_dispatch.list_models_render"
           (profile-thunk
            "list_models_render"
            (let ((stream (make-broadcast-stream)))
              (lambda ()
                (cadr-cli::print-cli-models pattern stream)))))
     sections)
    (push
     (list "session_pipeline.session_load"
           (profile-thunk
            "session_load"
            (lambda ()
              (cadr-agent:load-session session-path))))
     sections)
    (push
     (list "storage_journal.journal_read"
           (profile-thunk
            "journal_read"
            (lambda ()
              (cadr-agent::read-session-objects session-path))))
     sections)
    (push
     (list "storage_journal.journal_append"
           (profile-thunk
            "journal_append"
            (lambda ()
              (append-journal-once messages cwd))))
     sections)
    (write-markdown (nreverse sections))))

(parse-options)
(unwind-protect
     (run-profiles)
  (uiop:delete-directory-tree *scratch-directory*
                              :validate t
                              :if-does-not-exist :ignore))
