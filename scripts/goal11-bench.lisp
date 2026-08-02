(require :asdf)

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
  (dolist (name '("cadr-ai.asd"
                  "cadr-agent.asd"
                  "cadr-tui.asd"
                  "cadr-cli.asd"))
    (asdf:load-asd
     (truename
      (merge-pathnames
       name cl-user::*cadr-bench-project-directory*))))
  (asdf:load-system "cadr-cli" :verbose nil))

(defpackage #:cadr-goal11-bench
  (:use #:cl))

(in-package #:cadr-goal11-bench)

(defparameter *entry-counts* '(0 50 200 1000 5000))
(defparameter *samples* 5)
(defparameter *warmups* 1)
(defparameter *output-path* "-")
(defparameter *include-cold-start-p* t)
(defparameter *label* "unspecified")
(defparameter *sink* nil)
(defparameter *continuous-event-count* 1024)
(defparameter *continuous-nursery-bytes* (* 8 1024 1024))
(defparameter *paired-continuous-runs* 5)
(defparameter *session-scale-profile-path*
  (namestring
   (merge-pathnames
    "docs/benchmarks/goal-v13-session-scale.json"
    cl-user::*cadr-bench-project-directory*)))

(defclass counting-terminal (cadr-tui:terminal)
  ((written-units
    :initform 0
    :accessor counting-terminal-written-units)))

(defmethod cadr-tui:terminal-write
    ((terminal counting-terminal) text)
  (incf (counting-terminal-written-units terminal)
        (length text))
  text)

(defstruct frame-fixture
  state
  editor
  decoder
  terminal
  renderer
  render-coordinator
  message)

(defun parse-positive-integer (text option)
  (let ((value
          (parse-integer text :junk-allowed t)))
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
             (setf *entry-counts* '(0 50 200)
                   *samples* 3
                   *warmups* 1
                   *continuous-event-count* 12
                   *paired-continuous-runs* 1))
            ((string= argument "--no-cold-start")
             (setf *include-cold-start-p* nil))
            ((string= argument "--samples")
             (unless arguments
               (error "--samples requires a value"))
             (setf *samples*
                   (parse-positive-integer
                    (pop arguments) argument)))
            ((string= argument "--warmups")
             (unless arguments
               (error "--warmups requires a value"))
             (setf *warmups*
                   (parse-positive-integer
                    (pop arguments) argument)))
            ((string= argument "--continuous-events")
             (unless arguments
               (error "--continuous-events requires a value"))
             (setf *continuous-event-count*
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
            ((string= argument "--session-scale-profile")
             (unless arguments
               (error "--session-scale-profile requires a value"))
             (setf *session-scale-profile-path*
                   (pop arguments)))
            (t
             (error "Unknown benchmark option: ~A"
                    argument))))))

(defun json-object (&rest pairs)
  (apply #'cadr-ai::json-object pairs))

(defun json-array (values)
  (coerce values 'vector))

(defun median (values)
  (let* ((sorted (sort (copy-list values) #'<))
         (count (length sorted))
         (middle (floor count 2)))
    (if (oddp count)
        (coerce (nth middle sorted) 'double-float)
        (/ (+ (nth (1- middle) sorted)
              (nth middle sorted))
           2d0))))

(defun median-absolute-deviation (values center)
  (median
   (mapcar
    (lambda (value)
      (abs (- value center)))
    values)))

(defun percentile (values fraction)
  (let* ((sorted (sort (copy-list values) #'<))
         (index
           (max
            0
            (min
             (1- (length sorted))
             (1-
              (ceiling
               (* fraction (length sorted))))))))
    (coerce (nth index sorted) 'double-float)))

(defun elapsed-microseconds (start end)
  (* 1000000d0
     (/ (- end start)
        (coerce internal-time-units-per-second
                'double-float))))

(defun measure-batch (function repetitions)
  (sb-ext:gc :full t)
  (let ((bytes-before (sb-ext:get-bytes-consed))
        (started-at (get-internal-real-time)))
    (dotimes (index repetitions)
      (declare (ignore index))
      (setf *sink* (funcall function)))
    (let ((ended-at (get-internal-real-time))
          (bytes-after (sb-ext:get-bytes-consed)))
      (values
       (/ (elapsed-microseconds started-at ended-at)
          repetitions)
       (/ (- bytes-after bytes-before)
          (coerce repetitions 'double-float))))))

(defun collect-statistics (prepare repetitions)
  (dotimes (index *warmups*)
    (declare (ignore index))
    (measure-batch (funcall prepare) repetitions))
  (let ((times nil)
        (allocations nil))
    (dotimes (index *samples*)
      (declare (ignore index))
      (multiple-value-bind (microseconds bytes)
          (measure-batch (funcall prepare) repetitions)
        (push microseconds times)
        (push bytes allocations)))
    (setf times (nreverse times)
          allocations (nreverse allocations))
    (let ((time-median (median times))
          (allocation-median (median allocations)))
      (list
       :median-us time-median
       :mad-us
       (median-absolute-deviation times time-median)
       :median-bytes allocation-median
       :mad-bytes
       (median-absolute-deviation
        allocations allocation-median)
       :samples-us times
       :samples-bytes allocations
       :repetitions repetitions))))

(defun statistics-json (statistics)
  (json-object
   "mad_bytes" (getf statistics :mad-bytes)
   "mad_us" (getf statistics :mad-us)
   "median_bytes" (getf statistics :median-bytes)
   "median_us" (getf statistics :median-us)
   "repetitions" (getf statistics :repetitions)
   "samples_bytes"
   (json-array (getf statistics :samples-bytes))
   "samples_us"
   (json-array (getf statistics :samples-us))))

(defun make-mixed-entry (index)
  (case (mod index 5)
    (0
     (cadr-cli::make-tui-entry
      :type :user
      :text
      (format nil
              "Request ~D: explain **cache behavior** for 中文输入 and emoji 🚀 without changing output."
              index)))
    (1
     (cadr-cli::make-tui-entry
      :type :assistant
      :text
      (format nil
              "Entry ~D keeps markdown, `inline code`, and a wrapped paragraph stable across frames."
              index)
      :content-blocks
      (list
       (cons
        :assistant
        (format nil
                "Entry ~D keeps markdown, `inline code`, and a wrapped paragraph stable across frames."
                index)))))
    (2
     (cadr-cli::make-tui-entry
      :type :tool
      :tool-call-id (format nil "collapsed-~D" index)
      :tool-block
      (cadr-tui:make-tool-block
       :name "read"
       :summary (format nil "docs/example-~D.md:1-4" index)
       :output (format nil "alpha~%beta~%gamma~%delta")
       :status :complete
       :started-at 1d0
       :ended-at 1.012d0
       :collapsed-p t)))
    (3
     (cadr-cli::make-tui-entry
      :type :tool
      :tool-call-id (format nil "expanded-~D" index)
      :tool-block
      (cadr-tui:make-tool-block
       :name "bash"
       :summary "printf 'one\\ntwo\\nthree\\n'"
       :output (format nil "one~%two~%three")
       :status :complete
       :started-at 1d0
       :ended-at 1.021d0
       :collapsed-p nil)))
    (otherwise
     (cadr-cli::make-tui-entry
      :type :assistant
      :text
      (format nil
              "![image placeholder ~D](attachment://fixture.png) CJK 宽度与 emoji 🧪 占位。"
              index)
      :content-blocks
      (list
       (cons
        :assistant
        (format nil
                "![image placeholder ~D](attachment://fixture.png) CJK 宽度与 emoji 🧪 占位。"
                index)))))))

(defun make-entry-list (count)
  (loop for index below count
        collect (make-mixed-entry index)))

(defun make-frame-fixture-for-count
    (count &key streaming-p alt-p)
  (let* ((state
           (cadr-cli::make-tui-state
            :model "faux-bench"
            :provider "faux"
            :thinking :off
            :cwd "/tmp/cadr-goal11"
            :context-window 200000))
         (editor
           (cadr-tui:make-multiline-editor))
         (terminal
           (if alt-p
               (make-instance
                'counting-terminal
                :columns 100 :rows 40)
               (cadr-tui:make-virtual-terminal
                :columns 100 :rows 40)))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p alt-p))
         (render-coordinator
           (and
            alt-p
            (cadr-cli::make-tui-render-coordinator
             :interval 0d0)))
         (message
           (and
            streaming-p
            (cadr-ai:make-assistant-message
             :api :faux
             :provider :faux
             :model "faux-bench"
             :stop-reason :stop))))
    (cadr-cli::replace-tui-entries
     state (make-entry-list count))
    (when message
      (cadr-cli::tui-handle-agent-event
       state
       (cadr-agent::make-agent-event
        :type :message-start
        :message message)))
    (when alt-p
      (cadr-tui:renderer-start renderer))
    (make-frame-fixture
     :state state
     :editor editor
     :decoder (cadr-tui:make-input-decoder)
     :terminal terminal
     :renderer renderer
     :render-coordinator render-coordinator
     :message message)))

(defun render-fixture (fixture)
  (multiple-value-bind (document row column)
      (cadr-cli::render-tui-state
       (frame-fixture-state fixture)
       (frame-fixture-editor fixture)
       100 40
       :full-document-p
       (cadr-tui:alt-screen-renderer-p
        (frame-fixture-renderer fixture))
       :now 2d0)
    (cadr-tui:render-frame
     (frame-fixture-renderer fixture)
     document
     :cursor-row row
     :cursor-column column)))

(defun handle-alt-input-and-render (fixture input)
  (unless
      (cadr-tui:renderer-handle-input
       (frame-fixture-renderer fixture)
       input)
    (error "Alt-screen benchmark input was not consumed"))
  (cadr-cli::request-tui-render
   (frame-fixture-render-coordinator fixture))
  (let ((rendered nil))
    (unless
        (cadr-cli::flush-tui-render
         (frame-fixture-render-coordinator fixture)
         (lambda ()
           (setf rendered (render-fixture fixture)))
         :force-p t)
      (error "Alt-screen benchmark request did not render"))
    rendered))

(defun handle-editor-input-and-render (fixture input)
  (dolist (event
           (cadr-tui:feed-input
            (frame-fixture-decoder fixture)
            input))
    (cadr-cli::handle-tui-editor-event
     (frame-fixture-state fixture)
     (frame-fixture-editor fixture)
     event))
  (cadr-cli::request-tui-render
   (frame-fixture-render-coordinator fixture))
  (let ((rendered nil))
    (unless
        (cadr-cli::flush-tui-render
         (frame-fixture-render-coordinator fixture)
         (lambda ()
           (setf rendered (render-fixture fixture)))
         :force-p t)
      (error "Alt-screen editor benchmark request did not render"))
    rendered))

(defun frame-repetitions (count)
  (cond
    ((<= count 200) 10)
    ((<= count 1000) 3)
    (t 1)))

(defun stream-repetitions (count)
  (cond
    ((<= count 200) 20)
    ((<= count 1000) 5)
    (t 2)))

(defun append-repetitions (count)
  (cond
    ((zerop count) 500000)
    ((<= count 50) 400000)
    ((<= count 200) 300000)
    (t 200000)))

(defun frame-statistics (count)
  (collect-statistics
   (lambda ()
     (let ((fixture
             (make-frame-fixture-for-count count)))
       ;; Measure a steady frame. The first render populates the same
       ;; component caches that production populates on initial display.
       (render-fixture fixture)
       (lambda ()
         (render-fixture fixture))))
   (frame-repetitions count)))

(defun key-latency-statistics (count)
  (collect-statistics
   (lambda ()
     (let ((fixture
             (make-frame-fixture-for-count count)))
       (render-fixture fixture)
       (lambda ()
         (cadr-tui:editor-set-text
          (frame-fixture-editor fixture) "")
         (dolist
             (event
              (cadr-tui:feed-input
               (frame-fixture-decoder fixture)
               "x"))
           (cadr-cli::handle-tui-editor-event
            (frame-fixture-state fixture)
            (frame-fixture-editor fixture)
            event))
         (render-fixture fixture))))
   (frame-repetitions count)))

(defun stream-statistics (count)
  (collect-statistics
   (lambda ()
     (let ((fixture
             (make-frame-fixture-for-count
              count :streaming-p t)))
       (render-fixture fixture)
       (lambda ()
         (cadr-cli::tui-handle-agent-event
          (frame-fixture-state fixture)
          (cadr-agent::make-agent-event
           :type :message-update
           :message (frame-fixture-message fixture)
           :stream-event
           (cadr-ai:make-stream-event
            :type :text-delta
            :delta " delta")))
         (render-fixture fixture))))
   (stream-repetitions count)))

(defun sgr-mouse-input (button x y)
  (format nil "~C[<~D;~D;~DM"
          #\Escape button x y))

(defun prepare-alt-input-fixture (count)
  (let ((fixture
          (make-frame-fixture-for-count
           count :alt-p t)))
    (render-fixture fixture)
    (let* ((renderer (frame-fixture-renderer fixture))
           (terminal (frame-fixture-terminal fixture))
           (maximum
             (max
              0
              (-
               (cadr-tui::terminal-renderer-content-line-count
                renderer)
               (cadr-tui:terminal-rows terminal)))))
      (cadr-tui::renderer-scroll-to-top renderer)
      (cadr-tui:renderer-scroll-by
       renderer (floor maximum 2))
      (handle-alt-input-and-render
       fixture (sgr-mouse-input 0 10 10)))
    fixture))

(defun mouse-drag-statistics (count)
  (collect-statistics
   (lambda ()
     (let ((fixture (prepare-alt-input-fixture count))
           (event-index 0))
       (lambda ()
         (incf event-index)
         (handle-alt-input-and-render
          fixture
          (sgr-mouse-input
           32
           (if (oddp event-index) 20 70)
           (if (oddp event-index) 8 30))))))
   (frame-repetitions count)))

(defun wheel-statistics (count)
  (collect-statistics
   (lambda ()
     (let ((fixture (prepare-alt-input-fixture count))
           (event-index 0))
       (lambda ()
         (incf event-index)
         (handle-alt-input-and-render
          fixture
          (sgr-mouse-input
           (if (oddp event-index) 64 65)
           50 20)))))
   (frame-repetitions count)))

(defun continuous-event-input (index)
  (case (mod index 3)
    (0
     (sgr-mouse-input
      32
      (if (evenp index) 20 70)
      (if (evenp index) 8 30)))
    (1 (sgr-mouse-input 64 50 20))
    (otherwise (sgr-mouse-input 65 50 20))))

(defun continuous-event-trace-sha256 ()
  (cadr-ai::octets-hex
   (cadr-ai::sha256-bytes
    (cadr-ai::utf8-octets
     (format
      nil "~{~A~^~%~}"
      (loop for index below *continuous-event-count*
            collect (continuous-event-input index)))))))

(defun continuous-event-trace-counts-json ()
  (let ((drag 0)
        (wheel-up 0)
        (wheel-down 0))
    (dotimes (index *continuous-event-count*)
      (case (mod index 3)
        (0 (incf drag))
        (1 (incf wheel-up))
        (otherwise (incf wheel-down))))
    (json-object
     "drag" drag
     "wheel_down" wheel-down
     "wheel_up" wheel-up)))

(defun common-input-kind-name (kind)
  (ecase kind
    (:mouse-drag "mouse_drag")
    (:wheel "wheel")
    (:editor-key "editor_key")))

(defun common-event-input (kind index)
  (ecase kind
    (:mouse-drag
     (sgr-mouse-input
      32
      (if (evenp index) 20 70)
      (if (evenp index) 8 30)))
    (:wheel
     (sgr-mouse-input
      (if (evenp index) 64 65)
      50 20))
    (:editor-key
     (if (evenp index)
         "x"
         (string #\Rubout)))))

(defun common-event-trace-sha256 (kind)
  (cadr-ai::octets-hex
   (cadr-ai::sha256-bytes
    (cadr-ai::utf8-octets
     (format
      nil "~{~A~^~%~}"
      (loop for index below *continuous-event-count*
            collect (common-event-input kind index)))))))

(defun common-event-trace-counts-json (kind)
  (ecase kind
    (:mouse-drag
     (json-object "drag" *continuous-event-count*))
    (:wheel
     (json-object
      "wheel_down" (floor *continuous-event-count* 2)
      "wheel_up" (ceiling *continuous-event-count* 2)))
    (:editor-key
     (json-object
      "backspace" (floor *continuous-event-count* 2)
      "insert" (ceiling *continuous-event-count* 2)))))

(defun dispatch-common-input-and-render
    (fixture kind index)
  (let ((input (common-event-input kind index)))
    (if (eq kind :editor-key)
        (handle-editor-input-and-render fixture input)
        (handle-alt-input-and-render fixture input))))

(defun common-continuous-input-run
    (count kind &key nursery-bytes)
  (let* ((fixture (prepare-alt-input-fixture count))
         (renderer (frame-fixture-renderer fixture))
         (editor (frame-fixture-editor fixture))
         (initial-viewport-top
           (cadr-tui:renderer-viewport-top renderer))
         (latencies nil)
         (allocations nil)
         (gc-affected-latencies nil)
         (gc-runtime-before nil)
         (nursery-before
           (sb-ext:bytes-consed-between-gcs)))
    (unwind-protect
         (progn
           (sb-ext:gc :full t)
           (when nursery-bytes
             (setf
              (sb-ext:bytes-consed-between-gcs)
              nursery-bytes))
           (setf gc-runtime-before sb-ext:*gc-run-time*)
           (dotimes (index *continuous-event-count*)
             (let* ((gc-before sb-ext:*gc-run-time*)
                    (bytes-before (sb-ext:get-bytes-consed))
                    (started-at (get-internal-real-time)))
               (setf
                *sink*
                (dispatch-common-input-and-render
                 fixture kind index))
               (let ((latency
                       (elapsed-microseconds
                        started-at
                        (get-internal-real-time))))
                 (push latency latencies)
                 (push
                  (- (sb-ext:get-bytes-consed)
                     bytes-before)
                  allocations)
                 (when (> sb-ext:*gc-run-time* gc-before)
                   (push latency gc-affected-latencies)))))
           (setf latencies (nreverse latencies)
                 allocations (nreverse allocations)
                 gc-affected-latencies
                 (nreverse gc-affected-latencies))
           (let ((center (median latencies)))
             (list
              :event-count (length latencies)
              :gc-affected-event-count
              (length gc-affected-latencies)
              :gc-affected-max-us
              (if gc-affected-latencies
                  (reduce #'max gc-affected-latencies)
                  0d0)
              :gc-affected-samples-us gc-affected-latencies
              :gc-cpu-us
              (elapsed-microseconds
               gc-runtime-before sb-ext:*gc-run-time*)
              :mad-us
              (median-absolute-deviation latencies center)
              :max-us (reduce #'max latencies)
              :median-bytes (median allocations)
              :median-us center
              :p95-us (percentile latencies 0.95d0)
              :p99-us (percentile latencies 0.99d0)
              :samples-bytes allocations
              :samples-us latencies
              :total-bytes (reduce #'+ allocations)
              :rendered-frame-count (length latencies)
              :initial-viewport-top initial-viewport-top
              :final-viewport-top
              (cadr-tui:renderer-viewport-top renderer)
              :final-selection-active
              (not
               (null
                (cadr-tui::terminal-renderer-selection-anchor
                 renderer)))
              :final-editor-text-length
              (length (cadr-tui:editor-text editor)))))
      (setf
       (sb-ext:bytes-consed-between-gcs)
       nursery-before))))

(defun common-continuous-run-json (count kind)
  (let* ((run
           (common-continuous-input-run
            count kind
            :nursery-bytes *continuous-nursery-bytes*))
         (result
           (continuous-run-json run "forced-8mib-nursery")))
    (setf
     (gethash "input_kind" result)
     (common-input-kind-name kind)
     (gethash "event_trace_counts" result)
     (common-event-trace-counts-json kind)
     (gethash "event_trace_sha256" result)
     (common-event-trace-sha256 kind)
     (gethash "nursery_bytes" result)
     *continuous-nursery-bytes*)
    (ecase kind
      (:mouse-drag
       (setf
        (gethash "final_selection_active" result)
        (getf run :final-selection-active)))
      (:wheel
       (setf
        (gethash "initial_viewport_top" result)
        (getf run :initial-viewport-top)
        (gethash "final_viewport_top" result)
        (getf run :final-viewport-top)))
      (:editor-key
       (setf
        (gethash "final_editor_text_length" result)
        (getf run :final-editor-text-length))))
    result))

(defun continuous-alt-input-run (&key nursery-bytes)
  (let* ((fixture (prepare-alt-input-fixture 5000))
         (renderer (frame-fixture-renderer fixture))
         (initial-viewport-top
           (cadr-tui:renderer-viewport-top renderer))
         (latencies nil)
         (allocations nil)
         (gc-affected-latencies nil)
         (gc-runtime-before nil)
         (nursery-before
           (sb-ext:bytes-consed-between-gcs)))
    (unwind-protect
         (progn
           (sb-ext:gc :full t)
           (when nursery-bytes
             (setf
              (sb-ext:bytes-consed-between-gcs)
              nursery-bytes))
           (setf gc-runtime-before sb-ext:*gc-run-time*)
           (dotimes (index *continuous-event-count*)
             (let* ((gc-before sb-ext:*gc-run-time*)
                    (bytes-before (sb-ext:get-bytes-consed))
                    (started-at (get-internal-real-time)))
               (setf
                *sink*
                (handle-alt-input-and-render
                 fixture (continuous-event-input index)))
               (let ((latency
                       (elapsed-microseconds
                        started-at
                        (get-internal-real-time))))
                 (push latency latencies)
                 (push
                  (- (sb-ext:get-bytes-consed)
                     bytes-before)
                  allocations)
                 (when (> sb-ext:*gc-run-time* gc-before)
                   (push latency gc-affected-latencies)))))
           (setf latencies (nreverse latencies)
                 allocations (nreverse allocations)
                 gc-affected-latencies
                 (nreverse gc-affected-latencies))
           (let ((center (median latencies)))
             (list
              :event-count (length latencies)
              :gc-affected-event-count
              (length gc-affected-latencies)
              :gc-affected-max-us
              (if gc-affected-latencies
                  (reduce #'max gc-affected-latencies)
                  0d0)
              :gc-affected-samples-us gc-affected-latencies
              :gc-cpu-us
              (elapsed-microseconds
               gc-runtime-before sb-ext:*gc-run-time*)
              :mad-us
              (median-absolute-deviation latencies center)
              :max-us (reduce #'max latencies)
              :median-bytes (median allocations)
              :median-us center
              :p95-us (percentile latencies 0.95d0)
              :p99-us (percentile latencies 0.99d0)
              :samples-bytes allocations
              :samples-us latencies
              :total-bytes (reduce #'+ allocations)
              :rendered-frame-count (length latencies)
              :initial-viewport-top initial-viewport-top
              :final-viewport-top
              (cadr-tui:renderer-viewport-top renderer)
              :final-selection-active
              (not
               (null
                (cadr-tui::terminal-renderer-selection-anchor
                 renderer))))))
      (setf
       (sb-ext:bytes-consed-between-gcs)
       nursery-before))))

(defun continuous-run-json (run gc-mode)
  (json-object
   "event_count" (getf run :event-count)
   "event_trace_counts"
   (continuous-event-trace-counts-json)
   "event_trace_sha256" (continuous-event-trace-sha256)
   "final_selection_active" (getf run :final-selection-active)
   "final_viewport_top" (getf run :final-viewport-top)
   "gc_affected_event_count"
   (getf run :gc-affected-event-count)
   "gc_affected_max_us" (getf run :gc-affected-max-us)
   "gc_affected_samples_us"
   (json-array (getf run :gc-affected-samples-us))
   "gc_cpu_us" (getf run :gc-cpu-us)
   "gc_mode" gc-mode
   "initial_viewport_top" (getf run :initial-viewport-top)
   "mad_us" (getf run :mad-us)
   "max_us" (getf run :max-us)
   "median_bytes" (getf run :median-bytes)
   "median_us" (getf run :median-us)
   "p95_us" (getf run :p95-us)
   "p99_us" (getf run :p99-us)
   "rendered_frame_count" (getf run :rendered-frame-count)
   "renderer_mode" "synchronous-requested-frame"
   "samples_bytes" (json-array (getf run :samples-bytes))
   "samples_us" (json-array (getf run :samples-us))
   "scheduler_mode" "production-request-immediate-flush"
   "terminal_sink" "count-only"
   "total_bytes" (getf run :total-bytes)))

(defun continuous-alt-input-json ()
  (let ((run
          (continuous-alt-input-run
           :nursery-bytes *continuous-nursery-bytes*)))
    (let ((result
            (continuous-run-json run "forced-8mib-nursery")))
      (setf (gethash "nursery_bytes" result)
            *continuous-nursery-bytes*)
      result)))

(defun paired-continuous-alt-input-json ()
  (let* ((runs
           (loop repeat *paired-continuous-runs*
                 collect (continuous-alt-input-run)))
         (result
           (json-object
            "event_count" *continuous-event-count*
            "event_trace_counts"
            (continuous-event-trace-counts-json)
            "event_trace_sha256" (continuous-event-trace-sha256)
            "final_selection_active"
            (every
             (lambda (run)
               (getf run :final-selection-active))
             runs)
            "gc_mode" "runtime-default"
            "max_us"
            (reduce #'max runs :key
                    (lambda (run) (getf run :max-us)))
            "median_bytes"
            (median
             (mapcar
              (lambda (run) (getf run :median-bytes))
              runs))
            "rendered_frame_count" *continuous-event-count*
            "renderer_mode" "synchronous-requested-frame"
            "runs"
            (json-array
             (mapcar
              (lambda (run)
                (continuous-run-json run "runtime-default"))
              runs))
            "scheduler_mode" "production-request-immediate-flush"
            "terminal_sink" "count-only")))
    (dolist (field '((:median-us . "median")
                     (:p95-us . "p95")
                     (:p99-us . "p99")))
      (let* ((values
               (mapcar
                (lambda (run) (getf run (car field)))
                runs))
             (center (median values))
             (name (cdr field)))
        (setf
         (gethash (format nil "~A_us" name) result) center
         (gethash (format nil "~A_run_mad_us" name) result)
         (median-absolute-deviation values center))))
    result))

(defun append-statistics (count)
  (collect-statistics
   (lambda ()
     (let* ((state
              (cadr-cli::make-tui-state
               :model "faux-bench"))
            (entries (make-entry-list count))
            (tail (last entries))
            (entry
              (cadr-cli::make-tui-entry
               :type :notice
               :text "append benchmark")))
       (cadr-cli::replace-tui-entries state entries)
       (lambda ()
         (prog1
             (cadr-cli::append-tui-entry
              state entry)
           (if tail
               (progn
                 (setf
                  (cdr tail) nil
                  (cadr-cli::tui-state-entries state)
                  entries
                  (cadr-cli::tui-state-entries-tail state)
                  tail
                  (cadr-cli::tui-state-entries-tail-head state)
                  entries))
               (setf
                (cadr-cli::tui-state-entries state) nil
                (cadr-cli::tui-state-entries-tail state) nil
                (cadr-cli::tui-state-entries-tail-head state)
                nil))))))
   (append-repetitions count)))

(defun metric-point-json (count statistics
                          &key throughput-p)
  (let ((object
          (statistics-json statistics)))
    (setf (gethash "n" object) count)
    (when throughput-p
      (setf
       (gethash "delta_per_second" object)
       (/ 1000000d0
          (max 0.001d0
               (getf statistics :median-us)))))
    object))

(defun logarithmic-scaling (counts values)
  (let ((pairs
          (loop for count in counts
                for value in values
                when (and (plusp count)
                          (plusp value))
                  collect
                  (cons (log (coerce count 'double-float))
                        (log (coerce value 'double-float))))))
    (if (< (length pairs) 2)
        (values 0d0 "insufficient")
        (let* ((x-mean
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
                    (expt (- (car pair) x-mean) 2))))
               (exponent
                 (if (zerop denominator)
                     0d0
                     (/ numerator denominator)))
               (classification
                 (cond
                   ((< exponent 0.35d0) "constant")
                   ((< exponent 1.5d0) "linear")
                   (t "quadratic-or-worse"))))
          (values exponent classification)))))

(defun metric-json (counts statistics-list
                    &key throughput-p)
  (multiple-value-bind (exponent classification)
      (logarithmic-scaling
       counts
       (mapcar
        (lambda (statistics)
          (getf statistics :median-us))
        statistics-list))
    (json-object
     "points"
     (json-array
      (loop for count in counts
            for statistics in statistics-list
            collect
            (metric-point-json
             count statistics
             :throughput-p throughput-p)))
     "scaling"
     (json-object
      "classification" classification
      "log_log_exponent" exponent))))

(defun resident-bytes ()
  #+linux
  (with-open-file (stream "/proc/self/statm")
    (let ((size-pages (read stream nil 0))
          (resident-pages (read stream nil 0)))
      (declare (ignore size-pages))
      (* resident-pages
         (sb-posix:getpagesize))))
  #-linux
  0)

(defun memory-points ()
  (let ((points nil)
        (state
          (cadr-cli::make-tui-state
           :model "faux-bench"))
        (base-heap nil)
        (base-rss nil))
    (dolist (count *entry-counts*)
      (cadr-cli::replace-tui-entries
       state (make-entry-list count))
      (setf *sink* state)
      (sb-ext:gc :full t)
      (let ((heap (sb-kernel:dynamic-usage))
            (rss (resident-bytes)))
        (unless base-heap
          (setf base-heap heap
                base-rss rss))
        (push
         (json-object
          "heap_bytes" heap
          "heap_delta_bytes" (- heap base-heap)
          "n" count
          "rss_bytes" rss
          "rss_delta_bytes" (- rss base-rss))
         points)))
    (nreverse points)))

(defun memory-json ()
  (let* ((points (memory-points))
         (counts
           (mapcar
            (lambda (point)
              (gethash "n" point))
            points))
         (heap-deltas
           (mapcar
            (lambda (point)
              (gethash "heap_delta_bytes" point))
            points))
         (rss-deltas
           (mapcar
            (lambda (point)
              (gethash "rss_delta_bytes" point))
            points)))
    (multiple-value-bind
          (heap-exponent heap-classification)
        (logarithmic-scaling counts heap-deltas)
      (multiple-value-bind
            (rss-exponent rss-classification)
          (logarithmic-scaling counts rss-deltas)
        (json-object
         "heap_scaling"
         (json-object
          "classification" heap-classification
          "log_log_exponent" heap-exponent)
         "points" (json-array points)
         "rss_scaling"
         (json-object
          "classification" rss-classification
          "log_log_exponent" rss-exponent))))))

(defun cold-start-statistics ()
  (let ((binary
          (namestring
           (merge-pathnames
            "cadr"
            cl-user::*cadr-bench-project-directory*)))
        (helper
          (namestring
           (merge-pathnames
            "scripts/goal11-cold-start.py"
            cl-user::*cadr-bench-project-directory*))))
    (labels
        ((sample ()
           (let ((text
                   (string-trim
                    '(#\Space #\Tab #\Newline #\Return)
                    (uiop:run-program
                     (list "python3" helper binary)
                     :output :string
                     :error-output :string))))
             (multiple-value-bind (value end)
                 (read-from-string text nil nil)
               (unless
                   (and (numberp value)
                        (= end (length text)))
                 (error
                  "Invalid cold-start measurement: ~S"
                  text))
               (coerce value 'double-float)))))
      (dotimes (index *warmups*)
        (declare (ignore index))
        (sample))
      (let* ((times
               (loop repeat *samples*
                     collect (sample)))
             (time-median (median times))
             (zeroes
               (make-list *samples*
                          :initial-element 0d0)))
        (list
         :median-us time-median
         :mad-us
         (median-absolute-deviation times time-median)
         :median-bytes 0d0
         :mad-bytes 0d0
         :samples-us times
         :samples-bytes zeroes
         :repetitions 1)))))

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

(defun load-session-scale-profile ()
  (unless (probe-file *session-scale-profile-path*)
    (error "Session scale profile not found at ~A"
           *session-scale-profile-path*))
  (let ((profile
          (cadr-ai::parse-json
           (uiop:read-file-string
            *session-scale-profile-path*))))
    (unless (hash-table-p profile)
      (error "Session scale profile must be a JSON object"))
    profile))

(defun session-scale-common-entry-count (profile)
  (let* ((tiers (cadr-ai::json-get profile "tiers"))
         (count
           (and (hash-table-p tiers)
                (cadr-ai::json-get tiers "common"))))
    (unless (and (integerp count) (not (minusp count)))
      (error "Session scale profile has no common entry count"))
    count))

(defun provenance-json ()
  (let ((project
          (namestring
           cl-user::*cadr-bench-project-directory*)))
    (json-object
     "label" *label*
     "source_revision"
     (optional-trimmed-command-output
      (list "git" "-C" project
            "rev-parse" "HEAD")
      "isolated-copy")
     "tui_object_id"
     (trimmed-command-output
      (list "git" "-C" project
            "hash-object"
            (concatenate
             'string project
             "src/cadr-cli/tui.lisp")))
     "renderer_object_id"
     (trimmed-command-output
      (list "git" "-C" project
            "hash-object"
            (concatenate
             'string project
             "src/cadr-tui/renderer.lisp"))))))

(defun run-benchmarks ()
  (let* ((session-scale-profile
           (load-session-scale-profile))
         (common-entry-count
           (session-scale-common-entry-count
            session-scale-profile))
         (frame-results nil)
        (key-results nil)
        (stream-results nil)
        (mouse-results nil)
        (wheel-results nil)
         (append-results nil))
    (dolist (count *entry-counts*)
      (format *error-output*
              "goal11 bench: N=~D frame/key/stream/mouse/wheel/append~%"
              count)
      (push (frame-statistics count) frame-results)
      (push (key-latency-statistics count) key-results)
      (push (stream-statistics count) stream-results)
      (push (mouse-drag-statistics count) mouse-results)
      (push (wheel-statistics count) wheel-results)
      (push (append-statistics count) append-results))
    (setf frame-results (nreverse frame-results)
          key-results (nreverse key-results)
          stream-results (nreverse stream-results)
          mouse-results (nreverse mouse-results)
          wheel-results (nreverse wheel-results)
          append-results (nreverse append-results))
    (json-object
     "entry_counts" (json-array *entry-counts*)
     "kind" "cadr-goal11-performance"
     "machine"
     (json-object
      "lisp" (lisp-implementation-type)
      "lisp_version" (lisp-implementation-version)
      "machine_instance" (machine-instance)
      "machine_type" (machine-type))
     "metrics"
     (json-object
      "append_entry"
      (metric-json *entry-counts* append-results)
      "frame_render"
      (metric-json *entry-counts* frame-results)
      "key_to_frame"
      (metric-json *entry-counts* key-results)
      "mouse_drag_to_frame"
      (metric-json *entry-counts* mouse-results)
      "stream_delta_to_frame"
      (metric-json
       *entry-counts* stream-results
       :throughput-p t)
      "wheel_to_frame"
      (metric-json *entry-counts* wheel-results))
     "continuous_alt_input"
     (continuous-alt-input-json)
     "paired_continuous_alt_input"
     (paired-continuous-alt-input-json)
     "session_scale_profile"
     session-scale-profile
     "common_continuous_input"
     (json-object
      "editor_key"
      (common-continuous-run-json
       common-entry-count :editor-key)
      "entry_count" common-entry-count
      "event_count_per_kind" *continuous-event-count*
      "mouse_drag"
      (common-continuous-run-json
       common-entry-count :mouse-drag)
      "wheel"
      (common-continuous-run-json
       common-entry-count :wheel))
     "memory" (memory-json)
     "parameters"
     (json-object
      "height" 40
      "samples" *samples*
      "continuous_events" *continuous-event-count*
      "paired_fresh_fixture_per_run" t
      "continuous_nursery_bytes"
      *continuous-nursery-bytes*
      "warmups" *warmups*
      "width" 100)
     "provenance" (provenance-json)
     "schema_version" 1
     "cold_start"
     (if *include-cold-start-p*
         (statistics-json
          (cold-start-statistics))
         'null))))

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
(write-result (run-benchmarks))
