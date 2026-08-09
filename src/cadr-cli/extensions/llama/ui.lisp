(in-package #:cadr-cli)

;;; Baseline packages/coding-agent/src/extensions/llama/ui.ts: the
;;; interactive llama.cpp manager surface — context labels, model
;;; descriptions, compact counts, the framed model selector, the
;;; Hugging Face live search, and the cancellable progress view.

;;;; Pure helpers (ui.ts:35-39 contextLabel, :41-52 modelDescription,
;;;; :102-106 compactCount)

(defun llama-format-context-size (value)
  "Baseline: context >= 1000 ? `${Math.round(context / 1000)}k` : String(context)."
  (if (>= value 1000)
      ;; Math.round is floor(x + 0.5) for non-negative inputs.
      (format nil "~Dk" (floor (+ (/ value 1000) 1/2)))
      (princ-to-string value)))

(defun llama-context-label (model)
  "Baseline contextLabel: meta n_ctx ?? n_ctx_train, else the
--ctx-size/-c/-ctx value from the server status args."
  (let ((context
         (or (llama-model-info-context-window model)
             (llama-model-info-training-context-window model))))
    (cond
      (context (llama-format-context-size context))
      (t
       (let ((args (llama-model-info-arguments model)))
         (loop for rest on args
               while (cdr rest)
               when (member
                     (first rest)
                     '("--ctx-size" "-c" "-ctx")
                     :test #'string=)
               do (let ((value
                         (ignore-errors
                          (let ((*read-eval* nil))
                            (read-from-string (second rest))))))
                    (when (and (realp value) (plusp value))
                      (return (llama-format-context-size value))))))))))

(defun llama-model-description (model)
  "Baseline modelDescription: loaded status and context label joined
with \" · \"; non-loaded non-unloaded statuses show the raw status."
  (let ((status (llama-model-info-status model))
        (details nil))
    (let ((loaded-p (member status '(:loaded :sleeping))))
      (cond
        (loaded-p (push "loaded" details))
        ((not (eq status :unloaded))
         (push (string-downcase (symbol-name status)) details)))
      (when loaded-p
        (let ((context (llama-context-label model)))
          (when context
            (push (format nil "~A context" context) details)))))
    (format nil "~{~A~^ · ~}" (nreverse details))))

(defun llama-js-to-fixed (value digits)
  "JS Number.prototype.toFixed for non-negative rationals: ties round
away from zero."
  (let* ((scale (expt 10 digits))
         (scaled (floor (+ (* value scale) 1/2))))
    (if (zerop digits)
        (princ-to-string scaled)
        (format
         nil "~D.~V,'0D"
         (floor scaled scale)
         digits
         (mod scaled scale)))))

(defun llama-compact-count (value)
  "Baseline compactCount: 1.2k/3M formatting with toFixed cutoffs."
  (cond
    ((>= value 1000000)
     (format
      nil "~AM"
      (llama-js-to-fixed (/ value 1000000) (if (>= value 10000000) 0 1))))
    ((>= value 1000)
     (format
      nil "~Ak"
      (llama-js-to-fixed (/ value 1000) (if (>= value 100000) 0 1))))
    (t (princ-to-string value))))

;;;; The view (ui.ts LlamaView + HuggingFaceSearch + frame)

(defstruct llama-search-state
  input
  (results nil :type list)
  (filtered nil :type list)
  (selected 0 :type (integer 0 *))
  (status "Type at least 2 characters" :type string)
  (query "" :type string)
  (generation 0 :type (integer 0 *))
  (cache (make-hash-table :test #'equal))
  search-function)

(defclass llama-view (render-aware-component cadr-tui:component)
  ((keybindings
    :initarg :keybindings
    :reader llama-view-keybindings)
   (done-function
    :initarg :done-function
    :reader llama-view-done-function)
   (lock
    :reader llama-view-lock
    :initform (sb-thread:make-mutex :name "llama-view"))
   (condition
    :reader llama-view-condition
    :initform (sb-thread:make-waitqueue :name "llama-view"))
   (resolved-p :initform nil :accessor llama-view-resolved-p)
   (resolution :initform nil :accessor llama-view-resolution)
   (mode :initform :loading :accessor llama-view-mode)
   (title :initform "llama.cpp models" :accessor llama-view-title)
   (body :initform nil :accessor llama-view-body)
   (footer :initform nil :accessor llama-view-footer)
   (select-list :initform nil :accessor llama-view-select-list)
   (select-kind :initform nil :accessor llama-view-select-kind)
   (search :initform nil :accessor llama-view-search)
   (last-width :initform 80 :accessor llama-view-last-width)
   (status-message :initform nil :accessor llama-view-status-message)
   (progress :initform nil :accessor llama-view-progress)
   (body-prefix :initform nil :accessor llama-view-body-prefix)
   (closed-p :initform nil :accessor llama-view-closed-p)))

(defun make-llama-view (keybindings done-function)
  (make-instance
   'llama-view
   :keybindings keybindings
   :done-function done-function))

(defun llama-view-request-render (view)
  (let ((request (component-render-request-function view)))
    (when request (funcall request))))

(defun llama-view-park (view)
  "Park the flow thread until the TUI thread resolves the pending
interaction, then return its value."
  (sb-thread:with-mutex ((llama-view-lock view))
    (loop until (llama-view-resolved-p view)
          do (sb-thread:condition-wait
              (llama-view-condition view)
              (llama-view-lock view)))
    (prog1 (llama-view-resolution view)
      (setf
       (llama-view-resolved-p view) nil
       (llama-view-resolution view) nil))))

(defun llama-view-resolve (view value)
  (sb-thread:with-mutex ((llama-view-lock view))
    (setf
     (llama-view-resolution view) value
     (llama-view-resolved-p view) t)
    (sb-thread:condition-broadcast (llama-view-condition view))))

(defun llama-view-frame-lines (view width)
  "Baseline frame(): accent DynamicBorder, bold accent title, body,
dim footer, accent DynamicBorder."
  (append
   (list (selector-border-line width :accent))
   (component-text-lines
    (cadr-tui:theme-foreground
     :accent
     (cadr-tui:theme-bold (llama-view-title view) :enabled-p t)
     :enabled-p t)
    width)
   (llama-view-body view)
   (when (llama-view-footer view)
     (append
      (list "")
      (component-text-lines
       (cadr-tui:theme-foreground
        :dim (llama-view-footer view) :enabled-p t)
       width)))
   (list (selector-border-line width :accent))))

(defun llama-view-key-hint (view name description)
  (selector-keybinding-hint
   (llama-view-keybindings view) name description))

(defun llama-view-set-select
    (view title items confirm-verb cancel-verb kind)
  "Baseline selectList host for showModels/select: framed select with
min(items, 12) visible rows; the models list uses the baseline 36/56
primary column window."
  (setf
   (llama-view-title view) title
   (llama-view-select-list
    view)
   (apply
    #'cadr-tui:make-select-list
    :items items
    :height (max 1 (min (length items) 12))
    :show-filter-p nil
    (if (eq kind :models)
        (list
         :min-primary-column-width 36
         :max-primary-column-width 56)
        nil))
   (llama-view-select-kind view) kind
   (llama-view-footer view)
   (format
    nil "~A • ~A"
    (llama-view-key-hint view "tui.select.confirm" confirm-verb)
    (llama-view-key-hint view "tui.select.cancel" cancel-verb))
   (llama-view-mode view) :select)
  (llama-view-refresh-body view)
  (llama-view-request-render view))

(defun llama-view-refresh-body (view)
  (setf
   (llama-view-body view)
   (ecase (llama-view-mode view)
     ((:loading)
      (component-text-lines
       (cadr-tui:theme-foreground :muted "Loading…" :enabled-p t)
       (llama-view-width view)))
     ((:select)
      (append
       (llama-view-body-prefix view)
       (list "")
       (cadr-tui:render-select-list
        (llama-view-select-list view)
        (llama-view-width view))))
     ((:search)
      (append
       (list "")
       (llama-search-lines
        (llama-view-search view)
        (llama-view-width view))))
     ((:status)
      (append
       (list "")
       (component-text-lines
        (cadr-tui:theme-foreground
         :muted (llama-view-status-message view) :enabled-p t)
        (llama-view-width view))))
     ((:progress)
      (llama-view-progress-lines view)))))

(defmethod cadr-tui:component-render
    ((view llama-view) width &key focused-p)
  (declare (ignore focused-p))
  (sb-thread:with-mutex ((llama-view-lock view))
    (setf (llama-view-last-width view) width)
    (llama-view-refresh-body view))
  (llama-view-frame-lines view width))

(defmethod cadr-tui:component-handle-event
    ((view llama-view) event)
  (let ((kind (cadr-tui:input-event-kind event)))
    (sb-thread:with-mutex ((llama-view-lock view))
      (ecase (llama-view-mode view)
        ((:loading :status)
         (when (member kind '(:escape :cancel :interrupt))
           (llama-view-resolve view nil)))
        ((:select)
         (multiple-value-bind (action value)
             (cadr-tui:select-list-handle-event
              (llama-view-select-list view) event)
           (when (member action '(:select :cancel))
             (llama-view-resolve
              view
              (and (eq action :select) value)))))
        ((:search)
         (llama-search-handle-event view event))
        ((:progress)
         (when (member kind '(:escape :cancel :interrupt))
           (llama-view-resolve view :stop)))))
    (values nil nil)))

(defun llama-view-width (view)
  (llama-view-last-width view))

;;;; Progress view (ui.ts progress/updateProgress)

(defun llama-view-progress-lines (view)
  (let ((state (llama-view-progress view))
        (width (llama-view-width view)))
    (append
     (component-text-lines
      (cadr-tui:theme-foreground
       :text (or (getf state :model) "") :enabled-p t)
      width)
     (list "")
     (component-text-lines
      (cadr-tui:theme-foreground
       :muted (or (getf state :message) "") :enabled-p t)
      width)
     (when (getf state :ratio)
       (let* ((available 40)
              (ratio (max 0 (min 1 (getf state :ratio))))
              (filled (floor (+ (* ratio available) 1/2))))
         (component-text-lines
          (cadr-tui:theme-foreground
           :accent
           (format
            nil "~A~A ~D%"
            (make-string filled :initial-element #\█)
            (make-string (- available filled) :initial-element #\─)
            (floor (+ (* ratio 100) 1/2)))
           :enabled-p t)
          width)))
     (when (getf state :detail)
       (component-text-lines
        (cadr-tui:theme-foreground
         :dim (getf state :detail) :enabled-p t)
        width)))))

;;;; Hugging Face search (ui.ts HuggingFaceSearch)

(defun llama-search-lines (search width)
  (append
   (component-text-lines
    (cadr-tui:theme-foreground
     :dim "Model name or owner/repository[:quant]" :enabled-p t)
    width)
   (list
    (selector-input-line
     (cadr-tui:single-line-input-value
      (llama-search-state-input search))
     width))
   (list "")
   (llama-search-result-lines search width)))

(defun llama-search-result-lines (search width)
  (let* ((filtered (llama-search-state-filtered search))
         (max-visible 10)
         (count (length filtered))
         (selected (llama-search-state-selected search))
         (start
          (max
           0
           (min
            (- selected (floor max-visible 2))
            (- count max-visible))))
         (end (min (+ start max-visible) count)))
    (append
     (loop for index from start below end
           for model = (nth index filtered)
           for id = (getf model :id)
           for details =
           (format
            nil "~A downloads"
            (llama-compact-count (or (getf model :downloads) 0)))
           collect
           (selector-fit-line
            (if (eql index selected)
                (cadr-tui:theme-foreground
                 :accent
                 (format nil "→ ~A  ~A" id details)
                 :enabled-p t)
                (format
                 nil "  ~A~A"
                 id
                 (cadr-tui:theme-foreground
                  :muted
                  (format nil "  ~A" details)
                  :enabled-p t)))
            width))
     (when (or (plusp start) (< end count))
       (list
        (selector-fit-line
         (cadr-tui:theme-foreground
          :dim
          (format nil "  (~D/~D)" (1+ selected) count)
          :enabled-p t)
         width)))
     (cond
       ((zerop count)
        (list
         (selector-fit-line
          (cadr-tui:theme-foreground
           :dim
           (format nil "  ~A" (llama-search-state-status search))
           :enabled-p t)
          width)))
       ((string=
         (llama-search-state-status search)
         "Searching Hugging Face…")
        (list
         (selector-fit-line
          (cadr-tui:theme-foreground
           :dim
           (format nil "  ~A" (llama-search-state-status search))
           :enabled-p t)
          width)))))))

(defun llama-search-exact-query-p (query)
  "Baseline: /^[^/\\s]+\\/[^:\\s]+(?::[^\\s:]+)?$/u"
  (not
   (null
    (cl-ppcre:scan "^[^/\\s]+/[^:\\s]+(?::[^\\s:]+)?$" query))))

(defun llama-search-filter (search)
  (let ((query (llama-search-state-query search)))
    (setf
     (llama-search-state-filtered search)
     (if (zerop (length query))
         (copy-list (llama-search-state-results search))
         (selector-fuzzy-filter
          (llama-search-state-results search)
          query
          (lambda (model) (getf model :id))))
     (llama-search-state-selected search)
     (min
      (llama-search-state-selected search)
      (max 0 (1- (length (llama-search-state-filtered search))))))))

(defun llama-search-schedule (view)
  "Baseline scheduleSearch: debounce 500ms, cache by lowercase query,
stale responses discarded by generation and query identity."
  (let* ((search (llama-view-search view))
         (generation
          (incf (llama-search-state-generation search)))
         (query (llama-search-state-query search)))
    (flet ((render ()
             (llama-search-filter search)
             (llama-view-request-render view)))
      (cond
        ((< (length query) 2)
         (setf
          (llama-search-state-status search)
          "Type at least 2 characters")
         (render))
        ((gethash
          (string-downcase query)
          (llama-search-state-cache search))
         (let ((cached
                (gethash
                 (string-downcase query)
                 (llama-search-state-cache search))))
           (setf
            (llama-search-state-results search) cached
            (llama-search-state-status search)
            (if cached "" "No GGUF models found")
            (llama-search-state-selected search) 0)
           (render)))
        (t
         (setf
          (llama-search-state-status search)
          "Searching Hugging Face…")
         (render)
         (sb-thread:make-thread
          (lambda ()
            (sleep 0.5)
            (let ((stale-p
                   (sb-thread:with-mutex ((llama-view-lock view))
                     (or
                      (llama-view-closed-p view)
                      (/=
                       generation
                       (llama-search-state-generation
                        (llama-view-search view)))))))
              (unless stale-p
                (let ((results
                       (handler-case
                           (funcall
                            (llama-search-state-search-function
                             search)
                            query)
                         (error (cause)
                           (list
                            :error
                            (princ-to-string cause))))))
                  (sb-thread:with-mutex ((llama-view-lock view))
                    (let ((current (llama-view-search view)))
                      (unless
                          (or
                           (llama-view-closed-p view)
                           (/=
                            generation
                            (llama-search-state-generation current))
                           (not
                            (string=
                             query
                             (llama-search-state-query current))))
                        (if (eq (first results) :error)
                            (setf
                             (llama-search-state-results current) nil
                             (llama-search-state-status current)
                             (second results))
                            (progn
                              (setf
                               (gethash
                                (string-downcase query)
                                (llama-search-state-cache current))
                               results)
                              (setf
                               (llama-search-state-results current)
                               results
                               (llama-search-state-selected current) 0
                               (llama-search-state-status current)
                               (if results
                                   ""
                                   "No GGUF models found"))))
                        (llama-search-filter current)
                        (llama-view-request-render view)))))))
          :name "cadr-llama-search")))))))

(defun llama-search-handle-event (view event)
  (let ((search (llama-view-search view))
        (kind (cadr-tui:input-event-kind event)))
    (cond
      ((member kind '(:escape :cancel :interrupt))
       (llama-view-resolve view nil))
      ((member kind '(:up :down))
       (let ((filtered (llama-search-state-filtered search)))
         (when filtered
           (setf
            (llama-search-state-selected search)
            (if (eq kind :up)
                (mod
                 (1- (llama-search-state-selected search))
                 (length filtered))
                (mod
                 (1+ (llama-search-state-selected search))
                 (length filtered))))
         (llama-view-request-render view))))
      ((eq kind :enter)
       (let* ((query (llama-search-state-query search))
              (filtered (llama-search-state-filtered search))
              (selected
               (if (llama-search-exact-query-p query)
                   query
                   (and filtered
                        (getf
                         (nth
                          (llama-search-state-selected search)
                          filtered)
                         :id)))))
         (when selected
           (llama-view-resolve view selected))))
      (t
       (multiple-value-bind (action value)
           (cadr-tui:component-handle-event
            (llama-search-state-input search) event)
         (declare (ignore action value))
         (let ((query
                (string-trim
                 '(#\Space #\Tab #\Newline #\Return)
                 (cadr-tui:single-line-input-value
                  (llama-search-state-input search)))))
           (unless (string= query (llama-search-state-query search))
             (setf (llama-search-state-query search) query)
             (llama-search-schedule view))))))))

;;;; Public operations (ui.ts LlamaUi)

(defun llama-view-show-models (view server-url models)
  "Baseline showModels: loaded first, then id order; each row carries
modelDescription; the last row is the download entry; the server URL
shows dim above the list."
  (let ((sorted
         (sort
          (copy-list models)
          (lambda (left right)
            (let ((loaded-left
                   (if (eq (llama-model-info-status left) :loaded) 1 0))
                  (loaded-right
                   (if (eq (llama-model-info-status right) :loaded) 1 0)))
              (if (/= loaded-left loaded-right)
                  (> loaded-left loaded-right)
                  (startup-locale<
                   (llama-model-info-id left)
                   (llama-model-info-id right))))))))
    (setf
     (llama-view-body-prefix view)
     (component-text-lines
      (cadr-tui:theme-foreground :dim server-url :enabled-p t)
      (llama-view-width view)))
    (llama-view-set-select
     view "llama.cpp models"
     (append
      (mapcar
       (lambda (model)
         (cadr-tui:make-select-item
          :label (llama-model-info-id model)
          :description (llama-model-description model)
          :value model))
       sorted)
      (list
       (cadr-tui:make-select-item
        :label "Download model…"
        :description "Hugging Face owner/repository[:quant]"
        :value :download)))
     "load/unload/download" "close" :models)
    (llama-view-park view)))

(defun llama-view-select (view title options)
  "Baseline select(): bare label rows, min(n,12) visible."
  (setf (llama-view-body-prefix view) nil)
  (llama-view-set-select
   view title
   (mapcar
    (lambda (option)
      (cadr-tui:make-select-item :label option :value option))
    options)
   "select" "cancel" :plain)
  (llama-view-park view))

(defun llama-view-confirm (view title message)
  (string=
   (or
    (llama-view-select
     view (format nil "~A~%~A" title message) '("Yes" "No"))
    "")
   "Yes"))

(defun llama-view-connection-error (view server-url message)
  (if (string=
       (or
        (llama-view-select
         view
         (format nil "llama.cpp unavailable~%~A~2%~A" server-url message)
         '("Retry" "Close"))
        "")
       "Retry")
      :retry
      :close))

(defun llama-view-search-models (view search-function)
  (setf
   (llama-view-body-prefix view) nil
   (llama-view-search view)
   (make-llama-search-state
    :input (cadr-tui:make-single-line-input :prompt "> ")
    :search-function search-function)
   (llama-view-title view) "Download model"
   (llama-view-select-list view) nil
   (llama-view-footer view)
   (format
    nil "~A • ~A"
    (llama-view-key-hint view "tui.select.confirm" "select")
    (llama-view-key-hint view "tui.select.cancel" "back"))
   (llama-view-mode view) :search)
  (llama-view-refresh-body view)
  (llama-view-request-render view)
  (llama-view-park view))

(defun llama-view-show-status (view title message)
  (setf
   (llama-view-body-prefix view) nil
   (llama-view-title view) title
   (llama-view-status-message view) message
   (llama-view-select-list view) nil
   (llama-view-footer view) nil
   (llama-view-mode view) :status)
  (llama-view-refresh-body view)
  (llama-view-request-render view)
  nil)

(defun llama-view-progress-begin (view title model message)
  "Baseline progress(): shows the progress frame and parks until the
user stops it with the cancel key."
  (let ((existing
         (and
          (eq (llama-view-mode view) :progress)
          (llama-view-progress view))))
  (setf
   (llama-view-title view) title
   (llama-view-body-prefix view) nil
   (llama-view-select-list view) nil
   (llama-view-progress view)
   (list
    :model model
    :message message
    :ratio (and existing (getf existing :ratio))
    :detail (and existing (getf existing :detail)))
   (llama-view-footer view)
   (llama-view-key-hint view "tui.select.cancel" "stop")
   (llama-view-mode view) :progress))
  (llama-view-refresh-body view)
  (llama-view-request-render view)
  (llama-view-park view))

(defun llama-view-update-progress (view &key message ratio detail)
  "Baseline updateProgress(): no-op unless the progress frame is live."
  (when (eq (llama-view-mode view) :progress)
    (let ((state (llama-view-progress view)))
      (when message (setf (getf state :message) message))
      (when ratio (setf (getf state :ratio) ratio))
      (when detail (setf (getf state :detail) detail)))
    (llama-view-request-render view))
  nil)

;;;; Host bridge (ui.ts showLlamaUi + runWithProgress)

(defun show-llama-ui (context run)
  "Baseline showLlamaUi: open the custom component, run the flow on its
own thread (the baseline's void run(view)), close when it returns."
  (cadr-agent:extension-context-custom-component
   context
   (lambda (runtime theme keybindings done)
     (declare (ignore runtime theme))
     (let ((view (make-llama-view keybindings done)))
       (sb-thread:make-thread
        (lambda ()
          (handler-case
              (funcall run view)
            (error (cause)
              (funcall done nil)
              (error cause))))
        :name "cadr-llama-flow")
       view))))

(defun run-llama-with-progress
    (view &key title model initial-message
          cancel-title cancel-message run cancel)
  "Baseline runWithProgress: live progress with stop -> confirm ->
cancel semantics.  RUN takes an update callback; CANCEL is invoked only
after the user confirms the stop.  Returns (values result cancelled-p)."
  (let ((done nil)
        (result nil)
        (failure nil)
        (lock (sb-thread:make-mutex :name "llama-progress"))
        (condition (sb-thread:make-waitqueue :name "llama-progress")))
    (sb-thread:make-thread
     (lambda ()
       (multiple-value-bind (value error)
           (ignore-errors
            (funcall
             run
             (lambda (&key message ratio detail)
               (llama-view-update-progress
                view
                :message message
                :ratio ratio
                :detail detail))))
         (sb-thread:with-mutex (lock)
           (if error
               (setf failure error)
               (setf result value))
           (setf done t)
           (sb-thread:condition-broadcast condition))
         ;; Wake the parked progress frame so the race resolves.
         (llama-view-resolve view :settled)))
     :name "cadr-llama-progress-run")
    (loop
      (let ((outcome
             (llama-view-progress-begin
              view title model initial-message)))
        (cond
          ((eq outcome :settled)
           (return))
          ((eq outcome :stop)
           (cond
             ((sb-thread:with-mutex (lock) done)
              (return))
             ((llama-view-confirm view cancel-title cancel-message)
              (when cancel (funcall cancel))
              (sb-thread:with-mutex (lock)
                (loop until done
                      do (sb-thread:condition-wait condition lock)))
              (return-from run-llama-with-progress (values nil t)))
             (t
              ;; Not confirmed: the next loop iteration re-parks on the
              ;; progress frame, like the baseline's continue.
              nil))))))
    (when failure (error failure))
    (values result nil)))
