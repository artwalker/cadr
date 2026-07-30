(in-package #:cadr-agent)

;;; Immutable effective registry containers

(defstruct extension-snapshot
  (bundles nil :type list)
  (tools nil :type list)
  (commands nil :type list)
  (templates nil :type list)
  (hooks (make-hash-table :test #'eq) :type hash-table)
  (conflicts nil :type list)
  (active-count 0 :type (integer 0 *))
  (retired-p nil :type boolean)
  (released-p nil :type boolean))

(defstruct (extension-host
            (:constructor %make-extension-host))
  (cwd (uiop:getcwd) :type pathname)
  (mode :repl :type symbol)
  (notify-function
   (lambda (message level)
     (format *error-output*
             "~&extension[~(~A~)]> ~A~%"
             level message))
   :type function)
  reload-function
  agent
  (snapshot (make-extension-snapshot)
            :type extension-snapshot)
  (lock (sb-thread:make-mutex
         :name "cadr-extension-host"))
  (hook-lock (sb-thread:make-mutex
              :name "cadr-extension-hooks")))

;;; Public handler values

(defstruct (extension-context
            (:constructor %make-extension-context)
            (:conc-name %extension-context-))
  host
  source-path
  (active-p t :type boolean))

(defstruct (extension-event
            (:constructor %make-extension-event)
            (:conc-name %extension-event-))
  type
  turn-index
  message
  tool-call
  tool-result
  tool-results
  appended-messages)

(defstruct (extension-hook-result
            (:constructor %make-extension-hook-result))
  replacement
  (replacement-p nil :type boolean)
  (append-messages nil :type list)
  (block-p nil :type boolean)
  reason)

(defun make-extension-hook-result
    (&key
       (replacement nil replacement-p)
       append-messages
       block-p
       reason)
  (%make-extension-hook-result
   :replacement replacement
   :replacement-p replacement-p
   :append-messages append-messages
   :block-p (not (null block-p))
   :reason reason))

(defun assert-active-extension-context (context)
  (unless
      (and (typep context 'extension-context)
           (%extension-context-active-p context))
    (error
     'stale-extension-context
     :message
     "Extension context is stale outside its handler or after reload"))
  context)

(defun extension-context-cwd (context)
  (assert-active-extension-context context)
  (extension-host-cwd (%extension-context-host context)))

(defun extension-context-agent (context)
  (assert-active-extension-context context)
  (extension-host-agent (%extension-context-host context)))

(defun extension-context-session (context)
  (let ((agent (extension-context-agent context)))
    (and agent (agent-session agent))))

(defun extension-context-source-path (context)
  (assert-active-extension-context context)
  (%extension-context-source-path context))

(defun extension-context-mode (context)
  (assert-active-extension-context context)
  (extension-host-mode (%extension-context-host context)))

(defun extension-context-notify
    (context message &key (level :info))
  (assert-active-extension-context context)
  (unless (member level '(:info :warning :error))
    (error
     'extension-execution-error
     :message
     (format nil "Invalid extension notification level: ~S"
             level)))
  (funcall
   (extension-host-notify-function
    (%extension-context-host context))
   (princ-to-string message)
   level)
  nil)

(defun extension-context-compact
    (context &key (force-p t))
  (let ((agent (extension-context-agent context)))
    (unless agent
      (error
       'extension-execution-error
       :message "Extension context has no attached agent"))
    (compact-agent agent :force-p force-p)))

(defun extension-context-reload (context)
  (assert-active-extension-context context)
  (let* ((host (%extension-context-host context))
         (reload (extension-host-reload-function host)))
    (unless reload
      (error
       'extension-execution-error
       :message "Extension reload is unavailable in this host"))
    (prog1
        (funcall reload)
      (setf (%extension-context-active-p context) nil))))

(defun extension-event-type (event)
  (%extension-event-type event))

(defun extension-event-turn-index (event)
  (%extension-event-turn-index event))

(defun extension-event-message (event)
  (%extension-event-message event))

(defun extension-event-tool-call (event)
  (%extension-event-tool-call event))

(defun extension-event-tool-result (event)
  (%extension-event-tool-result event))

(defun extension-event-tool-results (event)
  (%extension-event-tool-results event))

;;; Registration model

(defstruct extension-bundle
  (id "" :type string)
  (path "" :type string)
  (scope :global :type symbol)
  (rank 0 :type integer)
  (order 0 :type integer)
  package
  (tools nil :type list)
  (commands nil :type list)
  (hooks nil :type list)
  (templates nil :type list)
  (snapshot-references 0 :type (integer 0 *)))

(defstruct extension-tool-definition
  name
  description
  parameters
  execution-mode
  handler
  bundle)

(defstruct extension-command-definition
  name
  description
  argument-hint
  handler
  bundle)

(defstruct extension-hook-definition
  event
  priority
  handler
  bundle
  order)

(defstruct extension-template-definition
  name
  description
  argument-hint
  template
  bundle)

(defvar *extension-registration-bundle* nil)

(defun call-with-extension-registration (bundle function)
  (let ((*extension-registration-bundle* bundle))
    (funcall function)))

(defun require-extension-registration-bundle ()
  (or
   *extension-registration-bundle*
   (error
    'extension-registration-error
    :message
    "Extension definitions are only valid while loading an extension")))

(defun valid-extension-resource-name-p (name)
  (and
   (stringp name)
   (plusp (length name))
   (every
    (lambda (character)
      (or
       (and (char>= character #\a)
            (char<= character #\z))
       (digit-char-p character)
       (member character '(#\- #\_ #\:))))
    name)))

(defun validate-extension-resource-name (kind name)
  (unless (valid-extension-resource-name-p name)
    (error
     'extension-registration-error
     :message
     (format nil
             "Invalid ~A name ~S; use lowercase ASCII letters, digits, -, _, or :"
             kind name)))
  name)

(defun validate-extension-schema (name schema)
  (unless (hash-table-p schema)
    (error
     'extension-registration-error
     :message
     (format nil "Tool ~A parameters must be a JSON Schema hash-table"
             name)))
  (handler-case
      (validate-json-schema-definition schema)
    (error (condition)
      (error
       'extension-registration-error
       :cause condition
       :message
       (format nil "Tool ~A has an invalid JSON Schema: ~A"
               name condition))))
  schema)

(defun ensure-unique-extension-definition
    (definitions name key kind)
  (when (find name definitions :key key :test #'string=)
    (error
     'extension-registration-error
     :message
     (format nil "~A ~A is registered more than once in the same extension"
             kind name))))

(defun register-extension-tool
    (name description parameters execution-mode handler)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "tool" name)
    (unless (stringp description)
      (error
       'extension-registration-error
       :message (format nil "Tool ~A description must be a string"
                        name)))
    (validate-extension-schema name parameters)
    (unless (member execution-mode '(:parallel :sequential))
      (error
       'extension-registration-error
       :message
       (format nil "Tool ~A execution mode must be :parallel or :sequential"
               name)))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message (format nil "Tool ~A handler must be a function"
                        name)))
    (ensure-unique-extension-definition
     (extension-bundle-tools bundle)
     name
     #'extension-tool-definition-name
     "Tool")
    (setf
     (extension-bundle-tools bundle)
     (nconc
      (extension-bundle-tools bundle)
      (list
       (make-extension-tool-definition
        :name name
        :description description
        :parameters parameters
        :execution-mode execution-mode
        :handler handler
        :bundle bundle)))))
  name)

(defun register-extension-command
    (name description argument-hint handler)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "command" name)
    (unless (or (null description) (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A description must be a string or NIL"
               name)))
    (unless (or (null argument-hint) (stringp argument-hint))
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A argument hint must be a string or NIL"
               name)))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A handler must be a function"
               name)))
    (ensure-unique-extension-definition
     (extension-bundle-commands bundle)
     name
     #'extension-command-definition-name
     "Command")
    (setf
     (extension-bundle-commands bundle)
     (nconc
      (extension-bundle-commands bundle)
      (list
       (make-extension-command-definition
        :name name
        :description description
        :argument-hint argument-hint
        :handler handler
        :bundle bundle)))))
  name)

(defparameter +extension-hook-events+
  '(:turn-start :turn-end
    :tool-call-before :tool-call-after))

(defun register-extension-hook
    (event priority handler)
  (let ((bundle (require-extension-registration-bundle)))
    (unless (member event +extension-hook-events+)
      (error
       'extension-registration-error
       :message
       (format nil "Unsupported extension hook event: ~S"
               event)))
    (unless (integerp priority)
      (error
       'extension-registration-error
       :message "Extension hook priority must be an integer"))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message "Extension hook handler must be a function"))
    (setf
     (extension-bundle-hooks bundle)
     (nconc
      (extension-bundle-hooks bundle)
      (list
       (make-extension-hook-definition
        :event event
        :priority priority
        :handler handler
        :bundle bundle
        :order (length (extension-bundle-hooks bundle)))))))
  event)

