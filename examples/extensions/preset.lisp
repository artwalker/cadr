(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *preset-definitions* (make-hash-table :test #'equal))
(defvar *preset-active-name* nil)
(defvar *preset-active-definition* nil)
(defvar *preset-original-thinking* nil)
(defvar *preset-original-tools* nil)

(defun preset-copy-object-into (source target)
  (when (hash-table-p source)
    (maphash (lambda (name value) (setf (gethash name target) value)) source))
  target)

(defun preset-read-file (path)
  (when (probe-file path)
    (handler-case
        (cadr-ai::parse-json
         (uiop:read-file-string path :external-format :utf-8))
      (error (condition)
        (warn "Failed to load presets from ~A: ~A" path condition)
        nil))))

(defun preset-load (cwd)
  (let ((definitions (make-hash-table :test #'equal)))
    (preset-copy-object-into
     (preset-read-file (merge-pathnames ".cadr/presets.json"
                                       (user-homedir-pathname)))
     definitions)
    (preset-copy-object-into
     (preset-read-file (merge-pathnames ".cadr/presets.json" cwd))
     definitions)
    definitions))

(defun preset-names ()
  (sort (loop for name being the hash-keys of *preset-definitions*
              collect name)
        #'string<))

(defun preset-vector-list (value)
  (cond ((vectorp value) (coerce value 'list))
        ((listp value) value)
        (t nil)))

(defun preset-find-model (context provider id)
  (find-if
   (lambda (model)
     (and (string-equal provider
                        (symbol-name (cadr-ai:model-provider model)))
          (string= id (cadr-ai:model-id model))))
   (cadr-agent:extension-context-scoped-models context)))

(defun preset-update-status (context)
  (cadr-agent:extension-context-set-status
   context "preset"
   (and *preset-active-name*
        (format nil "preset:~A" *preset-active-name*))))

(defun preset-apply (name definition context)
  (unless *preset-active-name*
    (setf *preset-original-thinking*
          (cadr-agent:extension-api-get-thinking-level *example-api*)
          *preset-original-tools*
          (cadr-agent:extension-api-get-active-tools *example-api*)))
  (let ((provider (cadr-ai::json-get definition "provider"))
        (model-id (cadr-ai::json-get definition "model"))
        (thinking (cadr-ai::json-get definition "thinkingLevel"))
        (tools (preset-vector-list
                (cadr-ai::json-get definition "tools"))))
    (when (and provider model-id)
      (let ((model (preset-find-model context provider model-id)))
        (if model
            (cadr-agent:extension-api-set-model *example-api* model)
            (cadr-agent:extension-context-notify
             context
             (format nil "Preset ~S: Model ~A/~A not found"
                     name provider model-id)
             :level :warning))))
    (when thinking
      (cadr-agent:extension-api-set-thinking-level
       *example-api* (intern (string-upcase thinking) :keyword)))
    (when tools
      (let* ((available
               (mapcar (lambda (tool) (getf tool :name))
                       (cadr-agent:extension-api-get-all-tools *example-api*)))
             (valid (remove-if-not
                     (lambda (tool) (member tool available :test #'string=))
                     tools))
             (invalid (set-difference tools valid :test #'string=)))
        (when invalid
          (cadr-agent:extension-context-notify
           context
           (format nil "Preset ~S: Unknown tools: ~{~A~^, ~}" name invalid)
           :level :warning))
        (when valid
          (cadr-agent:extension-api-set-active-tools *example-api* valid))))
    (setf *preset-active-name* name
          *preset-active-definition* definition)
    (preset-update-status context)
    t))

(defun preset-clear (context)
  (when *preset-original-thinking*
    (cadr-agent:extension-api-set-thinking-level
     *example-api* *preset-original-thinking*))
  (cadr-agent:extension-api-set-active-tools
   *example-api* (or *preset-original-tools* '("read" "bash" "edit" "write")))
  (setf *preset-active-name* nil *preset-active-definition* nil)
  (preset-update-status context)
  (cadr-agent:extension-context-notify
   context "Preset cleared, defaults restored"))

(defun preset-select-or-apply (arguments context)
  (let* ((requested (example-trim arguments))
         (names (preset-names))
         (choice
           (if (plusp (length requested))
               requested
               (cadr-agent:extension-context-select
                context "Select Preset"
                (append
                 (mapcar
                  (lambda (name)
                    (if (string= name (or *preset-active-name* ""))
                        (format nil "~A (active)" name)
                        name))
                  names)
                 '("(none)"))))))
    (when choice
      (let ((name
              (if (uiop:string-suffix-p " (active)" choice)
                  (subseq choice 0 (- (length choice) 9))
                  choice)))
        (cond
          ((string= name "(none)") (preset-clear context))
          ((gethash name *preset-definitions*)
           (preset-apply name (gethash name *preset-definitions*) context)
           (cadr-agent:extension-context-notify
            context (format nil "Preset ~S activated" name)))
          (t
           (cadr-agent:extension-context-notify
            context
            (format nil "Unknown preset ~S. Available: ~:[(none defined)~;~:*~{~A~^, ~}~]"
                    name names)
            :level :error)))))))

(cadr-agent:define-flag
 "preset" :description "Preset configuration to use"
 :type :string :default nil)

(cadr-agent:define-shortcut
 "ctrl+shift+u" :description "Cycle presets"
 :handler
 (lambda (context)
   (let* ((names (cons "(none)" (preset-names)))
          (current (or *preset-active-name* "(none)"))
          (position (or (position current names :test #'string=) -1))
          (next (nth (mod (1+ position) (length names)) names)))
     (preset-select-or-apply next context))))

(cadr-agent:define-command
 "preset" :description "Switch preset configuration"
 :handler #'preset-select-or-apply)

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (let ((instructions
           (and *preset-active-definition*
                (cadr-ai::json-get
                 *preset-active-definition* "instructions"))))
     (when instructions
       (list :system-prompt
             (format nil "~A~%~%~A"
                     (example-event-value event :system-prompt)
                     instructions))))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (setf *preset-definitions*
         (preset-load (cadr-agent:extension-context-cwd context)))
   (let ((flag (cadr-agent:extension-api-get-flag *example-api* "preset")))
     (when (and (stringp flag) (plusp (length flag)))
       (preset-select-or-apply flag context)))
   (unless *preset-active-name*
     (dolist (entry (example-session-entries context))
       (when (and (eq (cadr-agent:session-entry-type entry) :custom)
                  (string= (or (cadr-agent:session-entry-custom-type entry) "")
                           "preset-state"))
         (let* ((data (cadr-agent:session-entry-data entry))
                (name (getf data :name)))
           (when (gethash name *preset-definitions*)
             (setf *preset-active-name* name
                   *preset-active-definition*
                   (gethash name *preset-definitions*)))))))
   (preset-update-status context)))

(cadr-agent:define-event-hook
 :turn-start
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (when *preset-active-name*
     (cadr-agent:extension-api-append-entry
      *example-api* "preset-state" (list :name *preset-active-name*)))))
