(require :asdf)

(defparameter cl-user::*cadr-stability-project-directory*
  (uiop:ensure-directory-pathname
   (pathname
    (or (uiop:getenv "CADR_STABILITY_PROJECT_DIRECTORY")
        (error "CADR_STABILITY_PROJECT_DIRECTORY is not set")))))

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
       name cl-user::*cadr-stability-project-directory*))))
  (asdf:load-system "cadr-cli" :verbose nil))

(defpackage #:cadr-goal11-stability
  (:use #:cl))

(in-package #:cadr-goal11-stability)

(defparameter *turn-count* 1200)
(defparameter *target-session-bytes* (* 10 1024 1024))
(defparameter *output-path* "-")
(defparameter *label* "unspecified")
(defparameter *operation-sink* nil)
(defparameter *append-counts* '(0 1000 5000 20000))

(defun parse-positive-integer (text option)
  (let ((value (parse-integer text :junk-allowed t)))
    (unless (and value (plusp value))
      (error "~A requires a positive integer" option))
    value))

(defun parse-options ()
  (let ((arguments (uiop:command-line-arguments)))
    (loop while arguments
          for argument = (pop arguments)
          do
          (cond
            ((string= argument "--quick")
             (setf *turn-count* 120
                   *target-session-bytes* (* 1024 1024)))
            ((string= argument "--turns")
             (unless arguments
               (error "--turns requires a value"))
             (setf *turn-count*
                   (parse-positive-integer
                    (pop arguments) argument)))
            ((string= argument "--session-bytes")
             (unless arguments
               (error "--session-bytes requires a value"))
             (setf *target-session-bytes*
                   (parse-positive-integer
                    (pop arguments) argument)))
            ((string= argument "--output")
             (unless arguments
               (error "--output requires a value"))
             (setf *output-path* (pop arguments)))
            ((string= argument "--label")
             (unless arguments
               (error "--label requires a value"))
             (setf *label* (pop arguments)))
            (t
             (error "Unknown stability option: ~A" argument))))))

(defun json-object (&rest pairs)
  (apply #'cadr-ai::json-object pairs))

(defun json-array (values)
  (coerce values 'vector))

(defun elapsed-microseconds (start end)
  (* 1000000d0
     (/ (- end start)
        (coerce internal-time-units-per-second
                'double-float))))

(defun median (values)
  (let* ((sorted (sort (copy-list values) #'<))
         (count (length sorted))
         (middle (floor count 2)))
    (if (oddp count)
        (coerce (nth middle sorted) 'double-float)
        (/ (+ (nth (1- middle) sorted)
              (nth middle sorted))
           2d0))))

(defun logarithmic-exponent (counts values)
  (let* ((pairs
           (loop for count in counts
                 for value in values
                 when (and (plusp count) (plusp value))
                   collect
                   (cons
                    (log (coerce count 'double-float))
                    (log (coerce value 'double-float)))))
         (_
           (when (< (length pairs) 2)
             (return-from logarithmic-exponent 0d0)))
         (x-mean
           (/ (reduce #'+ pairs :key #'car)
              (length pairs)))
         (y-mean
           (/ (reduce #'+ pairs :key #'cdr)
              (length pairs)))
         (numerator
           (reduce
            #'+ pairs
            :key
            (lambda (pair)
              (* (- (car pair) x-mean)
                 (- (cdr pair) y-mean)))))
         (denominator
           (reduce
            #'+ pairs
            :key
            (lambda (pair)
              (expt (- (car pair) x-mean) 2)))))
    (declare (ignore _))
    (if (zerop denominator)
        0d0
        (/ numerator denominator))))

(defun resident-bytes ()
  #+linux
  (with-open-file (stream "/proc/self/statm")
    (let ((size-pages (read stream nil 0))
          (resident-pages (read stream nil 0)))
      (declare (ignore size-pages))
      (* resident-pages (sb-posix:getpagesize))))
  #-linux
  0)

(defun linux-directory-count (pattern)
  #+linux
  (length (directory pattern))
  #-linux
  0)

(defun file-descriptor-count ()
  (linux-directory-count #p"/proc/self/fd/*"))

(defun os-thread-count ()
  (linux-directory-count #p"/proc/self/task/*"))

(defun lisp-thread-count ()
  (length (sb-thread:list-all-threads)))

(defun full-gc-pause-microseconds ()
  (let ((started-at (get-internal-real-time)))
    (sb-ext:gc :full t)
    (elapsed-microseconds
     started-at (get-internal-real-time))))

(defun checkpoint-json (turn event-count state agent session)
  (let ((pause (full-gc-pause-microseconds)))
    (json-object
     "agent_messages" (length (cadr-agent:agent-messages agent))
     "event_count" event-count
     "fd_count" (file-descriptor-count)
     "gc_full_pause_us" pause
     "heap_bytes" (sb-kernel:dynamic-usage)
     "lisp_thread_count" (lisp-thread-count)
     "os_thread_count" (os-thread-count)
     "rss_bytes" (resident-bytes)
     "session_entries"
     (length (cadr-agent::session-%entries session))
     "tui_entries"
     (length (cadr-cli::tui-state-entries state))
     "turn" turn)))

(defun render-stability-frame (state editor renderer)
  (multiple-value-bind (document row column)
      (cadr-cli::render-tui-state
       state editor 100 40
       :full-document-p nil
       :now 2d0)
    (cadr-tui:render-frame
     renderer document
     :cursor-row row
     :cursor-column column)))

(defun checkpoint-turns ()
  (remove-duplicates
   (sort
    (list 0
          (max 1 (floor *turn-count* 4))
          (max 1 (floor *turn-count* 2))
          (max 1 (floor (* *turn-count* 3) 4))
          *turn-count*)
    #'<)))

(defun run-long-session (directory cwd)
  (let* ((handle (cadr-ai:make-faux-provider))
         (model (cadr-ai:faux-get-model handle))
         (response
           (cadr-ai:faux-assistant-message
            "acknowledged 中文 🚀"))
         (session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id "goal11-long-run"
            :timestamp 1))
         (state
           (cadr-cli::make-tui-state
            :model (cadr-ai:model-id model)
            :provider "faux"
            :thinking :off
            :cwd (namestring cwd)
            :context-window
            (cadr-ai:model-context-window model)))
         (editor (cadr-tui:make-multiline-editor))
         (terminal
           (cadr-tui:make-virtual-terminal
            :columns 100 :rows 40))
         (renderer
           (cadr-tui:make-terminal-renderer terminal))
         (event-count 0)
         (checkpoints nil)
         (wanted (checkpoint-turns))
         (started-at nil)
         (agent nil))
    (cadr-ai:faux-set-responses
     handle
     (loop repeat *turn-count* collect response))
    (setf
     agent
     (cadr-agent:make-agent
      :provider :faux
      :model model
      :session session
      :auto-compact-p nil
      :stream-function
      (lambda (provider stream-model context on-event
               &rest options)
        (declare (ignore provider))
        (apply #'cadr-ai:faux-stream
               handle stream-model context on-event options))
      :on-event
      (lambda (event)
        (incf event-count)
        (cadr-cli::tui-handle-agent-event state event)
        (render-stability-frame state editor renderer))))
    (push
     (checkpoint-json 0 event-count state agent session)
     checkpoints)
    (setf started-at (get-internal-real-time))
    (loop for turn from 1 to *turn-count*
          do
          (cadr-agent:agent-prompt
           agent
           (format nil
                   "turn ~D fixed payload 中文 🚀"
                   turn))
          (when (member turn wanted)
            (format *error-output*
                    "goal11 stability: long run checkpoint ~D/~D~%"
                    turn *turn-count*)
            (push
             (checkpoint-json
              turn event-count state agent session)
             checkpoints)))
    (setf checkpoints (nreverse checkpoints))
    (json-object
     "assumed_turns_per_minute" 2
     "checkpoints" (json-array checkpoints)
     "event_count" event-count
     "final_session_bytes"
     (with-open-file
         (stream (cadr-agent::session-path session)
                 :direction :input
                 :element-type '(unsigned-byte 8))
       (file-length stream))
     "frame_count" event-count
     "total_duration_us"
     (elapsed-microseconds
      started-at (get-internal-real-time))
     "provider" "faux"
     "simulated_hours"
     (/ *turn-count* 120d0)
     "turns" *turn-count*)))

(defun set-private-accessor-if-present
    (name value object)
  (let ((setter (list 'setf name)))
    (when (fboundp setter)
      (funcall (fdefinition setter) value object))))

(defun timed-repeated-append (function repetitions)
  (sb-ext:gc :full t)
  (multiple-value-bind (start-seconds start-microseconds)
      (sb-ext:get-time-of-day)
    (dotimes (index repetitions)
      (declare (ignore index))
      (funcall function))
    (multiple-value-bind (end-seconds end-microseconds)
        (sb-ext:get-time-of-day)
      (/ (+ (* (- end-seconds start-seconds) 1000000d0)
            (- end-microseconds start-microseconds))
         repetitions))))

(defun session-append-probe (count directory cwd)
  (let* ((session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id (format nil "append-probe-~D" count)))
         (message
           (cadr-ai:make-user-message
            :content "append probe" :timestamp 1)))
    (dotimes (index count)
      (declare (ignore index))
      (cadr-agent:session-append-message session message))
    (let ((entries (cadr-agent::session-%entries session))
          (tail (last (cadr-agent::session-%entries session)))
          (leaf (cadr-agent::session-leaf-id session)))
      (lambda ()
        (let ((id
                (cadr-agent:session-append-message
                 session message)))
          (remhash id (cadr-agent::session-by-id session))
          (if tail
              (setf
               (cdr tail) nil
               (cadr-agent::session-%entries session) entries)
              (setf
               (cadr-agent::session-%entries session) nil))
          (setf (cadr-agent::session-leaf-id session) leaf)
          (set-private-accessor-if-present
           'cadr-agent::session-%entries-tail tail session)
          (set-private-accessor-if-present
           'cadr-agent::session-%entries-tail-head entries session))))))

(defun agent-append-probe (count)
  (let* ((message
           (cadr-ai:make-user-message
            :content "append probe" :timestamp 1))
         (agent
           (cadr-agent:make-agent
            :provider :faux
            :model
            (cadr-ai:make-model
             :id "faux-1"
             :provider :faux
             :api :faux
             :base-url "http://localhost:0")
            :messages
            (loop repeat count collect message)))
         (messages (cadr-agent:agent-messages agent))
         (tail (last (cadr-agent:agent-messages agent))))
    (lambda ()
      (cadr-agent::append-agent-message agent message)
      (if tail
          (setf
           (cdr tail) nil
           (cadr-agent:agent-messages agent) messages)
          (setf (cadr-agent:agent-messages agent) nil))
      (set-private-accessor-if-present
       'cadr-agent::agent-messages-tail tail agent)
      (set-private-accessor-if-present
       'cadr-agent::agent-messages-tail-head messages agent))))

(defun append-metric-json (prepare samples repetitions)
  (let ((points nil)
        (medians nil))
    (dolist (count *append-counts*)
      (let ((samples
              (loop repeat samples
                    collect
                    (timed-repeated-append
                     (funcall prepare count)
                     repetitions))))
        (let ((value (median samples)))
          (push value medians)
          (push
           (json-object
            "median_us" value
            "n" count
            "samples_us" (json-array samples))
           points))))
    (setf points (nreverse points)
          medians (nreverse medians))
    (let ((exponent
            (logarithmic-exponent
             *append-counts* medians)))
      (json-object
       "log_log_exponent" exponent
       "points" (json-array points)
       "scaling"
       (if (< exponent 0.35d0)
           "constant"
           "linear-or-worse")))))

(defun run-append-probes (directory cwd)
  (format *error-output*
          "goal11 stability: agent/session append scaling~%")
  (json-object
   "agent"
   (append-metric-json
    (lambda (count)
      (agent-append-probe count))
    5 10000)
   "entry_counts" (json-array *append-counts*)
   "session"
   (append-metric-json
    (lambda (count)
      (session-append-probe count directory cwd))
    3 500)))

(defun file-size (path)
  (with-open-file
      (stream path
              :direction :input
              :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun make-large-session (directory cwd)
  (let* ((session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id "goal11-large"
            :timestamp 1))
         (payload
           (concatenate
            'string
            "fixed 中文 🚀 "
            (make-string 4080 :initial-element #\x)))
         (count 0)
         (path (cadr-agent::session-path session))
         (size 0))
    (loop
      (let ((timestamp (+ 2 count)))
        (cadr-agent:session-append-message
         session
         (if (evenp count)
             (cadr-ai:make-user-message
              :content payload :timestamp timestamp)
             (cadr-ai:faux-assistant-message
              payload :timestamp timestamp))))
      (incf count)
      (when (and (probe-file path)
                 (zerop (mod count 32)))
        (setf size (file-size path))
        (when (>= size *target-session-bytes*)
          (return))))
    (setf size (file-size path))
    (values path count size)))

(defun measure-session-operation (name function)
  (sb-ext:gc :full t)
  (let* ((base-heap (sb-kernel:dynamic-usage))
         (base-rss (resident-bytes))
         (peak-heap base-heap)
         (peak-rss base-rss)
         (sample-count 0)
         (lock
           (sb-thread:make-mutex
            :name "goal11 peak sampler"))
         (ready (sb-thread:make-semaphore :count 0))
         (stopped-p nil)
         (sampler
           (sb-thread:make-thread
            (lambda ()
              (sb-thread:signal-semaphore ready)
              (loop
                (sb-thread:with-mutex (lock)
                  (when stopped-p
                    (return))
                  (incf sample-count)
                  (setf
                   peak-heap
                   (max peak-heap
                        (sb-kernel:dynamic-usage))
                   peak-rss
                   (max peak-rss
                        (resident-bytes))))
                (sleep 0.001d0)))
            :name (format nil "goal11 ~A peak sampler" name))))
    (sb-thread:wait-on-semaphore ready)
    (let ((bytes-before (sb-ext:get-bytes-consed))
          (started-at (get-internal-real-time))
          (result nil))
      (unwind-protect
           (setf result (funcall function))
        (sb-thread:with-mutex (lock)
          (setf stopped-p t))
        (sb-thread:join-thread sampler))
      (let ((duration
              (elapsed-microseconds
               started-at (get-internal-real-time)))
            (allocated
              (- (sb-ext:get-bytes-consed) bytes-before)))
        (setf *operation-sink* result)
        (let ((gc-pause (full-gc-pause-microseconds))
              (retained-heap (sb-kernel:dynamic-usage))
              (retained-rss (resident-bytes))
              (entries
                (length
                 (cadr-agent::session-%entries result))))
          (setf *operation-sink* nil)
          (json-object
           "allocated_bytes" allocated
           "duration_us" duration
           "entries" entries
           "fd_count" (file-descriptor-count)
           "full_gc_pause_us" gc-pause
           "heap_base_bytes" base-heap
           "heap_peak_sampled_bytes" peak-heap
           "heap_retained_bytes" retained-heap
           "name" name
           "os_thread_count" (os-thread-count)
           "rss_base_bytes" base-rss
           "rss_peak_sampled_bytes" peak-rss
           "rss_retained_bytes" retained-rss
           "sample_count" sample-count
           "sample_interval_ms" 1d0))))))

(defun run-large-session-operations (directory cwd)
  (format *error-output*
          "goal11 stability: creating >=~D-byte JSONL session~%"
          *target-session-bytes*)
  (multiple-value-bind (path entry-count size)
      (make-large-session directory cwd)
    (sb-ext:gc :full t)
    (let ((operations
            (list
             (measure-session-operation
              "load"
              (lambda ()
                (cadr-agent:load-session path)))
             (measure-session-operation
              "resume"
              (lambda ()
                (cadr-agent:resume-session
                 "goal11-large"
                 :directory directory)))
             (measure-session-operation
              "continue"
              (lambda ()
                (cadr-agent:continue-session
                 :directory directory
                 :cwd cwd))))))
      (json-object
       "entry_count" entry-count
       "file_bytes" size
       "operations" (json-array operations)
       "target_bytes" *target-session-bytes*))))

(defun trimmed-command-output (arguments)
  (string-trim
   '(#\Space #\Tab #\Newline #\Return)
   (uiop:run-program
    arguments
    :output :string
    :error-output :string)))

(defun optional-trimmed-command-output
    (arguments fallback)
  (handler-case
      (let ((value (trimmed-command-output arguments)))
        (if (plusp (length value)) value fallback))
    (error () fallback)))

(defun provenance-json ()
  (let ((project
          (namestring
           cl-user::*cadr-stability-project-directory*)))
    (json-object
     "label" *label*
     "source_revision"
     (optional-trimmed-command-output
      (list "git" "-C" project "rev-parse" "HEAD")
      "isolated-copy")
     "agent_runtime_object_id"
     (trimmed-command-output
      (list "git" "-C" project "hash-object"
            (concatenate
             'string project "src/cadr-agent/runtime.lisp")))
     "agent_session_object_id"
     (trimmed-command-output
      (list "git" "-C" project "hash-object"
            (concatenate
             'string project "src/cadr-agent/session.lisp")))
     "tui_object_id"
     (trimmed-command-output
      (list "git" "-C" project "hash-object"
            (concatenate
             'string project "src/cadr-cli/interactive/controller.lisp"))))))

(defun run-stability ()
  (uiop:with-temporary-file
      (:pathname marker :keep t)
    (delete-file marker)
    (let* ((root
             (uiop:ensure-directory-pathname
              (pathname
               (format nil "~A-goal11-stability/"
                       (namestring marker)))))
           (long-directory
             (merge-pathnames "long/" root))
           (large-directory
             (merge-pathnames "large/" root))
           (cwd (merge-pathnames "project/" root)))
      (ensure-directories-exist
       (merge-pathnames "anchor" long-directory))
      (ensure-directories-exist
       (merge-pathnames "anchor" large-directory))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (unwind-protect
           (let* ((baseline
                    (progn
                      (sb-ext:gc :full t)
                      (json-object
                       "fd_count" (file-descriptor-count)
                       "heap_bytes" (sb-kernel:dynamic-usage)
                       "lisp_thread_count" (lisp-thread-count)
                       "os_thread_count" (os-thread-count)
                       "rss_bytes" (resident-bytes))))
                  (long-run
                    (run-long-session long-directory cwd)))
             (sb-ext:gc :full t)
             (setf
              (gethash "post_cleanup" long-run)
              (json-object
               "fd_count" (file-descriptor-count)
               "heap_bytes" (sb-kernel:dynamic-usage)
               "lisp_thread_count" (lisp-thread-count)
               "os_thread_count" (os-thread-count)
               "rss_bytes" (resident-bytes)))
             (json-object
             "baseline" baseline
              "append_scaling"
              (run-append-probes long-directory cwd)
              "kind" "cadr-goal11-stability"
              "large_session"
              (run-large-session-operations
               large-directory cwd)
              "long_run" long-run
              "machine"
              (json-object
               "lisp" (lisp-implementation-type)
               "lisp_version"
               (lisp-implementation-version)
               "machine_instance" (machine-instance)
               "machine_type" (machine-type))
              "provenance" (provenance-json)
              "schema_version" 1))
        (when (probe-file root)
          (uiop:delete-directory-tree
           root :validate t
           :if-does-not-exist :ignore))))))

(defun write-result (result)
  (let ((text (cadr-ai::stringify-json result)))
    (if (string= *output-path* "-")
        (write-line text)
        (with-open-file
            (stream *output-path*
                    :direction :output
                    :if-exists :supersede
                    :if-does-not-exist :create
                    :external-format :utf-8)
          (write-line text stream)))))

(parse-options)
(write-result (run-stability))