(defun register-extension-template
    (name description argument-hint template)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "prompt template" name)
    (unless (or (null description) (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A description must be a string or NIL"
               name)))
    (unless (or (null argument-hint) (stringp argument-hint))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A argument hint must be a string or NIL"
               name)))
    (unless (or (stringp template) (functionp template))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A must be a string or function"
               name)))
    (ensure-unique-extension-definition
     (extension-bundle-templates bundle)
     name
     #'extension-template-definition-name
     "Prompt template")
    (setf
     (extension-bundle-templates bundle)
     (nconc
      (extension-bundle-templates bundle)
      (list
       (make-extension-template-definition
        :name name
        :description description
        :argument-hint argument-hint
        :template template
        :bundle bundle)))))
  name)

(defmacro define-tool
    (name &key description parameters
                 (execution-mode :parallel)
                 handler)
  `(register-extension-tool
    ,name ,description ,parameters ,execution-mode ,handler))

(defmacro define-command
    (name &key description argument-hint handler)
  `(register-extension-command
    ,name ,description ,argument-hint ,handler))

(defmacro define-event-hook
    (event &key (priority 0) handler)
  `(register-extension-hook ,event ,priority ,handler))

(defmacro define-prompt-template
    (name &key description argument-hint template)
  `(register-extension-template
    ,name ,description ,argument-hint ,template))

(defun make-extension-host
    (&key
       (cwd (uiop:getcwd))
       (mode :repl)
       notify-function
       reload-function)
  (%make-extension-host
   :cwd
   (uiop:ensure-directory-pathname
    (pathname cwd))
   :mode mode
   :notify-function
   (or
    notify-function
    (lambda (message level)
      (format *error-output*
              "~&extension[~(~A~)]> ~A~%"
              level message)
      (finish-output *error-output*)))
   :reload-function reload-function))

(defun extension-definition-origin (definition)
  (extension-bundle-path
   (etypecase definition
     (extension-tool-definition
      (extension-tool-definition-bundle definition))
     (extension-command-definition
      (extension-command-definition-bundle definition))
     (extension-hook-definition
      (extension-hook-definition-bundle definition))
     (extension-template-definition
      (extension-template-definition-bundle definition)))))

(defun extension-conflict
    (kind name winner loser)
  (format nil
          "~A ~S from ~A conflicts with ~A; using ~A"
          kind name
          (extension-definition-origin loser)
          (extension-definition-origin winner)
          (extension-definition-origin winner)))

(defun add-first-definition
    (table ordered definition key kind conflicts)
  (let* ((name (funcall key definition))
         (winner (gethash name table)))
    (if winner
        (push
         (extension-conflict kind name winner definition)
         (symbol-value conflicts))
        (progn
          (setf (gethash name table) definition)
          (setf (symbol-value ordered)
                (nconc
                 (symbol-value ordered)
                 (list definition)))))))

(defun make-extension-snapshot-from-bundles (bundles)
  (let ((tool-table (make-hash-table :test #'equal))
        (command-table (make-hash-table :test #'equal))
        (template-table (make-hash-table :test #'equal))
        (*tools* nil)
        (*commands* nil)
        (*templates* nil)
        (*conflicts* nil)
        (hooks (make-hash-table :test #'eq)))
    (declare
     (special *tools* *commands* *templates*
              *conflicts*))
    (dolist (bundle bundles)
      (dolist (definition (extension-bundle-tools bundle))
        (add-first-definition
         tool-table '*tools* definition
         #'extension-tool-definition-name
         "Tool" '*conflicts*))
      (dolist (definition (extension-bundle-commands bundle))
        (add-first-definition
         command-table '*commands* definition
         #'extension-command-definition-name
         "Command" '*conflicts*))
      (dolist (definition (extension-bundle-templates bundle))
        (add-first-definition
         template-table '*templates* definition
         #'extension-template-definition-name
         "Prompt template" '*conflicts*))
      (dolist (definition (extension-bundle-hooks bundle))
        (push definition
              (gethash
               (extension-hook-definition-event definition)
               hooks))))
    (maphash
     (lambda (event definitions)
       (declare (ignore event))
       (setf definitions (nreverse definitions))
       (setf
        (gethash
         (extension-hook-definition-event
          (first definitions))
         hooks)
        (stable-sort
         definitions
         #'<
         :key #'extension-hook-definition-priority)))
     hooks)
    (make-extension-snapshot
     :bundles (copy-list bundles)
     :tools *tools*
     :commands *commands*
     :templates *templates*
     :hooks hooks
     :conflicts (nreverse *conflicts*))))

(defun release-extension-snapshot (snapshot)
  (unless (extension-snapshot-released-p snapshot)
    (setf (extension-snapshot-released-p snapshot) t)
    (dolist (bundle (extension-snapshot-bundles snapshot))
      (decf (extension-bundle-snapshot-references bundle))
      (when
          (and
           (zerop
            (extension-bundle-snapshot-references bundle))
           (extension-bundle-package bundle)
           (find-package
            (package-name
             (extension-bundle-package bundle))))
        (ignore-errors
          (delete-package
           (extension-bundle-package bundle)))))))

(defun maybe-release-extension-snapshot (snapshot)
  (when
      (and
       (extension-snapshot-retired-p snapshot)
       (zerop (extension-snapshot-active-count snapshot)))
    (release-extension-snapshot snapshot)))

(defun replace-extension-bundles (host bundles)
  (let ((snapshot
          (make-extension-snapshot-from-bundles bundles))
        (old nil))
    (sb-thread:with-mutex
        ((extension-host-lock host))
      (dolist (bundle
               (extension-snapshot-bundles snapshot))
        (incf
         (extension-bundle-snapshot-references bundle)))
      (setf old (extension-host-snapshot host)
            (extension-host-snapshot host) snapshot)
      (setf (extension-snapshot-retired-p old) t)
      (maybe-release-extension-snapshot old))
    (when (extension-host-agent host)
      (refresh-agent-extension-tools
       (extension-host-agent host)))
    (copy-list
     (extension-snapshot-conflicts snapshot))))

(defun acquire-extension-snapshot
    (host &optional snapshot)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (let ((resolved
            (or snapshot
                (extension-host-snapshot host))))
      (incf (extension-snapshot-active-count resolved))
      resolved)))

(defun release-acquired-extension-snapshot
    (host snapshot)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (decf (extension-snapshot-active-count snapshot))
    (maybe-release-extension-snapshot snapshot)))

(defun call-with-extension-definition
    (host snapshot definition function)
  (let* ((held
           (acquire-extension-snapshot host snapshot))
         (context
           (%make-extension-context
            :host host
            :source-path
            (extension-definition-origin definition))))
    (unwind-protect
         (funcall function context)
      (setf (%extension-context-active-p context) nil)
      (release-acquired-extension-snapshot host held))))

(defun notify-extension-failure
    (host definition phase condition)
  (funcall
   (extension-host-notify-function host)
   (format nil "~A ~A failed in ~A: ~A"
           phase
           (extension-definition-origin definition)
           (typecase definition
             (extension-tool-definition
              (extension-tool-definition-name definition))
             (extension-command-definition
              (extension-command-definition-name definition))
             (extension-hook-definition
              (extension-hook-definition-event definition))
             (extension-template-definition
              (extension-template-definition-name definition)))
           condition)
   :error))

(defun extension-host-current-snapshot (host)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (extension-host-snapshot host)))

(defun extension-host-conflicts (host)
  (copy-list
   (extension-snapshot-conflicts
    (extension-host-current-snapshot host))))

(defun extension-host-tools (host)
  (let ((snapshot
          (extension-host-current-snapshot host)))
    (loop
      for definition in
      (extension-snapshot-tools snapshot)
      collect
      (let ((captured definition)
            (captured-snapshot snapshot))
        (cadr-ai:make-tool
         :name
         (extension-tool-definition-name captured)
         :description
         (extension-tool-definition-description captured)
         :parameters
         (extension-tool-definition-parameters captured)
         :execution-mode
         (extension-tool-definition-execution-mode captured)
         :executor
         (lambda (call-id arguments)
           (handler-case
               (call-with-extension-definition
                host captured-snapshot captured
                (lambda (context)
                  (funcall
                   (extension-tool-definition-handler
                    captured)
                   call-id arguments context)))
             (extension-execution-error (condition)
               (error condition))
             (condition (condition)
               (error
                'extension-execution-error
                :cause condition
                :message
                (format nil
                        "Extension tool ~A from ~A failed: ~A"
                        (extension-tool-definition-name
                         captured)
                        (extension-definition-origin captured)
                        condition))))))))))

(defun attach-extension-host (host agent)
  (setf (extension-host-agent host) agent
        (agent-extension-host agent) host)
  (refresh-agent-extension-tools agent)
  host)

;;; Commands and prompt templates

(defun find-extension-command (snapshot name)
  (find name
        (extension-snapshot-commands snapshot)
        :key #'extension-command-definition-name
        :test #'string=))

(defun invoke-extension-command
    (host name arguments)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definition
           (find-extension-command snapshot name)))
    (unless definition
      (return-from invoke-extension-command nil))
    (handler-case
        (call-with-extension-definition
         host snapshot definition
         (lambda (context)
           (funcall
            (extension-command-definition-handler definition)
            arguments context)))
      (condition (condition)
        (notify-extension-failure
         host definition "Command" condition)))
    t))

(defun parse-extension-command-arguments (text)
  (let ((arguments nil)
        (current
          (make-array
           16 :element-type 'character
           :adjustable t :fill-pointer 0))
        (quote nil))
    (labels
        ((finish-current ()
           (when (plusp (fill-pointer current))
             (push (copy-seq current) arguments)
             (setf (fill-pointer current) 0))))
      (loop for character across text
            do
            (cond
              (quote
               (if (char= character quote)
                   (setf quote nil)
                   (vector-push-extend character current)))
              ((or (char= character #\")
                   (char= character #\'))
               (setf quote character))
              ((member character
                       '(#\Space #\Tab #\Newline #\Return))
               (finish-current))
              (t
               (vector-push-extend character current))))
      (finish-current))
    (nreverse arguments)))

(defun join-extension-arguments (arguments)
  (format nil "~{~A~^ ~}" arguments))

(defun extension-argument (arguments index)
  (and
   (plusp index)
   (nth (1- index) arguments)))

(defun parse-positive-index (text)
  (and
   (plusp (length text))
   (every #'digit-char-p text)
   (parse-integer text)))

(defun expand-braced-template-token
    (token arguments)
  (let ((default-position (search ":-" token))
        (slice-prefix-p
          (and
           (>= (length token) 2)
           (char= (char token 0) #\@)
           (char= (char token 1) #\:))))
    (cond
      (default-position
       (let* ((target
                (subseq token 0 default-position))
              (default
                (subseq token (+ default-position 2)))
              (value
                (cond
                  ((or (string= target "@")
                       (string= target "ARGUMENTS"))
                   (join-extension-arguments arguments))
                  (t
                   (let ((index
                           (parse-positive-index target)))
                     (and index
                          (extension-argument
                           arguments index)))))))
         (if (and value (plusp (length value)))
             value
             default)))
      (slice-prefix-p
       (let* ((parts
                (loop with start = 2
                      for position =
                        (position #\: token :start start)
                      collect
                      (subseq token start position)
                      while position
                      do (setf start (1+ position))))
              (start
                (parse-positive-index (first parts)))
              (length-value
                (and (second parts)
                     (parse-positive-index
                      (second parts)))))
         (if start
             (join-extension-arguments
              (if length-value
                  (subseq
                   arguments
                   (min (1- start)
                        (length arguments))
                   (min
                    (+ (1- start) length-value)
                    (length arguments)))
                  (nthcdr
                   (min (1- start)
                        (length arguments))
                   arguments)))
             nil)))
      ((or (string= token "@")
           (string= token "ARGUMENTS"))
       (join-extension-arguments arguments))
      (t
       (let ((index (parse-positive-index token)))
         (and index
              (or
               (extension-argument arguments index)
               "")))))))

(defun expand-simple-template-token
    (template start arguments)
  (cond
    ((and
      (< (1+ start) (length template))
      (char= (char template (1+ start)) #\@))
     (values
      (join-extension-arguments arguments)
      (+ start 2)))
    ((and
      (<= (+ start 10) (length template))
      (string=
       "ARGUMENTS"
       template
       :start2 (1+ start)
       :end2 (+ start 10)))
     (values
      (join-extension-arguments arguments)
      (+ start 10)))
    (t
     (let ((end (1+ start)))
       (loop
         while
         (and
          (< end (length template))
          (digit-char-p (char template end)))
         do (incf end))
       (if (> end (1+ start))
           (values
            (or
             (extension-argument
              arguments
              (parse-integer
               template
               :start (1+ start)
               :end end))
             "")
            end)
           (values "$" (1+ start)))))))

(defun substitute-extension-template
    (template arguments)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length template))
          do
          (if (char/= (char template index) #\$)
              (progn
                (write-char (char template index) output)
                (incf index))
              (if
                  (and
                   (< (1+ index) (length template))
                   (char= (char template (1+ index)) #\{))
                  (let ((close
                          (position
                           #\} template
                           :start (+ index 2))))
                    (if close
                        (let ((replacement
                                (expand-braced-template-token
                                 (subseq
                                  template
                                  (+ index 2)
                                  close)
                                 arguments)))
                          (if replacement
                              (write-string replacement output)
                              (write-string
                               (subseq
                                template index
                                (1+ close))
                               output))
                          (setf index (1+ close)))
                        (progn
                          (write-char #\$ output)
                          (incf index))))
                  (multiple-value-bind
                        (replacement next)
                      (expand-simple-template-token
                       template index arguments)
                    (write-string replacement output)
                    (setf index next)))))))

(defun split-slash-invocation (text)
  (unless
      (and
       (plusp (length text))
       (char= (char text 0) #\/))
    (return-from split-slash-invocation
      (values nil nil)))
  (let ((separator
          (position-if
           (lambda (character)
             (member character
                     '(#\Space #\Tab #\Newline #\Return)))
           text
           :start 1)))
    (values
     (subseq text 1 separator)
     (if separator
         (string-left-trim
          '(#\Space #\Tab #\Newline #\Return)
          (subseq text separator))
         ""))))

(defun expand-extension-prompt (host text)
  (multiple-value-bind (name argument-text)
      (split-slash-invocation text)
    (unless name
      (return-from expand-extension-prompt
        (values text nil)))
    (let* ((snapshot
             (extension-host-current-snapshot host))
           (definition
             (find
              name
              (extension-snapshot-templates snapshot)
              :key #'extension-template-definition-name
              :test #'string=)))
      (unless definition
        (return-from expand-extension-prompt
          (values text nil)))
      (let ((arguments
              (parse-extension-command-arguments
               argument-text)))
        (handler-case
            (values
             (if
                 (stringp
                  (extension-template-definition-template
                   definition))
                 (substitute-extension-template
                  (extension-template-definition-template
                   definition)
                  arguments)
                 (call-with-extension-definition
                  host snapshot definition
                  (lambda (context)
                    (let ((expanded
                            (funcall
                             (extension-template-definition-template
                              definition)
                             arguments context)))
                      (unless (stringp expanded)
                        (error
                         "Prompt template returned ~S instead of a string"
                         expanded))
                      expanded))))
             t)
          (condition (condition)
            (notify-extension-failure
             host definition "Prompt template" condition)
            (values text t)))))))

;;; Hook dispatch

(defun extension-message-p (value)
  (or
   (typep value 'cadr-ai:user-message)
   (typep value 'cadr-ai:assistant-message)
   (typep value 'cadr-ai:tool-result-message)))

(defun assistant-tool-call-signature (message)
  (loop
    for block in
    (cadr-ai:assistant-message-content message)
    when (typep block 'cadr-ai:tool-call)
      collect
      (list
       (cadr-ai:tool-call-id block)
       (cadr-ai:tool-call-name block))))

(defun valid-extension-replacement-p
    (event-type replacement original)
  (case event-type
    (:turn-start
     (or
      (null replacement)
      (typep replacement 'cadr-ai:user-message)))
    (:turn-end
     (and
      (typep replacement 'cadr-ai:assistant-message)
      (equal
       (assistant-tool-call-signature replacement)
       (assistant-tool-call-signature original))))
    (:tool-call-before
     (and
      (typep replacement 'cadr-ai:tool-call)
      (string=
       (cadr-ai:tool-call-id replacement)
       (cadr-ai:tool-call-id original))))
    (:tool-call-after
     (and
      (typep replacement 'cadr-ai:tool-result-message)
      (string=
       (cadr-ai:tool-result-message-tool-call-id replacement)
       (cadr-ai:tool-result-message-tool-call-id original))
      (string=
       (cadr-ai:tool-result-message-tool-name replacement)
       (cadr-ai:tool-result-message-tool-name original))))
    (otherwise nil)))

(defun make-hook-event
    (type turn-index primary tool-call
     tool-result tool-results appended)
  (%make-extension-event
   :type type
   :turn-index turn-index
   :message
   (and (member type '(:turn-start :turn-end))
        primary)
   :tool-call
   (if (eq type :tool-call-before)
       primary
       tool-call)
   :tool-result
   (if (eq type :tool-call-after)
       primary
       tool-result)
   :tool-results tool-results
   :appended-messages appended))

(defun run-extension-hooks
    (host event-type
     &key
       turn-index
       message
       tool-call
       tool-result
       tool-results)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definitions
           (copy-list
            (gethash event-type
                     (extension-snapshot-hooks
                      snapshot))))
         (primary
           (case event-type
             ((:turn-start :turn-end) message)
             (:tool-call-before tool-call)
             (:tool-call-after tool-result)))
         (appended nil)
         (blocked-p nil)
         (reason nil))
    (let ((held
            (acquire-extension-snapshot
             host snapshot)))
      (unwind-protect
           (sb-thread:with-mutex
               ((extension-host-hook-lock host))
             (dolist (definition definitions)
               (handler-case
                   (let ((result
                           (call-with-extension-definition
                            host snapshot definition
                            (lambda (context)
                              (funcall
                               (extension-hook-definition-handler
                                definition)
                               (make-hook-event
                                event-type turn-index primary
                                tool-call tool-result tool-results
                                appended)
                               context)))))
                     (when result
                       (unless
                           (typep
                            result
                            'extension-hook-result)
                         (error
                          "Hook returned ~S instead of EXTENSION-HOOK-RESULT or NIL"
                          result))
                       (let* ((replacement-p
                                (extension-hook-result-replacement-p
                                 result))
                              (replacement
                                (if replacement-p
                                    (extension-hook-result-replacement
                                     result)
                                    primary))
                              (messages
                                (extension-hook-result-append-messages
                                 result))
                              (result-block-p
                                (extension-hook-result-block-p
                                 result))
                              (result-reason
                                (extension-hook-result-reason
                                 result)))
                         (when
                             (and
                              replacement-p
                              (not
                               (valid-extension-replacement-p
                                event-type replacement
                                primary)))
                           (error
                            "Invalid replacement for ~S"
                            event-type))
                         (unless
                             (and
                              (listp messages)
                              (every
                               #'extension-message-p
                               messages))
                           (error
                            "Hook append-messages must be a list of CADR-AI messages"))
                         (when result-block-p
                           (unless
                               (eq
                                event-type
                                :tool-call-before)
                             (error
                              "Only :tool-call-before hooks may block"))
                           (unless
                               (or
                                (null result-reason)
                                (stringp result-reason))
                             (error
                              "Hook block reason must be a string or NIL")))
                         ;; Commit only after the entire hook result validates.
                         (setf primary replacement
                               appended
                               (nconc
                                appended
                                (copy-list messages)))
                         (when result-block-p
                           (setf
                            blocked-p t
                            reason
                            (or
                             result-reason
                             "Tool execution was blocked"))
                           (return)))))
                 (condition (condition)
                   (notify-extension-failure
                    host definition "Hook" condition)))))
        (release-acquired-extension-snapshot
         host held)))
    (values primary appended blocked-p reason)))
