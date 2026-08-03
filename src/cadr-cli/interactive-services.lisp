(in-package #:cadr-cli)

(defparameter +osc-133-start+
  (format nil "~C]133;A~C" #\Escape (code-char 7)))
(defparameter +osc-133-end+
  (format nil "~C]133;B~C" #\Escape (code-char 7)))
(defparameter +osc-133-final+
  (format nil "~C]133;C~C" #\Escape (code-char 7)))

(defun output-padding-string (output-pad)
  (make-string
   (if (member output-pad '(0 1))
       output-pad 1)
   :initial-element #\Space))

(defun render-user-message-lines
    (text width &key (output-pad 1))
  (let* ((padding
           (output-padding-string output-pad))
         (lines
           (cadr-tui:wrap-text
            (concatenate 'string padding text)
            width)))
    (append
     (list
      (concatenate
       'string +osc-133-start+
       (format nil "~C[49m" #\Escape)))
     lines
     (list
      (concatenate
       'string +osc-133-end+
       +osc-133-final+
       (format nil "~C[49m" #\Escape))))))

(defun render-assistant-message-lines
    (blocks width
     &key (output-pad 1)
       thinking-visible-p stop-reason)
  (let ((contains-tool-p nil)
        (thinking-run-p nil)
        (lines nil)
        (padding
          (output-padding-string output-pad)))
    (dolist (block blocks)
      (case (getf block :type)
        (:tool-call
         (setf contains-tool-p t
               thinking-run-p nil))
        (:thinking
         (unless thinking-run-p
           (setf
            lines
            (nconc
             lines
             (cadr-tui:wrap-text
              (concatenate
               'string padding
               (if thinking-visible-p
                   (or (getf block :thinking)
                       "")
                   "Thinking..."))
              width))))
         (setf thinking-run-p t))
        (:text
         (setf thinking-run-p nil)
         (setf
          lines
          (nconc
           lines
           (cadr-tui:wrap-text
            (concatenate
             'string padding
             (or (getf block :text) ""))
            width))))))
    (when (eq stop-reason :length)
      (setf
       lines
       (nconc
        lines
        (cadr-tui:wrap-text
         "Error: maximum output token limit reached; response may be incomplete."
         width))))
    (if contains-tool-p
        lines
        (if lines
            (let ((copy (copy-list lines)))
              (setf
               (first copy)
               (concatenate
                'string +osc-133-start+
                (first copy))
               (car (last copy))
               (concatenate
                'string +osc-133-end+
                +osc-133-final+
                (car (last copy))))
              copy)
            nil))))

(defstruct (status-log
            (:constructor make-status-log ()))
  (entries nil :type list)
  last-status-index)

(defun status-log-add-content (log text)
  (setf
   (status-log-entries log)
   (append
    (status-log-entries log)
    (list (cons :content text)))
   (status-log-last-status-index log)
   nil)
  log)

(defun status-log-show (log text)
  (let ((index
          (status-log-last-status-index log)))
    (if (and index
             (= index
                (1- (length
                     (status-log-entries log)))))
        (setf
         (nth index (status-log-entries log))
         (cons :status text))
        (progn
          (setf
           (status-log-entries log)
           (append
            (status-log-entries log)
            (list (cons :status text))))
          (setf
           (status-log-last-status-index log)
           (1-
            (length
             (status-log-entries log)))))))
  log)

(defstruct (startup-input-queue
            (:constructor make-startup-input-queue
                ()))
  (items nil :type list)
  (lock
    (sb-thread:make-mutex
     :name "cadr startup input")))

(defun queue-startup-input (queue text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           text)))
    (when (plusp (length trimmed))
      (sb-thread:with-mutex
          ((startup-input-queue-lock queue))
        (setf
         (startup-input-queue-items queue)
         (append
          (startup-input-queue-items queue)
          (list trimmed))))))
  queue)

(defun pop-startup-input (queue)
  (sb-thread:with-mutex
      ((startup-input-queue-lock queue))
    (when
        (startup-input-queue-items queue)
      (pop
       (startup-input-queue-items queue)))))

(defparameter +anthropic-subscription-auth-warning+
  "Anthropic subscription auth is active. Third-party harness usage draws from extra usage and is billed per token, not your Claude plan limits. Manage extra usage at https://claude.ai/settings/usage. Disable this warning in /settings.")

(defstruct anthropic-warning-state
  (shown-p nil :type boolean))

(defun anthropic-provider-p (provider)
  (string=
   "anthropic"
   (string-downcase
    (typecase provider
      (symbol (symbol-name provider))
      (string provider)
      (otherwise "")))))

(defun anthropic-warning-enabled-p
    (settings)
  (let ((warnings
          (and
           (hash-table-p settings)
           (cadr-ai::json-get
            settings "warnings"))))
    (not
     (and
      (hash-table-p warnings)
      (null
       (cadr-ai::json-get
        warnings
        "anthropicExtraUsage"
        t))))))

(defun anthropic-subscription-credential-p
    (credential)
  (or
   (eq credential :oauth)
   (typep credential
          'cadr-ai:oauth-credential)
   (let ((key
           (cond
             ((stringp credential)
              credential)
             ((typep
               credential
               'cadr-ai:api-key-credential)
              (cadr-ai:api-key-credential-key
               credential))
             (t nil))))
     (and
      key
      (uiop:string-prefix-p
       "sk-ant-oat" key)))))

(defun maybe-anthropic-subscription-warning
    (state provider settings
     credential-function)
  (when
      (or
       (anthropic-warning-state-shown-p
        state)
       (not
        (anthropic-warning-enabled-p
         settings))
       (not
        (anthropic-provider-p provider)))
    (return-from
        maybe-anthropic-subscription-warning
      nil))
  (handler-case
      (when
          (anthropic-subscription-credential-p
           (funcall credential-function))
        (setf
         (anthropic-warning-state-shown-p
          state)
         t)
        +anthropic-subscription-auth-warning+)
    (condition () nil)))

(defstruct session-search-record
  id
  path
  parent-path
  name
  cwd
  first-message
  (message-count 0 :type (integer 0 *))
  (modified 0 :type real)
  (all-messages-text "" :type string)
  payload)

(defun normalized-search-text (text)
  (string-downcase
   (cl-ppcre:regex-replace-all
    "\\s+" (or text "") " ")))

(defun quoted-search-p (query)
  (and (>= (length query) 2)
       (char= (char query 0) #\")
       (char= (char query
                    (1- (length query)))
              #\")))

(defun search-record-haystack (record)
  (normalized-search-text
   (format nil "~@[~A ~]~A"
           (session-search-record-name record)
           (session-search-record-all-messages-text
            record))))

(defun search-record-position (record query)
  (let ((haystack
          (search-record-haystack record)))
    (cond
      ((uiop:string-prefix-p "re:" query)
       (handler-case
           (multiple-value-bind (start end)
               (cl-ppcre:scan
                (cl-ppcre:create-scanner
                 (subseq query 3)
                 :case-insensitive-mode t)
                haystack)
             (declare (ignore end))
             start)
         (condition () nil)))
      (t
       (let ((needle
               (normalized-search-text
                (if (quoted-search-p query)
                    (subseq query 1
                            (1- (length query)))
                    query))))
         (if (zerop (length needle))
             0
             (search needle haystack)))))))

(defun named-session-p (record)
  (let ((name
          (session-search-record-name record)))
    (and name
         (plusp
          (length
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            name))))))

(defun filter-and-sort-sessions
    (sessions query
     &key (sort-mode :recent)
       (name-filter :all))
  (let ((matches nil)
        (regex-p
          (uiop:string-prefix-p
           "re:" query)))
    (when regex-p
      (handler-case
          (cl-ppcre:create-scanner
           (subseq query 3)
           :case-insensitive-mode t)
        (condition ()
          (return-from
              filter-and-sort-sessions nil))))
    (dolist (session sessions)
      (when (and
             (or
              (eq name-filter :all)
              (and
               (eq name-filter :named)
               (named-session-p session)))
             (let ((position
                     (search-record-position
                      session query)))
               (when position
                 (push
                  (cons session position)
                  matches)
                 t)))))
    (setf matches (nreverse matches))
    (when (eq sort-mode :relevance)
      (setf
       matches
       (stable-sort
        matches
        (lambda (left right)
          (if (= (cdr left) (cdr right))
              (>
               (session-search-record-modified
                (car left))
               (session-search-record-modified
                (car right)))
              (< (cdr left) (cdr right)))))))
    (mapcar #'car matches)))

(defun canonical-file-name (path)
  (namestring
   (or (ignore-errors (truename path))
       (uiop:ensure-absolute-pathname path))))

(defun thread-session-records (sessions)
  (let ((by-path
          (make-hash-table :test #'equal))
        (children
          (make-hash-table :test #'equal))
        (roots nil))
    (dolist (session sessions)
      (setf
       (gethash
        (canonical-file-name
         (session-search-record-path session))
        by-path)
       session))
    (dolist (session sessions)
      (let* ((parent-path
               (session-search-record-parent-path
                session))
             (parent
               (and parent-path
                    (gethash
                     (canonical-file-name
                      parent-path)
                     by-path))))
        (if parent
            (push session
                  (gethash
                   (canonical-file-name
                    (session-search-record-path
                     parent))
                   children))
            (push session roots))))
    (labels
        ((latest (session)
           (max
            (session-search-record-modified
             session)
            (loop for child in
                  (gethash
                   (canonical-file-name
                    (session-search-record-path
                     session))
                   children)
                  maximize (latest child)
                    into value
                  finally
                  (return (or value 0)))))
         (emit (session depth)
           (cons
            (cons depth session)
            (mapcan
             (lambda (child)
               (emit child (1+ depth)))
             (sort
              (copy-list
               (gethash
                (canonical-file-name
                 (session-search-record-path
                  session))
                children))
              #'>
              :key #'latest)))))
      (mapcan
       (lambda (root)
         (emit root 0))
       (sort roots #'> :key #'latest)))))

(define-condition active-session-deletion-error
    (error)
  ((path :initarg :path
         :reader active-session-deletion-path))
  (:report
   (lambda (condition stream)
     (format stream
             "Cannot delete the currently active session: ~A"
             (active-session-deletion-path
              condition)))))

(defun delete-session-file
    (path &key active-path trash-runner)
  (let ((target
          (uiop:ensure-absolute-pathname
           (pathname path))))
    (when
        (and
         active-path
         (string=
          (canonical-file-name target)
          (canonical-file-name active-path)))
      (error
       'active-session-deletion-error
       :path (namestring target)))
    (unless (probe-file target)
      (return-from delete-session-file
        (values t :missing nil)))
    (when trash-runner
      (handler-case
          (when
              (zerop
               (funcall
                trash-runner
                (if
                    (uiop:string-prefix-p
                     "-" (file-namestring target))
                    (list "trash" "--"
                          (namestring target))
                    (list "trash"
                          (namestring target)))))
            (return-from delete-session-file
              (values t :trash nil)))
        (condition () nil)))
    (handler-case
        (progn
          (delete-file target)
          (values t :unlink nil))
      (condition (condition)
        (values nil :unlink
                (princ-to-string condition))))))

(defun rename-session-at-path (path name)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           name)))
    (when (zerop (length trimmed))
      (error
       'cadr-ai:configuration-error
       :message "Session name must not be empty"))
    (let ((session
            (cadr-agent:load-session path)))
      (cadr-agent:session-set-name
       session trimmed)
      trimmed)))

(defun selector-modified-cursor-key (data)
  (multiple-value-bind
        (matched registers)
      (cl-ppcre:scan-to-strings
       (format nil "^~C\\[1;(\\d+)([ABCD])$"
               #\Escape)
       data)
    (when matched
      (let* ((mask
               (1-
                (parse-integer
                 (aref registers 0))))
             (direction
               (cdr
                (assoc
                 (char (aref registers 1) 0)
                 '((#\A . "up")
                   (#\B . "down")
                   (#\C . "right")
                   (#\D . "left"))))))
        (when direction
          (format
           nil "~{~A~^+~}"
           (append
            (when (logtest 1 mask)
              '("shift"))
            (when (logtest 4 mask)
              '("ctrl"))
            (when (logtest 2 mask)
              '("alt"))
            (when (logtest 8 mask)
              '("super"))
            (list direction))))))))

(defun selector-keybinding-matches-p
    (manager data name)
  (or
   (cadr-tui:keybinding-matches-p
    manager data name)
   (let ((parsed
           (selector-modified-cursor-key data)))
     (and parsed
          (member
           (cadr-tui::canonical-key-id parsed)
           (cadr-tui:keybinding-keys
            manager name)
           :key #'cadr-tui::canonical-key-id
           :test #'string=)))))

(defparameter +session-selector-keybinding-definitions+
  '(("app.session.toggleNamedFilter" . ("ctrl+n"))
    ("app.session.togglePath" . ("ctrl+p"))
    ("app.session.toggleSort" . ("ctrl+s"))
    ("app.session.rename" . ("ctrl+r"))
    ("app.session.delete" . ("ctrl+d"))
    ("app.session.deleteNoninvasive"
     . ("ctrl+backspace"))))

(defun make-session-selector-keybindings
    (&optional user-bindings)
  (cadr-tui:make-keybindings-manager
   :definitions
   +session-selector-keybinding-definitions+
   :user-bindings user-bindings))

(defstruct (session-selector-state
            (:constructor %make-session-selector-state))
  (current-sessions nil :type list)
  (all-sessions nil :type list)
  (all-loaded-p nil :type boolean)
  (all-loading-p nil :type boolean)
  (all-load-sequence 0 :type (integer 0 *))
  (scope :current)
  (sort-mode :threaded)
  (name-filter :all)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  (show-path-p nil :type boolean)
  (show-rename-hint-p nil :type boolean)
  (mode :list)
  (rename-input "" :type string)
  (rename-cursor 0 :type (integer 0 *))
  rename-target-path
  confirming-delete-path
  current-session-path
  status-message
  rename-function
  delete-function
  keybindings)

(defun make-session-selector-state
    (&key current-sessions all-sessions
          all-loaded-p current-session-path
          show-rename-hint-p rename-function
          delete-function keybindings)
  (%make-session-selector-state
   :current-sessions (copy-list current-sessions)
   :all-sessions (copy-list all-sessions)
   :all-loaded-p
   (or all-loaded-p
       (not (null all-sessions)))
   :current-session-path current-session-path
   :show-rename-hint-p
   (not (null show-rename-hint-p))
   :rename-function rename-function
   :delete-function delete-function
   :keybindings
   (or keybindings
       (make-session-selector-keybindings))))

(defun session-message-search-text (message)
  (typecase message
    (cadr-ai:user-message
     (cadr-ai::content-text
      (cadr-ai:user-message-content message)))
    (cadr-ai:assistant-message
     (cadr-ai::content-text
      (cadr-ai:assistant-message-content message)))
    (cadr-ai:tool-result-message
     (cadr-ai::content-text
      (cadr-ai:tool-result-message-content message)))
    (t "")))

(defun session-to-search-record (session)
  (let* ((messages
           (cadr-agent:session-messages session))
         (texts
           (mapcar #'session-message-search-text
                   messages)))
    (make-session-search-record
     :id (cadr-agent:session-id session)
     :path (cadr-agent:session-path session)
     :parent-path
     (cadr-agent:session-parent-session session)
     :name (cadr-agent:session-name session)
     :cwd (cadr-agent:session-cwd session)
     :first-message
     (find-if
      (lambda (text)
        (plusp
         (length
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           text))))
      texts)
     :message-count (length messages)
     :modified
     (or (cadr-agent::session-modified-timestamp
          session)
         (cadr-agent:session-timestamp session)
         0)
     :all-messages-text
     (format nil "~{~A~^~%~}" texts)
     :payload session)))

(defun session-select-items-to-records (items)
  (loop
    for item in items
    for value = (cadr-tui:select-item-value item)
    collect
    (if (typep value 'cadr-agent:session)
        (session-to-search-record value)
        (make-session-search-record
         :id
         (princ-to-string value)
         :path
         (princ-to-string value)
         :modified 0
         :first-message
         (cadr-tui:select-item-label item)
         :all-messages-text
         (cadr-tui:select-item-label item)
         :payload value))))

(defun session-selector-source-sessions (selector)
  (if (eq :all
          (session-selector-state-scope selector))
      (session-selector-state-all-sessions selector)
      (session-selector-state-current-sessions selector)))

(defun session-selector-visible-nodes (selector)
  (let* ((sessions
           (session-selector-source-sessions selector))
         (query
           (session-selector-state-query selector))
         (sort-mode
           (session-selector-state-sort-mode selector))
         (name-filter
           (session-selector-state-name-filter selector)))
    (if (and (eq sort-mode :threaded)
             (zerop
              (length
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                query))))
        (thread-session-records
         (if (eq name-filter :named)
             (remove-if-not #'named-session-p sessions)
             sessions))
        (mapcar
         (lambda (record)
           (cons 0 record))
         (filter-and-sort-sessions
          sessions query
          :sort-mode
          (if (eq sort-mode :relevance)
              :relevance
              :recent)
          :name-filter name-filter)))))

(defun session-selector-clamp-selected (selector)
  (let ((count
          (length
           (session-selector-visible-nodes selector))))
    (setf
     (session-selector-state-selected selector)
     (if (zerop count)
         0
         (min
          (session-selector-state-selected selector)
          (1- count)))))
  selector)

(defun session-selector-move (selector delta)
  (let ((count
          (length
           (session-selector-visible-nodes selector))))
    (when (plusp count)
      (setf
       (session-selector-state-selected selector)
       (mod
        (+ (session-selector-state-selected selector)
           delta)
        count))))
  selector)

(defun session-selector-selected-record (selector)
  (cdr
   (nth
    (session-selector-state-selected selector)
    (session-selector-visible-nodes selector))))

(defun same-session-path-p (left right)
  (and left right
       (string=
        (canonical-file-name left)
        (canonical-file-name right))))

(defun session-selector-start-delete (selector)
  (let ((record
          (session-selector-selected-record selector)))
    (when record
      (let ((path
              (session-search-record-path record)))
        (if
            (same-session-path-p
             path
             (session-selector-state-current-session-path
              selector))
            (let ((message
                    "Cannot delete the currently active session"))
              (setf
               (session-selector-state-status-message selector)
               message)
              (values :error message))
            (progn
              (setf
               (session-selector-state-confirming-delete-path
                selector)
               path
               (session-selector-state-status-message selector)
               nil)
              (values :changed path)))))))

(defun remove-session-record-by-path (records path)
  (remove-if
   (lambda (record)
     (same-session-path-p
      (session-search-record-path record)
      path))
   records))

(defun session-selector-delete-confirmed (selector)
  (let ((path
          (session-selector-state-confirming-delete-path
           selector)))
    (setf
     (session-selector-state-confirming-delete-path
      selector)
     nil)
    (unless path
      (return-from session-selector-delete-confirmed
        (values nil nil)))
    (handler-case
        (multiple-value-bind (ok method error)
            (if
                (session-selector-state-delete-function
                 selector)
                (funcall
                 (session-selector-state-delete-function
                  selector)
                 path)
                (delete-session-file path))
          (declare (ignore method))
          (if ok
              (progn
                (setf
                 (session-selector-state-current-sessions
                  selector)
                 (remove-session-record-by-path
                  (session-selector-state-current-sessions
                   selector)
                  path)
                 (session-selector-state-all-sessions
                  selector)
                 (remove-session-record-by-path
                  (session-selector-state-all-sessions
                   selector)
                  path)
                 (session-selector-state-status-message
                  selector)
                 "Session deleted")
                (session-selector-clamp-selected selector)
                (values :deleted path))
              (let ((message
                      (format nil "Failed to delete: ~A"
                              (or error "Unknown error"))))
                (setf
                 (session-selector-state-status-message
                  selector)
                 message)
                (values :error message))))
      (condition (condition)
        (let ((message
                (format nil "Failed to delete: ~A"
                        condition)))
          (setf
           (session-selector-state-status-message selector)
           message)
          (values :error message))))))

(defun session-selector-enter-rename (selector)
  (let ((record
          (session-selector-selected-record selector)))
    (when (and record
               (session-selector-state-rename-function
                selector))
      (let ((name
              (or
               (session-search-record-name record)
               "")))
        (setf
         (session-selector-state-mode selector)
         :rename
         (session-selector-state-rename-target-path
          selector)
         (session-search-record-path record)
         (session-selector-state-rename-input selector)
         name
         (session-selector-state-rename-cursor selector)
         0
         (session-selector-state-status-message selector)
         nil)
        (values :changed
                (session-search-record-path record))))))

(defun update-record-name-by-path (records path name)
  (dolist (record records)
    (when
        (same-session-path-p
         (session-search-record-path record)
         path)
      (setf
       (session-search-record-name record)
       name)
      (let ((payload
              (session-search-record-payload record)))
        (when (typep payload 'cadr-agent:session)
          (setf
           (cadr-agent:session-name payload)
           name)))))
  records)

(defun session-selector-confirm-rename (selector)
  (let* ((name
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            (session-selector-state-rename-input
             selector)))
         (path
           (session-selector-state-rename-target-path
            selector)))
    (when (zerop (length name))
      (return-from session-selector-confirm-rename
        (values nil nil)))
    (unwind-protect
         (handler-case
             (progn
               (funcall
                (session-selector-state-rename-function
                 selector)
                path name)
               (update-record-name-by-path
                (session-selector-state-current-sessions
                 selector)
                path name)
               (update-record-name-by-path
                (session-selector-state-all-sessions
                 selector)
                path name)
               (setf
                (session-selector-state-status-message
                 selector)
                "Session renamed")
               (values :renamed name))
           (condition (condition)
             (let ((message
                     (format nil "Failed to rename: ~A"
                             condition)))
               (setf
                (session-selector-state-status-message
                 selector)
                message)
               (values :error message))))
      (setf
       (session-selector-state-mode selector)
       :list
       (session-selector-state-rename-target-path
        selector)
       nil))))

(defun session-selector-toggle-scope (selector)
  (let ((started-token nil))
    (if (eq :current
            (session-selector-state-scope selector))
        (progn
          (setf
           (session-selector-state-scope selector)
           :all)
          (unless
              (or
               (session-selector-state-all-loaded-p selector)
               (session-selector-state-all-loading-p selector))
            (setf
             (session-selector-state-all-loading-p selector)
             t
             started-token
             (incf
              (session-selector-state-all-load-sequence
               selector)))))
        (setf
         (session-selector-state-scope selector)
         :current))
    (session-selector-clamp-selected selector)
    started-token))

(defun session-selector-complete-all-load
    (selector token sessions)
  (when
      (= token
         (session-selector-state-all-load-sequence
          selector))
    (setf
     (session-selector-state-all-sessions selector)
     (copy-list sessions)
     (session-selector-state-all-loaded-p selector)
     t
     (session-selector-state-all-loading-p selector)
     nil)
    (session-selector-clamp-selected selector))
  selector)

(defun session-selector-fail-all-load
    (selector token condition)
  (when
      (= token
         (session-selector-state-all-load-sequence
          selector))
    (setf
     (session-selector-state-all-loading-p selector)
     nil
     (session-selector-state-status-message selector)
     (format nil "Failed to load sessions: ~A"
             condition)))
  selector)

(defun delete-last-query-word (query)
  (let* ((trimmed-end
           (string-right-trim
            '(#\Space #\Tab)
            query))
         (separator
           (position-if
            (lambda (character)
              (member character '(#\Space #\Tab)))
            trimmed-end
            :from-end t)))
    (if separator
        (subseq trimmed-end 0 (1+ separator))
        "")))

(defun session-selector-app-key-p
    (selector data name)
  (cadr-tui:keybinding-matches-p
   (session-selector-state-keybindings selector)
   data name))

(defun session-selector-handle-raw-input
    (selector data)
  (when
      (or
       (eq :rename
           (session-selector-state-mode selector))
       (session-selector-state-confirming-delete-path
        selector))
    (return-from session-selector-handle-raw-input
      (values nil nil nil)))
  (cond
    ((session-selector-app-key-p
      selector data "app.session.delete")
     (multiple-value-bind (action value)
         (session-selector-start-delete selector)
       (values action value t)))
    ((session-selector-app-key-p
      selector data
      "app.session.deleteNoninvasive")
     (if (plusp
          (length
           (session-selector-state-query selector)))
         (progn
           (setf
            (session-selector-state-query selector)
            (delete-last-query-word
             (session-selector-state-query selector)))
           (session-selector-clamp-selected selector)
           (values :changed nil t))
         (multiple-value-bind (action value)
             (session-selector-start-delete selector)
           (values action value t))))
    ((session-selector-app-key-p
      selector data "app.session.rename")
     (multiple-value-bind (action value)
         (session-selector-enter-rename selector)
       (values action value t)))
    ((session-selector-app-key-p
      selector data "app.session.toggleSort")
     (setf
      (session-selector-state-sort-mode selector)
      (case
          (session-selector-state-sort-mode selector)
        (:threaded :recent)
        (:recent :relevance)
        (otherwise :threaded)))
     (session-selector-clamp-selected selector)
     (values :changed nil t))
    ((session-selector-app-key-p
      selector data "app.session.toggleNamedFilter")
     (setf
      (session-selector-state-name-filter selector)
      (if
          (eq :all
              (session-selector-state-name-filter
               selector))
          :named :all))
     (session-selector-clamp-selected selector)
     (values :changed nil t))
    ((session-selector-app-key-p
      selector data "app.session.togglePath")
     (setf
      (session-selector-state-show-path-p selector)
      (not
       (session-selector-state-show-path-p
        selector)))
     (values :changed nil t))
    (t
     (values nil nil nil))))

(defun insert-at-index (text addition index)
  (concatenate
   'string
   (subseq text 0 index)
   addition
   (subseq text index)))

(defun session-selector-handle-rename-event
    (selector event)
  (case (cadr-tui:input-event-kind event)
    (:escape
     (setf
      (session-selector-state-mode selector)
      :list
      (session-selector-state-rename-target-path selector)
      nil)
     (values :changed nil))
    (:enter
     (session-selector-confirm-rename selector))
    (:text
     (let ((text
             (or
              (cadr-tui:input-event-text event)
              "")))
       (setf
        (session-selector-state-rename-input selector)
        (insert-at-index
         (session-selector-state-rename-input selector)
         text
         (session-selector-state-rename-cursor
          selector)))
       (incf
        (session-selector-state-rename-cursor selector)
        (length text)))
     (values :changed nil))
    (:backspace
     (let ((cursor
             (session-selector-state-rename-cursor
              selector)))
       (when (plusp cursor)
         (let* ((text
                  (session-selector-state-rename-input
                   selector))
                (start
                  (cadr-tui::previous-cluster-boundary
                   text cursor)))
           (setf
            (session-selector-state-rename-input selector)
            (concatenate
             'string
             (subseq text 0 start)
             (subseq text cursor))
            (session-selector-state-rename-cursor selector)
            start))))
     (values :changed nil))
    (:left
     (setf
      (session-selector-state-rename-cursor selector)
      (max
       0
       (1-
        (session-selector-state-rename-cursor
         selector))))
     (values :changed nil))
    (:right
     (setf
      (session-selector-state-rename-cursor selector)
      (min
       (length
        (session-selector-state-rename-input selector))
       (1+
        (session-selector-state-rename-cursor
         selector))))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun session-selector-handle-event (selector event)
  (when
      (eq :rename
          (session-selector-state-mode selector))
    (return-from session-selector-handle-event
      (session-selector-handle-rename-event
       selector event)))
  (when
      (session-selector-state-confirming-delete-path
       selector)
    (return-from session-selector-handle-event
      (case (cadr-tui:input-event-kind event)
        (:enter
         (session-selector-delete-confirmed selector))
        (:escape
         (setf
          (session-selector-state-confirming-delete-path
           selector)
          nil)
         (values :changed nil))
        (otherwise
         (values nil nil)))))
  (case (cadr-tui:input-event-kind event)
    (:tab
     (let ((token
             (session-selector-toggle-scope selector)))
       (if token
           (values :load-all token)
           (values :changed nil))))
    (:up
     (session-selector-move selector -1)
     (values :changed nil))
    (:down
     (session-selector-move selector 1)
     (values :changed nil))
    (:page-up
     (setf
      (session-selector-state-selected selector)
      (max
       0
       (-
        (session-selector-state-selected selector)
        10)))
     (values :changed nil))
    (:page-down
     (setf
      (session-selector-state-selected selector)
      (min
       (max
        0
        (1-
         (length
          (session-selector-visible-nodes selector))))
       (+
        (session-selector-state-selected selector)
        10)))
     (values :changed nil))
    (:enter
     (let ((record
             (session-selector-selected-record selector)))
       (if record
           (values
            :select
            (session-search-record-payload record))
           (values nil nil))))
    (:escape
     (values :cancel nil))
    (:backspace
     (let ((query
             (session-selector-state-query selector)))
       (when (plusp (length query))
         (setf
          (session-selector-state-query selector)
          (subseq
           query 0
           (cadr-tui::previous-cluster-boundary
            query (length query))))))
     (session-selector-clamp-selected selector)
     (values :changed nil))
    (:text
     (setf
      (session-selector-state-query selector)
      (concatenate
       'string
       (session-selector-state-query selector)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (setf
      (session-selector-state-selected selector)
      0)
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun session-selector-binding-label
    (selector name)
  (or
   (first
    (cadr-tui:keybinding-keys
     (session-selector-state-keybindings selector)
     name))
   name))

(defun sanitize-session-selector-label (text)
  (with-output-to-string (output)
    (loop for character across (or text "")
          for code = (char-code character)
          do
          (write-char
           (if (or (<= code 31)
                   (= code 127))
               #\Space
               character)
           output))))

(defun session-selector-record-label (record)
  (sanitize-session-selector-label
   (or
    (and
     (named-session-p record)
     (session-search-record-name record))
    (let ((text
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             (or
              (session-search-record-first-message
               record)
              (session-search-record-all-messages-text
               record)))))
      (if (plusp (length text))
          text
          (session-search-record-id record))))))

(defun session-selector-shorten-path (path)
  (let* ((value
           (etypecase path
             (pathname (namestring path))
             (string path)))
         (home
           (string-right-trim
            "/" (namestring
                 (user-homedir-pathname)))))
    (if
        (uiop:string-prefix-p home value)
        (concatenate 'string "~"
                     (subseq value (length home)))
        value)))

(defun session-selector-format-age
    (modified &optional
                (now (cadr-ai::unix-milliseconds)))
  (let ((seconds
          (max 0
               (floor
                (/ (- now modified) 1000)))))
    (cond
      ((< seconds 60) "now")
      ((< seconds 3600)
       (format nil "~Dm" (floor seconds 60)))
      ((< seconds 86400)
       (format nil "~Dh" (floor seconds 3600)))
      ((< seconds 604800)
       (format nil "~Dd" (floor seconds 86400)))
      ((< seconds 2592000)
       (format nil "~Dw" (floor seconds 604800)))
      ((< seconds 31536000)
       (format nil "~Dmo" (floor seconds 2592000)))
      (t
       (format nil "~Dy" (floor seconds 31536000))))))

(defun selector-align-left-right
    (left right width)
  (let* ((right
           (cadr-tui:truncate-to-width
            right (max 0 width) ""))
         (left-width
           (max 0
                (- width
                   (cadr-tui:visible-width right)
                   1)))
         (left
           (cadr-tui:truncate-to-width
            left left-width "")))
    (concatenate
     'string left
     (make-string
      (max 0
           (- width
              (cadr-tui:visible-width left)
              (cadr-tui:visible-width right)))
      :initial-element #\Space)
     right)))

(defun centered-visible-slice
    (items selected maximum)
  (let* ((count (length items))
         (start
           (max
            0
            (min
             (- selected (floor maximum 2))
             (- count maximum))))
         (end (min (+ start maximum) count)))
    (values (subseq items start end)
            start end count)))

(defun session-selector-node-prefix
    (nodes index)
  (let* ((depth (car (nth index nodes)))
         (count (length nodes)))
    (when (zerop depth)
      (return-from session-selector-node-prefix ""))
    (with-output-to-string (output)
      (loop for level from 1 below depth
            for continues-p =
              (loop for cursor from (1+ index)
                    below count
                    for later-depth =
                      (car (nth cursor nodes))
                    when (< later-depth level)
                      return nil
                    when (= later-depth level)
                      return t
                    finally (return nil))
            do
            (write-string
             (if continues-p "│  " "   ")
             output))
      (let ((last-p
              (loop for cursor from (1+ index)
                    below count
                    for later-depth =
                      (car (nth cursor nodes))
                    when (< later-depth depth)
                      return t
                    when (= later-depth depth)
                      return nil
                    finally (return t))))
        (write-string
         (if last-p "└─ " "├─ ")
         output)))))

(defun selector-fit-line (line width &key (pad-p nil))
  (let* ((available (max 0 width))
         (limited
           (cadr-tui:truncate-to-width
            line available ""))
         (padding
           (if pad-p
               (max
                0
                (- available
                   (cadr-tui:visible-width limited)))
               0)))
    (concatenate
     'string limited
     (make-string padding
                  :initial-element #\Space))))

(defun selector-border-line
    (width &optional (color :border-muted))
  (cadr-tui:theme-foreground
   color
   (make-string (max 0 width)
                :initial-element #\─)))

(defun selector-title-line (title width)
  (selector-fit-line
   (cadr-tui:theme-foreground
    :accent
    (cadr-tui:theme-bold title))
   width))

(defun selector-selected-line (line width)
  (cadr-tui:theme-background
   :selected-bg
   (selector-fit-line line width :pad-p t)))

(defun selector-muted-line (line width)
  (selector-fit-line
   (cadr-tui:theme-foreground :muted line)
   width))

(defun selector-dim-line (line width)
  (selector-fit-line
   (cadr-tui:theme-foreground :dim line)
   width))

(defun render-session-selector (selector width)
  (when
      (eq :rename
          (session-selector-state-mode selector))
    (return-from render-session-selector
      (list
       ""
       (selector-border-line width :accent)
       ""
       (selector-fit-line
        (cadr-tui:theme-bold "Rename Session") width)
       ""
       (selector-fit-line
        (cadr-tui:theme-foreground
         :accent
         (session-selector-state-rename-input
          selector))
        width)
       ""
       (selector-dim-line
        "enter to save · escape to cancel"
        width)
       ""
       (selector-border-line width :accent))))
  (let* ((scope
           (session-selector-state-scope selector))
         (sort
           (session-selector-state-sort-mode selector))
         (name-filter
           (session-selector-state-name-filter selector))
         (nodes
           (session-selector-visible-nodes selector))
         (selected
           (session-selector-state-selected selector))
         (title
           (if (eq scope :current)
               "Resume Session (Current Folder)"
               "Resume Session (All)"))
         (scope-text
           (cond
             ((session-selector-state-all-loading-p
               selector)
              (concatenate
               'string
               (cadr-tui:theme-foreground
                :muted "○ Current Folder | ")
               (cadr-tui:theme-foreground
                :accent "Loading ...")))
             ((eq scope :current)
              (concatenate
               'string
               (cadr-tui:theme-foreground
                :accent "◉ Current Folder")
               (cadr-tui:theme-foreground
                :muted " | ○ All")))
             (t
              (concatenate
               'string
               (cadr-tui:theme-foreground
                :muted "○ Current Folder | ")
               (cadr-tui:theme-foreground
                :accent "◉ All")))))
         (right
           (concatenate
            'string scope-text "  "
            (cadr-tui:theme-foreground
             :muted "Name: ")
            (cadr-tui:theme-foreground
             :accent
             (if (eq name-filter :all)
                 "All" "Named"))
            "  "
            (cadr-tui:theme-foreground
             :muted "Sort: ")
            (cadr-tui:theme-foreground
             :accent
             (string-capitalize
              (symbol-name sort)))))
         (hint-1 nil)
         (hint-2 nil))
    (cond
      ((session-selector-state-confirming-delete-path
        selector)
       (setf
        hint-1
        (cadr-tui:theme-foreground
         :error
         "Delete session? enter confirm · escape cancel")
        hint-2 ""))
      ((session-selector-state-status-message selector)
       (setf
        hint-1
        (cadr-tui:theme-foreground
         :accent
         (session-selector-state-status-message
          selector))
        hint-2 ""))
      (t
       (setf
        hint-1
        (format nil "tab scope · re:<pattern> regex · ~S exact"
                "phrase")
        hint-2
        (format
         nil "~{~A~^ · ~}"
         (append
          (list
           (format nil "~A sort"
                   (session-selector-binding-label
                    selector "app.session.toggleSort"))
           (format nil "~A named"
                   (session-selector-binding-label
                    selector
                    "app.session.toggleNamedFilter"))
           (format nil "~A delete"
                   (session-selector-binding-label
                    selector "app.session.delete"))
           (format nil "~A path (~A)"
                   (session-selector-binding-label
                    selector "app.session.togglePath")
                   (if
                       (session-selector-state-show-path-p
                        selector)
                       "on" "off")))
          (when
              (session-selector-state-show-rename-hint-p
               selector)
            (list
             (format nil "~A rename"
                     (session-selector-binding-label
                      selector
                      "app.session.rename")))))))))
    (multiple-value-bind
          (visible start end total)
        (centered-visible-slice nodes selected 10)
      (append
       (list
        ""
        (selector-border-line width :accent)
        ""
        (selector-fit-line
         (selector-align-left-right
          (cadr-tui:theme-bold title)
          right width)
         width)
        (selector-dim-line hint-1 width)
        (selector-dim-line hint-2 width)
        ""
        (selector-fit-line
         (concatenate
          'string
          (cadr-tui:theme-foreground :muted "> ")
          (cadr-tui:theme-foreground
           :accent
           (session-selector-state-query selector)))
         width)
        "")
       (if (null visible)
           (list
            (selector-muted-line
             (cond
               ((eq name-filter :named)
                (if (eq scope :current)
                    "  No named sessions in current folder. Press ctrl+n to show all, or Tab to view all."
                    "  No named sessions found. Press ctrl+n to show all."))
               ((eq scope :current)
                "  No sessions in current folder. Press Tab to view all.")
               (t "  No sessions found"))
             width))
           (loop
             for node in visible
             for index from start
             for record = (cdr node)
             for selected-p = (= index selected)
             for current-p =
               (same-session-path-p
                (session-search-record-path record)
                (session-selector-state-current-session-path
                 selector))
             for name-p = (named-session-p record)
             for prefix =
               (session-selector-node-prefix nodes index)
             for raw-label =
               (session-selector-record-label record)
             for right-part =
               (format
                nil "~@[~A ~]~@[~A ~]~D ~A"
                (and
                 (session-selector-state-show-path-p
                  selector)
                 (session-selector-shorten-path
                  (session-search-record-path record)))
                (and
                 (eq scope :all)
                 (session-search-record-cwd record)
                 (session-selector-shorten-path
                  (session-search-record-cwd record)))
                (session-search-record-message-count record)
                (session-selector-format-age
                 (session-search-record-modified record)))
             for cursor =
               (if selected-p
                   (cadr-tui:theme-foreground
                    :accent "› ")
                   "  ")
             for available =
               (max
                10
                (- width 2
                   (cadr-tui:visible-width prefix)
                   (cadr-tui:visible-width right-part)
                   2))
             for fitted-label =
               (cadr-tui:truncate-to-width
                raw-label available "…")
             for styled-label =
               (funcall
                (cond
                  (current-p
                   (lambda (text)
                     (cadr-tui:theme-foreground
                      :accent text)))
                  (name-p
                   (lambda (text)
                     (cadr-tui:theme-foreground
                      :warning text)))
                  (t #'identity))
                (if selected-p
                    (cadr-tui:theme-bold fitted-label)
                    fitted-label))
             for left =
               (concatenate
                'string cursor
                (cadr-tui:theme-foreground
                 :dim prefix)
                styled-label)
             for spacing =
               (max
                1
                (- width
                   (cadr-tui:visible-width left)
                   (cadr-tui:visible-width right-part)))
             for line =
               (concatenate
                'string left
                (make-string spacing
                             :initial-element #\Space)
                (cadr-tui:theme-foreground
                 :dim right-part))
             collect
               (if selected-p
                   (cadr-tui:theme-background
                    :selected-bg
                    (selector-fit-line line width))
                   (selector-fit-line line width))))
       (when (or (> start 0)
                 (< end total))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)"
                   (1+ selected) total)
           width)))
       (list ""
             (selector-border-line width :accent))))))

(defstruct (user-message-selector-state
            (:constructor
                %make-user-message-selector-state))
  (items nil :type list)
  (selected 0 :type (integer 0 *))
  (max-visible 10 :type (integer 1 *))
  keybindings)

(defun make-user-message-selector-state
    (&key items initial-selected-value
       (max-visible 10) keybindings)
  (let ((initial
          (and initial-selected-value
               (position
                initial-selected-value items
                :key #'cadr-tui:select-item-value
                :test #'equal))))
    (%make-user-message-selector-state
     :items (copy-list items)
     :selected
     (or initial
         (max 0 (1- (length items))))
     :max-visible (max 1 max-visible)
     :keybindings
     (or keybindings
         (cadr-tui:make-keybindings-manager)))))

(defun user-message-selector-move (state delta)
  (let ((count
          (length
           (user-message-selector-state-items state))))
    (when (plusp count)
      (setf
       (user-message-selector-state-selected state)
       (mod
        (+
         (user-message-selector-state-selected state)
         delta)
        count))))
  state)

(defun user-message-selector-selection (state)
  (let ((item
          (nth
           (user-message-selector-state-selected state)
           (user-message-selector-state-items state))))
    (and item
         (cadr-tui:select-item-value item))))

(defun user-message-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:up
     (user-message-selector-move state -1)
     (values :changed nil))
    (:down
     (user-message-selector-move state 1)
     (values :changed nil))
    ((:enter :submit)
     (let ((value
             (user-message-selector-selection state)))
       (if value
           (values :select value)
           (values nil nil))))
    ((:escape :cancel :interrupt)
     (values :cancel nil))
    (otherwise
     (values nil nil))))

(defun user-message-selector-handle-raw-input
    (state data)
  (let ((keybindings
          (user-message-selector-state-keybindings state)))
    (cond
      ((selector-keybinding-matches-p
        keybindings data "tui.select.up")
       (user-message-selector-move state -1)
       (values :changed nil t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.down")
       (user-message-selector-move state 1)
       (values :changed nil t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.confirm")
       (let ((value
               (user-message-selector-selection state)))
         (values (and value :select) value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.cancel")
       (values :cancel nil t))
      (t
       (values nil nil nil)))))

(defun render-user-message-selector
    (state width)
  (let* ((items
           (user-message-selector-state-items state))
         (selected
           (user-message-selector-state-selected state)))
    (multiple-value-bind
          (visible start end total)
        (centered-visible-slice
         items selected
         (user-message-selector-state-max-visible state))
      (append
       (list
        ""
        (selector-fit-line
         (cadr-tui:theme-bold "Fork from Message")
         width))
       (mapcar
        (lambda (line)
          (selector-muted-line line width))
        (cadr-tui:wrap-text
         "Select a user message to copy the active path up to that point into a new session"
         width))
       (list ""
             (selector-border-line width)
             "")
       (if visible
           (mapcan
            (lambda (item index)
              (let* ((selected-p (= index selected))
                     (text
                       (string-trim
                        '(#\Space #\Tab #\Newline #\Return)
                        (cl-ppcre:regex-replace-all
                         "\\n"
                         (cadr-tui:select-item-label item)
                         " ")))
                     (message
                       (cadr-tui:truncate-to-width
                        text (max 0 (- width 2)) "")))
                (list
                 (selector-fit-line
                  (concatenate
                   'string
                   (if selected-p
                       (cadr-tui:theme-foreground
                        :accent "› ")
                       "  ")
                   (if selected-p
                       (cadr-tui:theme-bold message)
                       message))
                  width)
                 (selector-muted-line
                  (format nil "  Message ~D of ~D"
                          (1+ index) total)
                  width)
                 "")))
            visible
            (loop for index from start below end
                  collect index))
           (list
            (selector-muted-line
             "  No user messages found" width)))
       (when (or (> start 0)
                 (< end total))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)"
                   (1+ selected) total)
           width)))
       (list ""
             (selector-border-line width))))))

(defun format-cwd-for-footer (cwd home)
  (let* ((normalized-home
           (string-right-trim "/" home))
         (normalized-cwd
           (string-right-trim "/" cwd)))
    (cond
      ((string= normalized-cwd
                normalized-home)
       "~")
      ((and
        (uiop:string-prefix-p
         normalized-home normalized-cwd)
        (> (length normalized-cwd)
           (length normalized-home))
        (char=
         (char normalized-cwd
               (length normalized-home))
         #\/))
       (concatenate
        'string "~"
        (subseq normalized-cwd
                (length normalized-home))))
      (t cwd))))

(defun fit-footer-text (text width)
  (cadr-tui:truncate-to-width text width))

(defun usage-value (usage key)
  (or (getf usage key) 0))

(defun footer-usage-summary
    (usages &key provider)
  (let ((input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0)
        (cost 0d0))
    (dolist (usage usages)
      (incf input (usage-value usage :input))
      (incf output (usage-value usage :output))
      (incf cache-read
            (usage-value usage :cache-read))
      (incf cache-write
            (usage-value usage :cache-write))
      (incf cost
            (coerce
             (usage-value usage :cost)
             'double-float)))
    (let* ((cache-total
             (+ input cache-read cache-write))
           (hit-rate
             (and (plusp (+ cache-read cache-write))
                  (* 100d0
                     (/ cache-read
                        (max 1 cache-total))))))
      (format
       nil
       "in:~D out:~D~@[ CH~,1F%~] $~,3F~:[~; (sub)~]"
       input output hit-rate cost
       (string-equal
        (or provider "")
        "kimi-coding")))))

(defstruct git-footer-paths
  repo-directory
  common-git-directory
  head-path)

(defun parent-directory-pathname (directory)
  (let* ((normalized
           (uiop:ensure-directory-pathname
            directory))
         (parts
           (pathname-directory normalized)))
    (when (> (length parts) 1)
      (make-pathname
       :directory (butlast parts)
       :defaults normalized))))

(defun find-git-footer-paths (cwd)
  (loop
    with directory =
    (uiop:ensure-directory-pathname
     (uiop:ensure-absolute-pathname cwd))
    for git-path =
    (merge-pathnames ".git" directory)
    do
    (when (probe-file git-path)
      (handler-case
          (if (uiop:directory-pathname-p
               (truename git-path))
              (let* ((git-directory
                       (uiop:ensure-directory-pathname
                        (truename git-path)))
                     (head
                       (merge-pathnames
                        "HEAD" git-directory)))
                (when (probe-file head)
                  (return
                    (make-git-footer-paths
                     :repo-directory directory
                     :common-git-directory
                     git-directory
                     :head-path head))))
              (let* ((content
                       (string-trim
                        '(#\Space #\Tab
                          #\Newline #\Return)
                        (uiop:read-file-string
                         git-path
                         :external-format
                         :utf-8)))
                     (prefix "gitdir: "))
                (when
                    (uiop:string-prefix-p
                     prefix content)
                  (let* ((git-directory
                           (uiop:ensure-directory-pathname
                            (uiop:ensure-absolute-pathname
                             (subseq
                              content
                              (length prefix))
                             directory)))
                         (head
                           (merge-pathnames
                            "HEAD"
                            git-directory))
                         (common-file
                           (merge-pathnames
                            "commondir"
                            git-directory))
                         (common-directory
                           (if
                               (probe-file
                                common-file)
                               (uiop:ensure-directory-pathname
                                (uiop:ensure-absolute-pathname
                                 (string-trim
                                  '(#\Space #\Tab
                                    #\Newline #\Return)
                                  (uiop:read-file-string
                                   common-file
                                   :external-format
                                   :utf-8))
                                 git-directory))
                               git-directory)))
                    (when (probe-file head)
                      (return
                        (make-git-footer-paths
                         :repo-directory directory
                         :common-git-directory
                         common-directory
                         :head-path head)))))))
        (condition ()
          (return nil))))
    (let ((parent
            (parent-directory-pathname
             directory)))
      (unless parent
        (return nil))
      (setf directory parent))))

(defun run-git-symbolic-branch (repo-directory)
  (handler-case
      (let ((output
              (uiop:run-program
               '("git"
                 "--no-optional-locks"
                 "symbolic-ref"
                 "--quiet"
                 "--short"
                 "HEAD")
               :directory repo-directory
               :output :string
               :error-output nil
               :ignore-error-status t)))
        (let ((branch
                (string-trim
                 '(#\Space #\Tab
                   #\Newline #\Return)
                 (or output ""))))
          (and
           (plusp (length branch))
           branch)))
    (condition () nil)))

(defparameter *git-symbolic-branch-function*
  #'run-git-symbolic-branch)

(defun git-symbolic-branch (repo-directory)
  (funcall *git-symbolic-branch-function*
           repo-directory))

(defun resolve-git-footer-branch (paths)
  (handler-case
      (let* ((content
               (string-trim
                '(#\Space #\Tab
                  #\Newline #\Return)
                (uiop:read-file-string
                 (git-footer-paths-head-path
                  paths)
                 :external-format :utf-8)))
             (prefix "ref: refs/heads/"))
        (cond
          ((uiop:string-prefix-p
            prefix content)
           (let ((branch
                   (subseq
                    content
                    (length prefix))))
             (if (string= branch ".invalid")
                 (or
                  (git-symbolic-branch
                   (git-footer-paths-repo-directory
                    paths))
                  "detached")
                 branch)))
          (t "detached")))
    (condition () :unavailable)))

(defstruct (footer-data-provider
            (:constructor
                %make-footer-data-provider))
  cwd
  git-paths
  (cached-branch :uninitialized)
  (observed-source-signature :uninitialized)
  (pending-source-signature :none)
  (pending-source-since 0
                        :type integer)
  (%statuses nil :type list)
  (available-provider-count 0
                            :type (integer 0 *))
  (callbacks nil :type list)
  (poll-seconds 0.5d0
                :type real)
  (debounce-seconds 0.5d0
                    :type real)
  (clock-function #'get-internal-real-time
                  :type function)
  stop-semaphore
  thread
  (lock
    (sb-thread:make-mutex
     :name "cadr footer data"))
  (disposed-p nil :type boolean))

(defun binary-file-signature (path)
  (when (probe-file path)
    (with-open-file
        (input path
               :direction :input
               :element-type '(unsigned-byte 8))
      (let ((checksum 0)
            (length 0))
        (loop for byte = (read-byte input nil :eof)
              until (eq byte :eof)
              do
              (setf checksum
                    (logand
                     #xffffffff
                     (+ (* checksum 33)
                        byte)))
              (incf length))
        (list
         (file-write-date path)
         length checksum)))))

(defun footer-source-signature (paths)
  (handler-case
      (let* ((head-path
               (git-footer-paths-head-path paths))
             (head
               (string-trim
                '(#\Space #\Tab
                  #\Newline #\Return)
                (uiop:read-file-string
                 head-path
                 :external-format :utf-8)))
             (reftable-directory
               (merge-pathnames
                "reftable/"
                (git-footer-paths-common-git-directory
                 paths))))
        (list
         head
         (when
             (and
              (string=
               head "ref: refs/heads/.invalid")
              (uiop:directory-exists-p
               reftable-directory))
           (loop
             for path in
             (sort
              (copy-list
               (uiop:directory-files
                reftable-directory))
              #'string<
              :key #'namestring)
             collect
             (list
              (file-namestring path)
              (binary-file-signature
               path))))))
    (condition () :unavailable)))

(defun refresh-footer-data-provider (provider)
  (let* ((paths
           (footer-data-provider-git-paths
            provider))
         (resolved
           (and paths
                (resolve-git-footer-branch
                 paths))))
    (unless (eq resolved :unavailable)
      (let ((callbacks nil))
        (sb-thread:with-mutex
            ((footer-data-provider-lock
              provider))
          (let ((previous
                  (footer-data-provider-cached-branch
                   provider)))
            (setf
             (footer-data-provider-cached-branch
              provider)
             resolved)
            (when
                (and
                 (not
                  (eq previous :uninitialized))
                 (not (equal previous resolved)))
              (setf callbacks
                    (copy-list
                     (footer-data-provider-callbacks
                      provider))))))
        (dolist (callback callbacks)
          (funcall callback)))))
  provider)

(defun footer-debounce-elapsed-p (provider)
  (>=
   (-
    (funcall
     (footer-data-provider-clock-function provider))
    (footer-data-provider-pending-source-since
     provider))
   (round
    (*
     (footer-data-provider-debounce-seconds
      provider)
     internal-time-units-per-second))))

(defun poll-footer-data-provider (provider)
  (let* ((paths
           (footer-data-provider-git-paths
            provider))
         (signature
           (and paths
                (footer-source-signature
                 paths))))
    (unless (eq signature :unavailable)
      (cond
        ((equal
          signature
          (footer-data-provider-observed-source-signature
           provider))
         (setf
          (footer-data-provider-pending-source-signature
           provider)
          :none))
        ((not
          (equal
           signature
           (footer-data-provider-pending-source-signature
            provider)))
         (setf
          (footer-data-provider-pending-source-signature
           provider)
          signature
          (footer-data-provider-pending-source-since
           provider)
          (funcall
           (footer-data-provider-clock-function provider))))
        ((footer-debounce-elapsed-p provider)
         (refresh-footer-data-provider
          provider)
         (setf
          (footer-data-provider-observed-source-signature
           provider)
          signature
          (footer-data-provider-pending-source-signature
           provider)
          :none)))))
  provider)

(defun make-footer-data-provider
    (cwd &key
           (poll-seconds 0.5d0)
           (debounce-seconds 0.5d0)
           (clock-function #'get-internal-real-time))
  (let* ((provider
           (%make-footer-data-provider
            :cwd
            (uiop:ensure-directory-pathname
             cwd)
            :git-paths
            (find-git-footer-paths cwd)
            :poll-seconds poll-seconds
            :debounce-seconds
            debounce-seconds
            :clock-function clock-function
            :stop-semaphore
            (sb-thread:make-semaphore
             :count 0)))
         (symbolic-branch-function
           *git-symbolic-branch-function*))
    (refresh-footer-data-provider provider)
    (when
        (footer-data-provider-git-paths
         provider)
      (setf
       (footer-data-provider-observed-source-signature
        provider)
       (footer-source-signature
        (footer-data-provider-git-paths
         provider))))
    (when
        (footer-data-provider-git-paths
         provider)
      (setf
       (footer-data-provider-thread provider)
       (sb-thread:make-thread
        (lambda ()
          (let ((*git-symbolic-branch-function*
                  symbolic-branch-function))
            (loop
              until
              (sb-thread:wait-on-semaphore
               (footer-data-provider-stop-semaphore
                provider)
               :timeout
               (footer-data-provider-poll-seconds
                provider))
              do
              (poll-footer-data-provider
               provider))))
        :name "cadr footer git watcher")))
    provider))

(defun footer-data-provider-git-branch
    (provider)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (let ((branch
            (footer-data-provider-cached-branch
             provider)))
      (unless (eq branch :uninitialized)
        branch))))

(defun footer-data-provider-on-branch-change
    (provider callback)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (pushnew
     callback
     (footer-data-provider-callbacks
      provider)))
  (lambda ()
    (sb-thread:with-mutex
        ((footer-data-provider-lock provider))
      (setf
       (footer-data-provider-callbacks provider)
       (delete
        callback
        (footer-data-provider-callbacks
         provider))))))

(defun footer-data-provider-set-status
    (provider key text)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (setf
     (footer-data-provider-%statuses provider)
     (if text
         (acons
          key text
          (remove
           key
           (footer-data-provider-%statuses
            provider)
           :key #'car
           :test #'string=))
         (remove
          key
          (footer-data-provider-%statuses
           provider)
          :key #'car
          :test #'string=))))
  text)

(defun footer-data-provider-statuses
    (provider)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (copy-tree
     (footer-data-provider-%statuses
      provider))))

(defun footer-data-provider-dispose
    (provider)
  (let ((thread nil))
    (sb-thread:with-mutex
        ((footer-data-provider-lock provider))
      (unless
          (footer-data-provider-disposed-p
           provider)
        (setf
         (footer-data-provider-disposed-p
          provider)
         t
         thread
         (footer-data-provider-thread
          provider)
         (footer-data-provider-callbacks
          provider)
         nil)
        (sb-thread:signal-semaphore
         (footer-data-provider-stop-semaphore
          provider))))
    (when thread
      (stop-thread-for-cleanup thread)))
  nil)

(defstruct theme-detection
  theme
  source
  confidence)

(defun colorfgbg-background-index (value)
  (loop
    for part in
    (reverse
     (uiop:split-string
      value :separator '(#\;)))
    for trimmed =
    (string-trim
     '(#\Space #\Tab #\Newline #\Return)
     part)
    for index =
    (ignore-errors
      (parse-integer trimmed :junk-allowed t))
    when (and index (<= 0 index 255))
      return index))

(defun detect-background-from-environment
    (&optional environment)
  (let ((value
          (or
           (cdr (assoc "COLORFGBG"
                       environment
                       :test #'string=))
           (and (null environment)
                (uiop:getenv "COLORFGBG")))))
    (if value
        (let ((index
                (colorfgbg-background-index
                 value)))
          (if index
              (make-theme-detection
               :theme
               (apply #'rgb-background-theme
                      (xterm-color-to-rgb index))
               :source "COLORFGBG"
               :confidence :high)
              (make-theme-detection
               :theme :dark
               :source "fallback"
               :confidence :low)))
        (make-theme-detection
         :theme :dark
         :source "fallback"
         :confidence :low))))

(defun rgb-background-theme (red green blue)
  (dolist (channel (list red green blue))
    (check-type channel (integer 0 255)))
  (let* ((linear
           (lambda (value)
             (let ((channel (/ value 255d0)))
               (if (<= channel 0.03928d0)
                   (/ channel 12.92d0)
                   (expt
                    (/ (+ channel 0.055d0)
                       1.055d0)
                    2.4d0)))))
         (luminance
           (+
            (* 0.2126d0
               (funcall linear red))
            (* 0.7152d0
               (funcall linear green))
            (* 0.0722d0
               (funcall linear blue)))))
    (if (>= luminance 0.5d0)
        :light :dark)))

(defun parse-auto-theme-setting (setting)
  (when (stringp setting)
    (let ((slash (position #\/ setting)))
      (when
          (and slash
               (null
                (position #\/ setting
                          :start (1+ slash))))
        (let ((light
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (subseq setting 0 slash)))
              (dark
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (subseq setting (1+ slash)))))
          (when
              (and (plusp (length light))
                   (plusp (length dark)))
            (list :light-theme light
                  :dark-theme dark)))))))

(defun resolve-theme-setting
    (setting background)
  (let ((auto
          (parse-auto-theme-setting setting)))
    (cond
      (auto
       (ecase background
         (:light (getf auto :light-theme))
         (:dark (getf auto :dark-theme))))
      ((and (stringp setting)
            (find #\/ setting))
       nil)
      ((stringp setting) setting)
      (t nil))))

(defun xterm-color-to-rgb (index)
  (unless (typep index '(integer 0 255))
    (return-from xterm-color-to-rgb nil))
  (cond
    ((< index 16)
     (nth
      index
      '((0 0 0) (128 0 0) (0 128 0)
        (128 128 0) (0 0 128) (128 0 128)
        (0 128 128) (192 192 192)
        (128 128 128) (255 0 0) (0 255 0)
        (255 255 0) (0 0 255) (255 0 255)
        (0 255 255) (255 255 255))))
    ((< index 232)
     (let* ((value (- index 16))
            (red (floor value 36))
            (green (floor (mod value 36) 6))
            (blue (mod value 6))
            (levels #(0 95 135 175 215 255)))
       (list (aref levels red)
             (aref levels green)
             (aref levels blue))))
    ((< index 256)
     (let ((gray (+ 8 (* 10 (- index 232)))))
       (list gray gray gray)))
    (t nil)))

(defun rgb-hex (rgb)
  (and rgb
       (format nil "#~2,'0X~2,'0X~2,'0X"
               (first rgb)
               (second rgb)
               (third rgb))))

(defun resolve-theme-value
    (value variables &optional seen)
  (cond
    ((integerp value)
     (rgb-hex
      (xterm-color-to-rgb value)))
    ((not (stringp value)) nil)
    ((zerop (length value)) nil)
    ((char= (char value 0) #\#)
     (string-downcase value))
    ((member value seen :test #'string=)
     nil)
    (t
     (resolve-theme-value
      (cadr-ai::json-get variables value)
      variables
      (cons value seen)))))

(defun theme-export-colors (theme)
  (let ((variables
          (or
           (cadr-ai::json-get theme "vars")
           (empty-json-object)))
        (export
          (or
           (cadr-ai::json-get theme "export")
           (empty-json-object))))
    (list
     :page-bg
     (resolve-theme-value
      (cadr-ai::json-get export "pageBg")
      variables)
     :card-bg
     (resolve-theme-value
      (cadr-ai::json-get export "cardBg")
      variables)
     :info-bg
     (resolve-theme-value
      (cadr-ai::json-get export "infoBg")
      variables))))

(defun load-theme-summaries (directory)
  (sort
   (loop
     for path in
     (uiop:directory-files
      (uiop:ensure-directory-pathname directory)
      "*.json")
     for object =
     (handler-case
         (cadr-ai::parse-json
          (uiop:read-file-string
           path :external-format :utf-8))
       (condition () nil))
     when (hash-table-p object)
       collect
       (list
        :name
        (or
         (cadr-ai::json-get object "name")
         (pathname-name path))
        :path path
        :object object))
   #'string<
   :key (lambda (entry)
          (getf entry :name))))

(defun clipboard-command-candidates
    (&key
       platform
       termux-p
       wayland-p
       wayland-display-p
       x11-display-p)
  (cond
    ((eq platform :darwin)
     '(("pbcopy")))
    ((eq platform :windows)
     '(("clip")))
    (t
     (append
      (and termux-p
           '(("termux-clipboard-set")))
      (and wayland-p wayland-display-p
           '(("wl-copy")))
      (and x11-display-p
           '(("xclip" "-selection" "clipboard")
             ("xsel" "--clipboard" "--input")))))))

(defun osc52-copy-sequence
    (text &key (maximum-bytes 100000))
  (let* ((bytes (cadr-ai::utf8-octets text))
         (encoded
           (encode-base64-bytes bytes)))
    (when (<= (length encoded)
              maximum-bytes)
      (format nil "~C]52;c;~A~C"
              #\Escape encoded
              (code-char 7)))))

(defun read-clipboard-text (&key native-getter)
  (when native-getter
    (handler-case
        (let ((text
                (funcall native-getter)))
          (and (stringp text)
               (plusp (length text))
               text))
      (condition () nil))))

(defun default-clipboard-copy-runner (argv input)
  (handler-case
      (progn
        (uiop:run-program
         argv
         :input
         (make-string-input-stream input)
         :output nil
         :error-output nil)
        t)
    (condition () nil)))

(defun copy-to-clipboard
    (text
     &key
       (platform :linux)
       termux-p
       wayland-p
       wayland-display-p
       x11-display-p
       remote-p
       native-setter
       (command-runner
         #'default-clipboard-copy-runner)
       (output *standard-output*))
  (let ((copied-p nil)
        (native-p nil)
        (shell-p nil))
    (when (and native-setter
               (not (eq platform :linux)))
      (handler-case
          (progn
            (funcall native-setter text)
            (setf copied-p t
                  native-p t))
        (condition () nil)))
    (when (and copied-p
               (not remote-p))
      (return-from copy-to-clipboard :native))
    (unless copied-p
      (dolist
          (argv
           (clipboard-command-candidates
            :platform platform
            :termux-p termux-p
            :wayland-p wayland-p
            :wayland-display-p wayland-display-p
            :x11-display-p x11-display-p))
        (when
            (handler-case
                (funcall command-runner argv text)
              (condition () nil))
          (setf copied-p t
                shell-p t)
          (return))))
    (let ((osc52
            (and
             (or remote-p
                 (not copied-p))
             (osc52-copy-sequence text))))
      (when osc52
        (write-string osc52 output)
        (finish-output output)
        (setf copied-p t))
      (unless copied-p
        (error
         'cadr-ai:configuration-error
         :message "Failed to copy to clipboard"))
      (cond
        ((and native-p osc52) :native+osc52)
        ((and shell-p osc52) :shell+osc52)
        (native-p :native)
        (shell-p :shell)
        (osc52 :osc52)
        (t :unknown)))))

(defstruct clipboard-image
  bytes
  mime-type)

(defstruct image-process-result
  bytes
  mime-type
  (original-width 0 :type (integer 0 *))
  (original-height 0 :type (integer 0 *))
  (width 0 :type (integer 0 *))
  (height 0 :type (integer 0 *))
  (resized-p nil :type boolean)
  (hints nil :type list))

(declaim (ftype function process-image-bytes))

(defparameter +clipboard-image-mime-preference+
  '("image/png" "image/jpeg" "image/webp"
    "image/gif"))

(defun clipboard-environment-value
    (environment name)
  (if environment
      (cdr
       (assoc name environment :test #'string=))
      (uiop:getenv name)))

(defun clipboard-wayland-p (environment)
  (or
   (clipboard-environment-value
    environment "WAYLAND_DISPLAY")
   (string-equal
    (or
     (clipboard-environment-value
      environment "XDG_SESSION_TYPE")
     "")
    "wayland")))

(defun clipboard-wsl-p (environment)
  (or
   (clipboard-environment-value
    environment "WSL_DISTRO_NAME")
   (clipboard-environment-value
    environment "WSLENV")
   (ignore-errors
     (search
      "microsoft"
      (string-downcase
       (uiop:read-file-string
        #P"/proc/version"
        :external-format :utf-8))))))

(defun clipboard-base-mime-type (value)
  (string-downcase
   (string-trim
    '(#\Space #\Tab)
    (first
     (uiop:split-string
      value :separator '(#\;))))))

(defun preferred-clipboard-image-mime
    (text)
  (let ((types
          (remove
           ""
           (mapcar
            (lambda (line)
              (string-trim
               '(#\Space #\Tab #\Return)
               line))
            (uiop:split-string
             text :separator '(#\Newline)))
           :test #'string=)))
    (or
     (loop for preferred
           in +clipboard-image-mime-preference+
           thereis
           (find
            preferred types
            :test
            (lambda (left right)
              (string=
               left
               (clipboard-base-mime-type
                right)))))
     (find-if
      (lambda (value)
        (uiop:string-prefix-p
         "image/"
         (clipboard-base-mime-type value)))
      types))))

(defun default-clipboard-image-runner (argv)
  (handler-case
      (let ((bytes
              (uiop:run-program
               argv
               :output :byte-vector
               :error-output nil)))
        (values bytes t))
    (condition ()
      (values
       (make-array
        0 :element-type '(unsigned-byte 8))
       nil))))

(defun clipboard-command-text (bytes)
  (handler-case
      (sb-ext:octets-to-string
       bytes :external-format :utf-8)
    (condition () "")))

(defun clipboard-image-from-bytes
    (bytes mime-type)
  (when (and bytes
             (plusp (length bytes)))
    (let ((base
            (clipboard-base-mime-type
             mime-type)))
      (if
          (member
           base
           +clipboard-image-mime-preference+
           :test #'string=)
          (make-clipboard-image
           :bytes bytes
           :mime-type base)
          (let ((processed
                  (process-image-bytes
                   bytes base
                   :auto-resize-p nil)))
            (when
                (and
                 (image-process-result-mime-type
                  processed)
                 (member
                  (image-process-result-mime-type
                   processed)
                  +clipboard-image-mime-preference+
                  :test #'string=))
              (make-clipboard-image
               :bytes
               (image-process-result-bytes
                processed)
               :mime-type
               (image-process-result-mime-type
                processed))))))))

(defun read-clipboard-image-via-wl-paste
    (runner)
  (multiple-value-bind (type-bytes ok)
      (funcall runner
               '("wl-paste" "--list-types"))
    (when ok
      (let ((mime
              (preferred-clipboard-image-mime
               (clipboard-command-text type-bytes))))
        (when mime
          (multiple-value-bind (bytes read-ok)
              (funcall
               runner
               (list
                "wl-paste" "--type" mime
                "--no-newline"))
            (when read-ok
              (clipboard-image-from-bytes
               bytes mime))))))))

(defun read-clipboard-image-via-xclip
    (runner)
  (multiple-value-bind (target-bytes target-ok)
      (funcall
       runner
       '("xclip" "-selection" "clipboard"
         "-t" "TARGETS" "-o"))
    (let* ((preferred
             (and target-ok
                  (preferred-clipboard-image-mime
                   (clipboard-command-text
                    target-bytes))))
           (types
             (remove-duplicates
              (append
               (and preferred (list preferred))
               +clipboard-image-mime-preference+)
              :test #'string=)))
      (dolist (mime types)
        (multiple-value-bind (bytes ok)
            (funcall
             runner
             (list
              "xclip" "-selection" "clipboard"
              "-t" mime "-o"))
          (when ok
            (let ((image
                    (clipboard-image-from-bytes
                     bytes mime)))
              (when image
                (return-from
                    read-clipboard-image-via-xclip
                  image)))))))))

(defun read-clipboard-image-via-native
    (native-image-reader)
  (when native-image-reader
    (handler-case
        (multiple-value-bind (bytes mime-type)
            (funcall native-image-reader)
          (clipboard-image-from-bytes
           bytes (or mime-type "image/png")))
      (condition () nil))))

(defun default-clipboard-temporary-path ()
  (merge-pathnames
   (format nil "pi-wsl-clip-~A.png"
           (cadr-ai:uuid-v7))
   (uiop:temporary-directory)))

(defun powershell-single-quote (text)
  (cl-ppcre:regex-replace-all
   "'" text "''"))

(defun read-clipboard-image-via-powershell
    (runner temporary-path-provider)
  (let ((temporary
          (funcall temporary-path-provider)))
    (unwind-protect
         (handler-case
             (multiple-value-bind
                   (path-bytes path-ok)
                 (funcall
                  runner
                  (list
                   "wslpath" "-w"
                   (namestring temporary)))
               (unless path-ok
                 (return-from
                     read-clipboard-image-via-powershell
                   nil))
               (let ((windows-path
                       (string-trim
                        '(#\Space #\Tab #\Newline
                          #\Return)
                        (clipboard-command-text
                         path-bytes))))
                 (when
                     (zerop (length windows-path))
                   (return-from
                       read-clipboard-image-via-powershell
                     nil))
                 (let ((script
                         (format
                          nil
                          "~{~A~^; ~}"
                          (list
                           "Add-Type -AssemblyName System.Windows.Forms"
                           "Add-Type -AssemblyName System.Drawing"
                           (format
                            nil "$path = '~A'"
                            (powershell-single-quote
                             windows-path))
                           "$img = [System.Windows.Forms.Clipboard]::GetImage()"
                           "if ($img) { $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); Write-Output 'ok' } else { Write-Output 'empty' }"))))
                   (multiple-value-bind
                         (output ok)
                       (funcall
                        runner
                        (list
                         "powershell.exe"
                         "-NoProfile"
                         "-Command"
                         script))
                     (when
                         (and
                          ok
                          (string=
                           "ok"
                           (string-trim
                            '(#\Space #\Tab
                              #\Newline #\Return)
                            (clipboard-command-text
                             output)))
                          (probe-file temporary))
                       (let ((bytes
                               (read-binary-file
                                temporary)))
                         (when
                             (plusp (length bytes))
                           (make-clipboard-image
                            :bytes bytes
                            :mime-type
                            "image/png"))))))))
           (condition () nil))
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun read-clipboard-image
    (&key
       environment
       (platform :linux)
       (command-runner
         #'default-clipboard-image-runner)
       native-image-reader
       (temporary-path-provider
         #'default-clipboard-temporary-path))
  (when
      (clipboard-environment-value
       environment "TERMUX_VERSION")
    (return-from read-clipboard-image nil))
  (if (eq platform :linux)
      (let* ((wayland-p
               (clipboard-wayland-p environment))
             (wsl-p
               (clipboard-wsl-p environment))
             (image
               (and
                (or wayland-p wsl-p)
                (or
                 (read-clipboard-image-via-wl-paste
                  command-runner)
                 (read-clipboard-image-via-xclip
                  command-runner)))))
        (or
         image
         (and
          wsl-p
          (read-clipboard-image-via-powershell
           command-runner
           temporary-path-provider))
         (and
          (not wayland-p)
          (or
           (read-clipboard-image-via-native
            native-image-reader)
           (read-clipboard-image-via-xclip
            command-runner)))))
      (read-clipboard-image-via-native
       native-image-reader)))

(defun u32-be (bytes offset)
  (logior
   (ash (aref bytes offset) 24)
   (ash (aref bytes (1+ offset)) 16)
   (ash (aref bytes (+ offset 2)) 8)
   (aref bytes (+ offset 3))))

(defun jpeg-dimensions (bytes)
  (when (bytes-prefix-p bytes #(255 216 255))
    (loop with position = 2
          while (< (+ position 3)
                   (length bytes))
          do
          (unless (= (aref bytes position) #xff)
            (incf position)
            (loop-finish))
          (loop while
                (and (< position (length bytes))
                     (= (aref bytes position)
                        #xff))
                do (incf position))
          (when (>= position (length bytes))
            (return))
          (let ((marker (aref bytes position)))
            (incf position)
            (cond
              ((or (= marker #xd8)
                   (= marker #xd9))
               nil)
              ((= marker #xda)
               (return))
              (t
               (when (> (+ position 1)
                        (1- (length bytes)))
                 (return))
               (let ((size
                       (+
                        (ash
                         (aref bytes position)
                         8)
                        (aref bytes
                              (1+ position)))))
                 (when (or (< size 2)
                           (> (+ position size)
                              (length bytes)))
                   (return))
                 (when
                     (member marker
                             '(#xc0 #xc1 #xc2 #xc3
                               #xc5 #xc6 #xc7
                               #xc9 #xca #xcb
                               #xcd #xce #xcf))
                   (return-from
                       jpeg-dimensions
                     (values
                      (+
                       (ash
                        (aref bytes
                              (+ position 5))
                        8)
                       (aref bytes
                             (+ position 6)))
                      (+
                       (ash
                        (aref bytes
                              (+ position 3))
                        8)
                       (aref bytes
                             (+ position 4)))
                      t)))
                 (incf position size))))))))

(defun image-dimensions-from-bytes
    (bytes mime-type)
  (cond
    ((and
      (string= mime-type "image/png")
      (>= (length bytes) 24)
      (bytes-prefix-p
       bytes
       #(137 80 78 71 13 10 26 10)))
     (values
      (u32-be bytes 16)
      (u32-be bytes 20)
      t))
    ((string= mime-type "image/jpeg")
     (jpeg-dimensions bytes))
    ((and
      (string= mime-type "image/bmp")
      (>= (length bytes) 26))
     (values
      (abs (s32-le bytes 18))
      (abs (s32-le bytes 22))
      t))
    (t
     (values nil nil nil))))

(defun process-image-bytes
    (bytes mime-type
     &key (auto-resize-p t)
       (max-width 2000)
       (max-height 2000)
       (max-bytes (* 9 512 1024))
       (jpeg-quality 80)
       resize-function)
  (let ((effective-bytes bytes)
        (effective-mime mime-type)
        (hints nil))
    (when (string= mime-type "image/bmp")
      (setf effective-bytes
            (bmp-to-png bytes)
            effective-mime "image/png")
      (push
       "[Image converted from image/bmp to image/png.]"
       hints))
    (multiple-value-bind (rgba width height)
        (decode-image-rgba
         effective-bytes effective-mime)
      (unless rgba
        (return-from process-image-bytes nil))
      (let ((resize-required-p
              (and
               auto-resize-p
               (or (> width max-width)
                   (> height max-height)
                   (>=
                    (base64-encoded-byte-size
                     effective-bytes)
                    max-bytes)))))
        (cond
          ((not resize-required-p)
           (make-image-process-result
            :bytes (copy-seq effective-bytes)
            :mime-type effective-mime
            :original-width width
            :original-height height
            :width width
            :height height
            :resized-p nil
            :hints (nreverse hints)))
          (resize-function
           (funcall
            resize-function
            effective-bytes effective-mime
            width height
            max-width max-height max-bytes
            (nreverse hints)))
          (t
           (multiple-value-bind
                 (resized-bytes resized-mime
                  resized-width resized-height)
               (resize-image-rgba-to-limits
                rgba width height
                max-width max-height max-bytes
                :jpeg-quality jpeg-quality)
             (when resized-bytes
               (make-image-process-result
                :bytes resized-bytes
                :mime-type resized-mime
                :original-width width
                :original-height height
                :width resized-width
                :height resized-height
                :resized-p t
                :hints
                (nreverse hints))))))))))

(defun format-image-dimension-note (result)
  (when (image-process-result-resized-p result)
    (let ((scale
            (/ (image-process-result-original-width result)
               (max 1
                    (image-process-result-width result)))))
      (format
       nil
       "[Image: original ~Dx~D, displayed at ~Dx~D. Multiply coordinates by ~,2F to map to original image.]"
       (image-process-result-original-width result)
       (image-process-result-original-height result)
       (image-process-result-width result)
       (image-process-result-height result)
       (coerce scale 'double-float)))))

(defun process-image-data (bytes)
  (let ((mime-type (detect-image-mime-type bytes)))
    (when mime-type
      (if (member mime-type
                  '("image/gif" "image/webp")
                  :test #'string=)
          (values bytes mime-type nil nil)
          (let ((processed
                  (handler-case
                      (process-image-bytes bytes mime-type)
                    (condition () nil))))
            (if processed
                (let* ((dimension-note
                         (format-image-dimension-note
                          processed))
                       (hints
                         (append
                          (copy-list
                           (image-process-result-hints
                            processed))
                          (and dimension-note
                               (list dimension-note)))))
                  (values
                   (image-process-result-bytes processed)
                   (image-process-result-mime-type processed)
                   hints nil))
                (values
                 nil mime-type nil
                 (if (string= mime-type "image/bmp")
                     "[Image omitted: could not be converted to a supported inline image format.]"
                     "[Image omitted: could not be resized below the inline image size limit.]"))))))))

(defun process-image-file (path)
  (process-image-data (read-binary-file path)))

(defparameter +syntax-highlight-languages+
  '("bash" "c" "clojure" "cmake" "cpp" "csharp"
    "css" "diff" "dockerfile" "elixir" "erlang"
    "fish" "go" "graphql" "haskell" "hcl" "html"
    "java" "javascript" "json" "kotlin" "less"
    "lisp" "lua" "makefile" "markdown" "ocaml"
    "perl" "php" "powershell" "protobuf" "python"
    "r" "ruby" "rust" "sass" "scala" "scss" "sql"
    "swift" "toml" "typescript" "vim" "xml" "yaml"))

(defun supports-syntax-language-p (language)
  (not
   (null
    (member
     (string-downcase language)
     +syntax-highlight-languages+
     :test #'string=))))

(defun decode-highlight-entity (entity)
  (cond
    ((string= entity "lt") "<")
    ((string= entity "gt") ">")
    ((string= entity "quot") "\"")
    ((string= entity "apos") "'")
    ((string= entity "amp") "&")
    ((and
      (> (length entity) 1)
      (char= (char entity 0) #\#)
      (every #'digit-char-p
             (subseq entity 1)))
     (let ((character
             (code-char
              (parse-integer entity
                             :start 1))))
       (and character
            (string character))))
    (t nil)))

(defun decode-highlight-text (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          do
          (if (char= (char text index) #\&)
              (let ((semicolon
                      (position #\; text
                                :start (1+ index))))
                (if semicolon
                    (let ((decoded
                            (decode-highlight-entity
                             (subseq text
                                     (1+ index)
                                     semicolon))))
                      (if decoded
                          (progn
                            (write-string decoded output)
                            (setf index
                                  (1+ semicolon)))
                          (progn
                            (write-char #\& output)
                            (incf index))))
                    (progn
                      (write-char #\& output)
                      (incf index))))
              (progn
                (write-char (char text index)
                            output)
                (incf index))))))

(defun highlight-class-name (tag)
  (let ((marker (search "class=\"" tag)))
    (when marker
      (let* ((start (+ marker 7))
             (end (position #\" tag
                            :start start))
             (value
               (and end
                    (subseq tag start end))))
        (and
         value
         (find-if
          (lambda (name)
            (uiop:string-prefix-p
             "hljs-" name))
          (uiop:split-string
           value :separator '(#\Space))))))))

(defun render-highlighted-html
    (html &optional theme)
  (let ((formatters nil)
        (segments nil)
        (index 0))
    (labels
        ((emit (text)
           (when (plusp (length text))
             (let* ((decoded
                      (decode-highlight-text text))
                    (formatter
                      (find-if #'identity
                               formatters)))
               (push
                (if formatter
                    (funcall formatter decoded)
                    decoded)
                segments)))))
      (loop while (< index (length html))
            for open = (position #\< html
                                 :start index)
            do
            (if (null open)
                (progn
                  (emit (subseq html index))
                  (setf index (length html)))
                (progn
                  (emit (subseq html index open))
                  (let ((close
                          (position #\> html
                                    :start open)))
                    (if (null close)
                        (progn
                          (emit (subseq html open))
                          (setf index
                                (length html)))
                        (let ((tag
                                (subseq html
                                        (1+ open)
                                        close)))
                          (cond
                            ((uiop:string-prefix-p
                              "/span" tag)
                             (pop formatters))
                            ((uiop:string-prefix-p
                              "span" tag)
                             (let* ((class
                                      (highlight-class-name
                                       tag))
                                    (scope
                                      (and class
                                           (subseq class 5)))
                                    (formatter
                                      (and scope
                                           (cdr
                                            (assoc
                                             scope theme
                                             :test
                                             #'string=)))))
                               (push
                                (or formatter
                                    (first formatters))
                                formatters))))
                          (setf index (1+ close))))))))
      (apply #'concatenate 'string
             (nreverse segments)))))

(defparameter +simple-syntax-keywords+
  '("as" "async" "await" "break" "case"
    "catch" "class" "const" "continue"
    "def" "default" "do" "else" "enum"
    "export" "extends" "false" "finally"
    "for" "from" "function" "if" "import"
    "in" "interface" "let" "match" "new"
    "nil" "null" "package" "pass" "private"
    "protected" "public" "raise" "return"
    "static" "struct" "super" "switch" "this"
    "throw" "trait" "true" "try" "type"
    "typeof" "undefined" "var" "void" "while"
    "with" "yield"))

(defparameter +simple-syntax-types+
  '("any" "boolean" "byte" "char" "double"
    "float" "int" "integer" "long" "map"
    "number" "object" "record" "short"
    "string" "symbol" "tuple" "uint" "vector"))

(defparameter +simple-syntax-color-keys+
  '(("comment" . :syntax-comment)
    ("keyword" . :syntax-keyword)
    ("function" . :syntax-function)
    ("variable" . :syntax-variable)
    ("string" . :syntax-string)
    ("number" . :syntax-number)
    ("type" . :syntax-type)
    ("operator" . :syntax-operator)
    ("punctuation" . :syntax-punctuation)
    ("meta" . :muted)
    ("addition" . :tool-diff-added)
    ("deletion" . :tool-diff-removed)))

(defun simple-syntax-formatter (scope theme)
  (or
   (cdr (assoc scope theme :test #'string=))
   (let ((color
           (cdr
            (assoc scope
                   +simple-syntax-color-keys+
                   :test #'string=))))
     (and
      color
      (lambda (text)
        (cadr-tui:theme-foreground
         color text :enabled-p t))))))

(defun write-simple-syntax-token
    (text scope theme output)
  (let ((formatter
          (and scope
               (simple-syntax-formatter
                scope theme))))
    (write-string
     (if formatter
         (funcall formatter text)
         text)
     output)))

(defun write-simple-syntax-range
    (code start end scope theme output)
  (when (< start end)
    (write-simple-syntax-token
     (subseq code start end)
     scope theme output)))

(defun simple-syntax-next-nonspace-index
    (code start)
  (loop for index from start below (length code)
        unless
        (member (char code index)
                '(#\Space #\Tab #\Newline
                  #\Return))
          return index))

(defun simple-syntax-quoted-end
    (code start)
  (let ((quote (char code start))
        (index (1+ start))
        (escaped-p nil))
    (loop while (< index (length code))
          for character = (char code index)
          do
          (cond
            (escaped-p
             (setf escaped-p nil))
            ((char= character #\\)
             (setf escaped-p t))
            ((char= character quote)
             (return (1+ index))))
          (incf index)
          finally (return index))))

(defun simple-syntax-highlight-diff
    (code theme)
  (with-output-to-string (output)
    (loop with start = 0
          while (< start (length code))
          for newline =
            (position #\Newline code :start start)
          for end = (or newline (length code))
          for scope =
            (and (< start end)
                 (case (char code start)
                   (#\+ "addition")
                   (#\- "deletion")
                   (otherwise nil)))
          do
          (write-simple-syntax-range
           code start end scope theme output)
          (when newline
            (write-char #\Newline output))
          (setf start
                (if newline
                    (1+ newline)
                    (length code))))))

(defun simple-syntax-markup-name-part-p
    (character)
  (or (alphanumericp character)
      (member character '(#\- #\_ #\:))))

(defun simple-syntax-highlight-markup
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          do
          (cond
            ((and
              (<= (+ index 4) (length code))
              (string= "<!--" code
                       :start2 index
                       :end2 (+ index 4)))
             (let* ((close
                      (search "-->" code
                              :start2 (+ index 4)))
                    (end
                      (if close
                          (+ close 3)
                          (length code))))
               (write-simple-syntax-range
                code index end "comment"
                theme output)
               (setf index end)))
            ((char= (char code index) #\<)
             (let ((prefix-end
                     (if
                         (and
                          (< (1+ index) (length code))
                          (char= (char code (1+ index))
                                 #\/))
                         (+ index 2)
                         (1+ index))))
               (write-simple-syntax-range
                code index prefix-end
                "punctuation" theme output)
               (setf index prefix-end)
               (let ((name-end index))
                 (loop while
                       (and
                        (< name-end (length code))
                        (simple-syntax-markup-name-part-p
                         (char code name-end)))
                       do (incf name-end))
                 (write-simple-syntax-range
                  code index name-end "keyword"
                  theme output)
                 (setf index name-end))
               (loop while (< index (length code))
                     for character = (char code index)
                     do
                     (cond
                       ((char= character #\>)
                        (write-simple-syntax-range
                         code index (1+ index)
                         "punctuation" theme output)
                        (incf index)
                        (return))
                       ((and
                         (char= character #\/)
                         (< (1+ index) (length code))
                         (char= (char code (1+ index))
                                #\>))
                        (write-simple-syntax-range
                         code index (+ index 2)
                         "punctuation" theme output)
                        (incf index 2)
                        (return))
                       ((member character
                                '(#\Space #\Tab
                                  #\Newline #\Return))
                        (let ((end (1+ index)))
                          (loop while
                                (and
                                 (< end (length code))
                                 (member
                                  (char code end)
                                  '(#\Space #\Tab
                                    #\Newline
                                    #\Return)))
                                do (incf end))
                          (write-simple-syntax-range
                           code index end
                           "punctuation" theme output)
                          (setf index end)))
                       ((member character '(#\" #\'))
                        (let ((end
                                (simple-syntax-quoted-end
                                 code index)))
                          (write-simple-syntax-range
                           code index end "string"
                           theme output)
                          (setf index end)))
                       ((simple-syntax-markup-name-part-p
                         character)
                        (let ((end (1+ index)))
                          (loop while
                                (and
                                 (< end (length code))
                                 (simple-syntax-markup-name-part-p
                                  (char code end)))
                                do (incf end))
                          (write-simple-syntax-range
                           code index end "variable"
                           theme output)
                          (setf index end)))
                       (t
                        (write-simple-syntax-range
                         code index (1+ index)
                         "punctuation" theme output)
                        (incf index))))))
            (t
             (let ((end
                     (or (position #\< code
                                   :start (1+ index))
                         (length code))))
               (write-string
                (subseq code index end) output)
               (setf index end)))))))

(defun simple-syntax-highlight-json
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          for character = (char code index)
          do
          (cond
            ((char= character #\")
             (let* ((end
                      (simple-syntax-quoted-end
                       code index))
                    (next
                      (simple-syntax-next-nonspace-index
                       code end))
                    (scope
                      (if
                          (and next
                               (char= (char code next)
                                      #\:))
                          "variable"
                          "string")))
               (write-simple-syntax-range
                code index end scope theme output)
               (setf index end)))
            ((or (digit-char-p character)
                 (and
                  (char= character #\-)
                  (< (1+ index) (length code))
                  (digit-char-p
                   (char code (1+ index)))))
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (digit-char-p (char code end))
                       (member (char code end)
                               '(#\. #\e #\E #\+ #\-))))
                     do (incf end))
               (write-simple-syntax-range
                code index end "number"
                theme output)
               (setf index end)))
            ((alpha-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and (< end (length code))
                          (alpha-char-p
                           (char code end)))
                     do (incf end))
               (write-simple-syntax-range
                code index end
                (and
                 (member
                  (string-downcase
                   (subseq code index end))
                  '("true" "false" "null")
                  :test #'string=)
                 "number")
                theme output)
               (setf index end)))
            (t
             (write-char character output)
             (incf index))))))

(defparameter +simple-bash-built-ins+
  '("alias" "bg" "bind" "break" "builtin"
    "cd" "command" "compgen" "complete"
    "continue" "declare" "dirs" "disown"
    "echo" "enable" "eval" "exec" "exit"
    "export" "fc" "fg" "getopts" "hash"
    "help" "history" "jobs" "kill" "let"
    "local" "logout" "mapfile" "popd"
    "printf" "pushd" "pwd" "read"
    "readonly" "return" "set" "shift"
    "shopt" "source" "suspend" "test"
    "times" "trap" "type" "typeset"
    "ulimit" "umask" "unalias" "unset"
    "wait"))

(defparameter +simple-bash-keywords+
  '("case" "coproc" "do" "done" "elif"
    "else" "esac" "fi" "for" "function"
    "if" "in" "select" "then" "time"
    "until" "while"))

(defun simple-syntax-bash-variable-end
    (code start limit)
  (cond
    ((and (< (1+ start) limit)
          (char= (char code (1+ start)) #\{))
     (let ((close
             (position #\} code
                       :start (+ start 2)
                       :end limit)))
       (if close (1+ close) (1+ start))))
    (t
     (let ((end (1+ start)))
       (loop while
             (and
              (< end limit)
              (or
               (alphanumericp (char code end))
               (member (char code end)
                       '(#\_ #\@ #\# #\? #\!
                         #\- #\$))))
             do (incf end))
       end))))

(defun simple-syntax-write-bash-string
    (code start end theme output)
  (if (char= (char code start) #\')
      (write-simple-syntax-range
       code start end "string" theme output)
      (loop with segment-start = start
            with index = (1+ start)
            while (< index end)
            do
            (if (char= (char code index) #\$)
                (let ((variable-end
                        (simple-syntax-bash-variable-end
                         code index end)))
                  (write-simple-syntax-range
                   code segment-start index
                   "string" theme output)
                  (write-simple-syntax-range
                   code index variable-end
                   "variable" theme output)
                  (setf index variable-end
                        segment-start variable-end))
                (incf index))
            finally
            (write-simple-syntax-range
             code segment-start end
             "string" theme output))))

(defun simple-syntax-highlight-bash
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          for character = (char code index)
          do
          (cond
            ((char= character #\#)
             (let ((end
                     (or (position #\Newline code
                                   :start (1+ index))
                         (length code))))
               (write-simple-syntax-range
                code index end "comment"
                theme output)
               (setf index end)))
            ((member character '(#\" #\'))
             (let ((end
                     (simple-syntax-quoted-end
                      code index)))
               (simple-syntax-write-bash-string
                code index end theme output)
               (setf index end)))
            ((char= character #\$)
             (let ((end
                     (simple-syntax-bash-variable-end
                      code index (length code))))
               (write-simple-syntax-range
                code index end "variable"
                theme output)
               (setf index end)))
            ((or (alpha-char-p character)
                 (char= character #\_))
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (alphanumericp (char code end))
                       (char= (char code end) #\_)))
                     do (incf end))
               (let* ((word (subseq code index end))
                      (lower (string-downcase word))
                      (next
                        (simple-syntax-next-nonspace-index
                         code end))
                      (function-p
                        (and next
                             (char= (char code next) #\()
                             (< (1+ next) (length code))
                             (char= (char code (1+ next))
                                    #\)))))
                 (write-simple-syntax-range
                  code index end
                  (cond
                    ((member lower
                             +simple-bash-built-ins+
                             :test #'string=)
                     "type")
                    ((member lower
                             +simple-bash-keywords+
                             :test #'string=)
                     "keyword")
                    (function-p "function")
                    (t nil))
                  theme output))
               (setf index end)))
            ((digit-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and (< end (length code))
                          (digit-char-p
                           (char code end)))
                     do (incf end))
               (write-simple-syntax-range
                code index end "number"
                theme output)
               (setf index end)))
            (t
             (write-char character output)
             (incf index))))))

(defparameter +simple-sql-keywords+
  '("all" "alter" "and" "as" "asc" "between"
    "by" "case" "create" "delete" "desc"
    "distinct" "drop" "else" "end" "exists"
    "from" "full" "group" "having" "in"
    "inner" "insert" "into" "is" "join"
    "left" "like" "limit" "not" "null"
    "offset" "on" "or" "order" "outer"
    "right" "select" "set" "table" "then"
    "union" "update" "values" "when" "where"))

(defun simple-syntax-highlight-sql
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          for character = (char code index)
          do
          (cond
            ((and
              (< (1+ index) (length code))
              (char= character #\-)
              (char= (char code (1+ index)) #\-))
             (let ((end
                     (or (position #\Newline code
                                   :start (+ index 2))
                         (length code))))
               (write-simple-syntax-range
                code index end "comment"
                theme output)
               (setf index end)))
            ((member character '(#\' #\"))
             (let ((end
                     (simple-syntax-quoted-end
                      code index)))
               (write-simple-syntax-range
                code index end "string"
                theme output)
               (setf index end)))
            ((alpha-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (alphanumericp (char code end))
                       (char= (char code end) #\_)))
                     do (incf end))
               (write-simple-syntax-range
                code index end
                (and
                 (member
                  (string-downcase
                   (subseq code index end))
                  +simple-sql-keywords+
                  :test #'string=)
                 "keyword")
                theme output)
               (setf index end)))
            ((digit-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (digit-char-p (char code end))
                       (char= (char code end) #\.)))
                     do (incf end))
               (write-simple-syntax-range
                code index end "number"
                theme output)
               (setf index end)))
            ((member character
                     '(#\= #\< #\> #\! #\+ #\-
                       #\* #\/ #\%))
             (let ((end (1+ index)))
               (when
                   (and
                    (< end (length code))
                    (member (char code end)
                            '(#\= #\> #\<)))
                 (incf end))
               (write-simple-syntax-range
                code index end "operator"
                theme output)
               (setf index end)))
            (t
             (write-char character output)
             (incf index))))))

(defun simple-syntax-regexp-start-p
    (code index)
  (let ((previous
          (loop for cursor downfrom (1- index) to 0
                for character = (char code cursor)
                unless
                (member character
                        '(#\Space #\Tab #\Newline
                          #\Return))
                  return character)))
    (or (null previous)
        (member previous
                '(#\= #\( #\[ #\{ #\, #\:
                  #\; #\! #\? #\& #\|)))))

(defun simple-syntax-regexp-end
    (code start)
  (let ((index (1+ start))
        (escaped-p nil)
        (class-p nil))
    (loop while (< index (length code))
          for character = (char code index)
          do
          (cond
            (escaped-p
             (setf escaped-p nil))
            ((char= character #\\)
             (setf escaped-p t))
            ((char= character #\[)
             (setf class-p t))
            ((and class-p
                  (char= character #\]))
             (setf class-p nil))
            ((and (not class-p)
                  (char= character #\/))
             (incf index)
             (loop while
                   (and (< index (length code))
                        (alpha-char-p
                         (char code index)))
                   do (incf index))
             (return index)))
          (incf index)
          finally (return nil))))

(defun simple-syntax-identifier-start-p
    (character)
  (or (alpha-char-p character)
      (member character '(#\_ #\$))))

(defun simple-syntax-identifier-part-p
    (character)
  (or (alphanumericp character)
      (member character '(#\_ #\$))))

(defun simple-syntax-next-character
    (code start)
  (loop for index from start below (length code)
        for character = (char code index)
        unless
        (member character
                '(#\Space #\Tab #\Newline
                  #\Return))
          return character))

(defun simple-syntax-line-comment-length
    (code index language)
  (let ((remaining (- (length code) index)))
    (cond
      ((and
        (member language
                '("c" "cpp" "go" "java"
                  "javascript" "typescript"
                  "rust")
                :test #'string=)
        (>= remaining 2)
            (string= "//" code
                     :start2 index
                     :end2 (+ index 2)))
       2)
      ((and
        (member language '("sql")
                :test #'string=)
        (>= remaining 2)
        (string= "--" code
                 :start2 index
                 :end2 (+ index 2)))
       2)
      ((and
        (member language
                '("bash" "python" "ruby"
                  "yaml")
                :test #'string=)
        (char= (char code index) #\#))
       1)
      ((and
        (string= language "lisp")
        (char= (char code index) #\;))
       1)
      (t nil))))

(defun simple-syntax-word-scope
    (word next-character previous-word
     parameter-depth expect-type-p)
  (let ((lower (string-downcase word)))
    (cond
      ((member lower +simple-syntax-keywords+
               :test #'string=)
       "keyword")
      ((member previous-word
               '("class" "enum" "interface"
                 "struct" "trait")
               :test #'string=)
       "function")
      ((or
        (member lower +simple-syntax-types+
                :test #'string=)
        expect-type-p
        (member previous-word
                '("extends" "implements" "new"
                  "type")
                :test #'string=))
       "type")
      ((and next-character
            (char= next-character #\())
       "function")
      ((plusp parameter-depth)
       "variable")
      (t nil))))

(defun simple-syntax-highlight
    (code language &optional theme)
  (unless
      (and (stringp language)
           (supports-syntax-language-p language))
    (return-from simple-syntax-highlight code))
  (let ((language (string-downcase language)))
    (cond
      ((string= language "diff")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-diff
          code theme)))
      ((member language '("html" "xml")
               :test #'string=)
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-markup
          code theme)))
      ((string= language "json")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-json
          code theme)))
      ((string= language "bash")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-bash
          code theme)))
      ((string= language "sql")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-sql
          code theme)))))
  (let ((language (string-downcase language))
        (index 0)
        (previous-word nil)
        (parameter-depth 0)
        (pending-function-p nil)
        (expect-type-p nil))
    (with-output-to-string (output)
      (labels
          ((emit (start end &optional scope)
             (let* ((text (subseq code start end))
                    (formatter
                      (and scope
                           (simple-syntax-formatter
                            scope theme))))
               (write-string
                (if formatter
                    (funcall formatter text)
                    text)
                output))))
        (loop while (< index (length code))
              for character = (char code index)
              for comment-length =
              (simple-syntax-line-comment-length
               code index language)
              do
              (cond
                (comment-length
                 (let ((end
                         (or
                          (position #\Newline code
                                    :start
                                    (+ index comment-length))
                          (length code))))
                   (emit index end "comment")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((and
                  (member language
                          '("c" "cpp" "css" "go"
                            "java" "javascript"
                            "typescript" "rust")
                          :test #'string=)
                  (<= (+ index 2) (length code))
                  (string= "/*" code
                           :start2 index
                           :end2 (+ index 2)))
                 (let* ((close
                          (search "*/" code
                                  :start2 (+ index 2)))
                        (end
                          (if close
                              (+ close 2)
                              (length code))))
                   (emit index end "comment")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((and
                  (member language
                          '("javascript" "typescript")
                          :test #'string=)
                  (char= character #\/)
                  (simple-syntax-regexp-start-p
                   code index)
                  (simple-syntax-regexp-end
                   code index))
                 (let ((end
                         (simple-syntax-regexp-end
                          code index)))
                   (emit index end "string")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((and
                  (string= language "python")
                  (char= character #\@))
                 (let ((end (1+ index)))
                   (loop while
                         (and
                          (< end (length code))
                          (not
                           (member
                            (char code end)
                            '(#\Space #\Tab
                              #\Newline #\Return))))
                         do (incf end))
                   (emit index end "meta")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((member character
                         '(#\" #\' #\`))
                 (let ((quote character)
                       (end (1+ index))
                       (escaped-p nil))
                   (loop while (< end (length code))
                         for current = (char code end)
                         do
                         (cond
                           (escaped-p
                            (setf escaped-p nil))
                           ((char= current #\\)
                            (setf escaped-p t))
                           ((char= current quote)
                            (incf end)
                            (return)))
                         (incf end))
                   (emit index end "string")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((simple-syntax-identifier-start-p
                  character)
                 (let ((end (1+ index)))
                   (loop while
                         (and
                          (< end (length code))
                          (simple-syntax-identifier-part-p
                           (char code end)))
                         do (incf end))
                   (let* ((word (subseq code index end))
                          (lower
                            (string-downcase word))
                          (scope
                            (simple-syntax-word-scope
                             word
                             (simple-syntax-next-character
                              code end)
                             previous-word
                             parameter-depth
                             expect-type-p)))
                     (emit index end scope)
                     (setf
                      pending-function-p
                      (and
                       scope
                       (string= scope "function")
                       (eql
                        (simple-syntax-next-character
                         code end)
                        #\())
                      expect-type-p nil)
                     (setf previous-word lower
                           index end))))
                ((digit-char-p character)
                 (let ((end (1+ index)))
                   (loop while
                         (and
                          (< end (length code))
                          (or
                           (digit-char-p
                            (char code end))
                           (member
                            (char code end)
                            '(#\. #\_))))
                         do (incf end))
                   (emit index end "number")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((char= character #\()
                 (if
                     (or pending-function-p
                         (plusp parameter-depth))
                     (progn
                       (emit index (1+ index)
                             "function")
                       (incf parameter-depth))
                     (write-char character output))
                 (setf pending-function-p nil)
                 (setf previous-word nil)
                 (incf index))
                ((and
                  (plusp parameter-depth)
                  (char= character #\)))
                 (emit index (1+ index) "function")
                 (decf parameter-depth)
                 (setf expect-type-p nil
                       previous-word nil)
                 (incf index))
                ((and
                  (plusp parameter-depth)
                  (char= character #\:))
                 (emit index (1+ index) "variable")
                 (setf expect-type-p t
                       previous-word nil)
                 (incf index))
                ((and
                  expect-type-p
                  (member character '(#\Space #\Tab)))
                 (emit index (1+ index) "variable")
                 (incf index))
                (t
                 (write-char character output)
                 (unless
                     (member character
                             '(#\Space #\Tab))
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil))
                 (incf index))))))))

(defun tree-entry-visible-p
    (entry filter)
  (case filter
    (:all t)
    (:messages
     (eq (getf entry :type)
         :message))
    (:user
     (and
      (eq (getf entry :type)
          :message)
      (eq (getf entry :role)
          :user)))
    (:labeled
     (not (null (getf entry :label))))
    (otherwise t)))

(defun nearest-visible-tree-entry
    (entries entry-id filter)
  (let ((by-id
          (make-hash-table :test #'equal))
        (current entry-id))
    (dolist (entry entries)
      (setf
       (gethash (getf entry :id)
                by-id)
       entry))
    (loop while current
          for entry = (gethash current by-id)
          while entry
          when (tree-entry-visible-p entry filter)
            return entry
          do (setf current
                   (getf entry :parent-id)))))

(defstruct tree-selection
  (filter :messages :type symbol)
  selected-id
  preserved-id)

(defun switch-tree-selection-filter
    (selection entries filter)
  (let* ((current
           (or
            (tree-selection-selected-id
             selection)
            (tree-selection-preserved-id
             selection)))
         (nearest
           (nearest-visible-tree-entry
            entries current filter)))
    (if nearest
        (setf
         (tree-selection-selected-id selection)
         (getf nearest :id)
         (tree-selection-preserved-id selection)
         nil)
        (setf
         (tree-selection-preserved-id selection)
         current
         (tree-selection-selected-id selection)
         nil))
    (setf (tree-selection-filter selection)
          filter)
    selection))

(defparameter +tree-selector-keybinding-definitions+
  (list
   (cons
    "app.tree.foldOrUp"
    #+darwin '("alt+left" "ctrl+left")
    #-darwin '("ctrl+left" "alt+left"))
   (cons
    "app.tree.unfoldOrDown"
    #+darwin '("alt+right" "ctrl+right")
    #-darwin '("ctrl+right" "alt+right"))
   '("app.message.copy" . ("ctrl+x"))
   '("app.tree.editLabel" . ("shift+l"))
   '("app.tree.toggleLabelTimestamp"
     . ("shift+t"))
   '("app.tree.filter.default" . ("ctrl+d"))
   '("app.tree.filter.noTools" . ("ctrl+t"))
   '("app.tree.filter.userOnly" . ("ctrl+u"))
   '("app.tree.filter.labeledOnly" . ("ctrl+l"))
   '("app.tree.filter.all" . ("ctrl+a"))
   '("app.tree.filter.cycleForward" . ("ctrl+o"))
   '("app.tree.filter.cycleBackward"
     . ("shift+ctrl+o"))))

(defun make-tree-selector-keybindings
    (&optional user-bindings)
  (cadr-tui:make-keybindings-manager
   :definitions
   +tree-selector-keybinding-definitions+
   :user-bindings user-bindings))

(defstruct (tree-selector-state
            (:constructor %make-tree-selector-state))
  (entries nil :type list)
  (ordered-entries nil :type list)
  current-leaf-id
  (filter :default :type symbol)
  (query "" :type string)
  selected-id
  preserved-id
  (visible-ids nil :type list)
  (visible-parent
   (make-hash-table :test #'equal)
   :type hash-table)
  (visible-children
   (make-hash-table :test #'equal)
   :type hash-table)
  (folded
   (make-hash-table :test #'equal)
   :type hash-table)
  (show-label-timestamps-p nil :type boolean)
  (max-visible-lines 10 :type (integer 1 *))
  (mode :list :type symbol)
  label-edit-id
  (label-input "" :type string)
  keybindings
  copy-callback
  select-callback
  cancel-callback
  label-callback)

(defun tree-selector-entry-map (entries)
  (let ((result
          (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (setf
       (gethash (getf entry :id)
                result)
       entry))
    result))

(defun tree-selector-active-path
    (entries current-leaf-id)
  (let ((by-id
          (tree-selector-entry-map entries))
        (result
          (make-hash-table :test #'equal))
        (current current-leaf-id))
    (loop while current
          for entry = (gethash current by-id)
          while entry
          do
             (setf (gethash current result) t
                   current
                   (getf entry :parent-id)))
    result))

(defun tree-selector-prioritize-active
    (entries active-path)
  (append
   (remove-if-not
    (lambda (entry)
      (gethash (getf entry :id)
               active-path))
    entries)
   (remove-if
    (lambda (entry)
      (gethash (getf entry :id)
               active-path))
    entries)))

(defun tree-selector-order-entries
    (entries current-leaf-id)
  (let ((children
          (make-hash-table :test #'equal))
        (known
          (tree-selector-entry-map entries))
        (active-path
          (tree-selector-active-path
           entries current-leaf-id))
        (roots nil)
        (result nil))
    (dolist (entry entries)
      (let ((parent-id
              (getf entry :parent-id)))
        (if (and parent-id
                 (gethash parent-id known))
            (setf
             (gethash parent-id children)
             (nconc
              (gethash parent-id children)
              (list entry)))
            (setf roots
                  (nconc roots (list entry))))))
    (let ((stack
            (tree-selector-prioritize-active
             roots active-path)))
      (loop while stack
            for entry = (pop stack)
            do
               (push entry result)
               (dolist
                   (child
                    (reverse
                     (tree-selector-prioritize-active
                      (gethash
                       (getf entry :id)
                       children)
                      active-path)))
                 (push child stack))))
    (nreverse result)))

(defun tree-selector-settings-entry-p (entry)
  (member
   (getf entry :type)
   '(:label :custom :model-change
     :thinking-level-change :session-info)
   :test #'eq))

(defun tree-selector-entry-filtered-p
    (entry filter current-leaf-id)
  (and
   (not
    (and
     (eq (getf entry :type) :message)
     (eq (getf entry :role) :assistant)
     (getf entry :tool-call-only-p)
     (not (getf entry :error-p))
     (not
      (equal (getf entry :id)
             current-leaf-id))))
   (case filter
     (:user-only
      (and
       (eq (getf entry :type) :message)
       (eq (getf entry :role) :user)))
     (:no-tools
      (and
       (not
        (tree-selector-settings-entry-p entry))
       (not
        (and
         (eq (getf entry :type) :message)
         (member
          (getf entry :role)
          '(:tool-result :toolresult)
          :test #'eq)))))
     (:labeled-only
      (not (null (getf entry :label))))
     (:all t)
     (otherwise
      (not
       (tree-selector-settings-entry-p entry))))))

(defun tree-selector-entry-search-text (entry)
  (format
   nil "~{~A~^ ~}"
   (remove
    nil
    (list
     (getf entry :label)
     (getf entry :role)
     (getf entry :text)
     (getf entry :summary)
     (getf entry :name)
     (getf entry :model-id)
     (getf entry :thinking-level)
     (getf entry :custom-type)))))

(defun tree-selector-query-matches-p
    (entry query)
  (let ((haystack
          (string-downcase
           (tree-selector-entry-search-text
            entry))))
    (every
     (lambda (token)
       (search
        (string-downcase token)
        haystack))
     (remove
      ""
      (cl-ppcre:split "\\s+" query)
      :test #'string=))))

(defun tree-selector-nearest-visible-id
    (state target visible-set)
  (let ((by-id
          (tree-selector-entry-map
           (tree-selector-state-entries state)))
        (current target))
    (loop while current
          for entry = (gethash current by-id)
          when (gethash current visible-set)
            return current
          while entry
          do (setf current
                   (getf entry :parent-id))
          finally
             (return
               (car
                (last
                 (tree-selector-state-visible-ids
                  state)))))))

(defun tree-selector-rebuild-visible-maps
    (state entries)
  (let ((visible-set
          (make-hash-table :test #'equal))
        (parent-map
          (make-hash-table :test #'equal))
        (children-map
          (make-hash-table :test #'equal))
        (by-id
          (tree-selector-entry-map
           (tree-selector-state-entries state))))
    (dolist (entry entries)
      (setf
       (gethash (getf entry :id)
                visible-set)
       t))
    (dolist (entry entries)
      (let ((parent
              (getf entry :parent-id)))
        (loop while
              (and parent
                   (not
                    (gethash parent
                             visible-set)))
              for parent-entry =
                (gethash parent by-id)
              do
                 (setf parent
                       (and parent-entry
                            (getf
                             parent-entry
                             :parent-id))))
        (setf
         (gethash (getf entry :id)
                  parent-map)
         parent
         (gethash parent children-map)
         (nconc
          (gethash parent children-map)
          (list (getf entry :id))))))
    (setf
     (tree-selector-state-visible-parent
      state)
     parent-map
     (tree-selector-state-visible-children
      state)
     children-map)
    visible-set))

(defun tree-selector-apply-filter (state)
  (let* ((target
           (or
            (tree-selector-state-selected-id state)
            (tree-selector-state-preserved-id state)))
         (skip
           (make-hash-table :test #'equal))
         (visible
           (loop
             for entry in
               (tree-selector-state-ordered-entries
                state)
             for id = (getf entry :id)
             for parent-id = (getf entry :parent-id)
             when
               (and
                parent-id
                (or
                 (gethash
                  parent-id
                  (tree-selector-state-folded
                   state))
                 (gethash parent-id skip)))
               do (setf (gethash id skip) t)
             when
               (and
                (not (gethash id skip))
                (tree-selector-entry-filtered-p
                 entry
                 (tree-selector-state-filter state)
                 (tree-selector-state-current-leaf-id
                  state))
                (tree-selector-query-matches-p
                 entry
                 (tree-selector-state-query state)))
               collect entry)))
    (setf
     (tree-selector-state-visible-ids state)
     (mapcar
      (lambda (entry)
        (getf entry :id))
      visible))
    (let* ((visible-set
             (tree-selector-rebuild-visible-maps
              state visible))
           (nearest
             (tree-selector-nearest-visible-id
              state target visible-set)))
      (if nearest
          (setf
           (tree-selector-state-selected-id
            state)
           nearest
           (tree-selector-state-preserved-id
            state)
           nil)
          (setf
           (tree-selector-state-preserved-id
            state)
           target
           (tree-selector-state-selected-id
            state)
           nil))))
  state)

(defun make-tree-selector-state
    (&key entries current-leaf-id
       initial-selected-id
       (filter :default)
       (max-visible-lines 10)
       copy-callback select-callback
       cancel-callback label-callback
       keybindings)
  (let ((state
          (%make-tree-selector-state
           :entries entries
           :ordered-entries
           (tree-selector-order-entries
            entries current-leaf-id)
           :current-leaf-id current-leaf-id
           :filter filter
           :max-visible-lines
           (max 1 max-visible-lines)
           :selected-id
           (or initial-selected-id
               current-leaf-id)
           :keybindings
           (or keybindings
               (make-tree-selector-keybindings))
           :copy-callback copy-callback
           :select-callback select-callback
           :cancel-callback cancel-callback
           :label-callback label-callback)))
    (tree-selector-apply-filter state)))

(defun tree-selector-selected-id (state)
  (tree-selector-state-selected-id state))

(defun tree-selector-visible-ids (state)
  (copy-list
   (tree-selector-state-visible-ids state)))

(defun tree-selector-select-id (state id)
  (when
      (member
       id
       (tree-selector-state-visible-ids state)
       :test #'equal)
    (setf
     (tree-selector-state-selected-id state)
     id
     (tree-selector-state-preserved-id state)
     nil))
  state)

(defun tree-selector-set-filter (state filter)
  (clrhash
   (tree-selector-state-folded state))
  (setf
   (tree-selector-state-filter state)
   filter)
  (tree-selector-apply-filter state))

(defparameter +tree-selector-filter-modes+
  '(:default :no-tools :user-only
    :labeled-only :all))

(defun tree-selector-cycle-filter
    (state direction)
  (let* ((modes
           +tree-selector-filter-modes+)
         (index
           (or
            (position
             (tree-selector-state-filter state)
             modes)
            0)))
    (tree-selector-set-filter
     state
     (nth
      (mod (+ index direction)
           (length modes))
      modes))))

(defun tree-selector-set-query (state query)
  (clrhash
   (tree-selector-state-folded state))
  (setf
   (tree-selector-state-query state)
   (or query ""))
  (tree-selector-apply-filter state))

(defun tree-selector-move (state delta)
  (let* ((ids
           (tree-selector-state-visible-ids
            state))
         (length (length ids)))
    (when (plusp length)
      (let* ((current
               (or
                (position
                 (tree-selector-state-selected-id
                  state)
                 ids :test #'equal)
                0))
             (next
               (mod (+ current delta)
                    length)))
        (setf
         (tree-selector-state-selected-id
          state)
         (nth next ids)
         (tree-selector-state-preserved-id
          state)
         nil))))
  state)

(defun tree-selector-foldable-p (state id)
  (let* ((children
           (gethash
            id
            (tree-selector-state-visible-children
             state)))
         (parent
           (gethash
            id
            (tree-selector-state-visible-parent
             state)))
         (siblings
           (gethash
            parent
            (tree-selector-state-visible-children
             state))))
    (and children
         (or (null parent)
             (> (length siblings) 1)))))

(defun tree-selector-branch-segment-id
    (state direction)
  (let* ((selected
           (tree-selector-state-selected-id
            state))
         (ids
           (tree-selector-state-visible-ids
            state))
         (index
           (position selected ids :test #'equal))
         (current selected))
    (unless current
      (return-from
          tree-selector-branch-segment-id
        nil))
    (ecase direction
      (:down
       (loop
         for children =
           (gethash
            current
            (tree-selector-state-visible-children
             state))
         do
            (cond
              ((null children)
               (return current))
              ((cdr children)
               (return (car children)))
              (t
               (setf current
                     (car children))))))
      (:up
       (loop
         for parent =
           (gethash
            current
            (tree-selector-state-visible-parent
             state))
         do
            (when (null parent)
              (return current))
            (let ((siblings
                    (gethash
                     parent
                     (tree-selector-state-visible-children
                      state))))
              (when
                  (and
                   (cdr siblings)
                   (<
                    (or
                     (position current
                               ids :test #'equal)
                     index)
                    index))
                (return current)))
            (setf current parent))))))

(defun tree-selector-fold-or-up (state)
  (let ((id
          (tree-selector-state-selected-id
           state)))
    (if
        (and
         id
         (tree-selector-foldable-p state id)
         (not
          (gethash
           id
           (tree-selector-state-folded state))))
        (progn
          (setf
           (gethash
            id
            (tree-selector-state-folded state))
           t)
          (tree-selector-apply-filter state))
        (tree-selector-select-id
         state
         (tree-selector-branch-segment-id
          state :up))))
  state)

(defun tree-selector-unfold-or-down (state)
  (let ((id
          (tree-selector-state-selected-id
           state)))
    (if
        (and
         id
         (gethash
          id
          (tree-selector-state-folded state)))
        (progn
          (remhash
           id
           (tree-selector-state-folded state))
          (tree-selector-apply-filter state))
        (tree-selector-select-id
         state
         (tree-selector-branch-segment-id
          state :down))))
  state)

(defun tree-selector-selected-entry (state)
  (find
   (tree-selector-state-selected-id state)
   (tree-selector-state-entries state)
   :key
   (lambda (entry)
     (getf entry :id))
   :test #'equal))

(defun tree-selector-copy-selected (state)
  (when (tree-selector-state-copy-callback state)
    (funcall
     (tree-selector-state-copy-callback state)
     (let ((entry
             (tree-selector-selected-entry
              state)))
       (and entry
            (getf entry :text)))))
  state)

(defun tree-selector-toggle-label-timestamps
    (state)
  (setf
   (tree-selector-state-show-label-timestamps-p
    state)
   (not
    (tree-selector-state-show-label-timestamps-p
     state)))
  state)

(defun tree-selector-iso-timestamp
    (&optional (universal-time
                 (get-universal-time)))
  (multiple-value-bind
        (second minute hour day month year)
      (decode-universal-time universal-time)
    (format
     nil
     "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D"
     year month day hour minute second)))

(defun tree-selector-start-label-edit (state)
  (let ((entry
          (tree-selector-selected-entry state)))
    (when entry
      (setf
       (tree-selector-state-mode state) :label
       (tree-selector-state-label-edit-id state)
       (getf entry :id)
       (tree-selector-state-label-input state)
       (or (getf entry :label) ""))))
  state)

(defun tree-selector-confirm-label (state)
  (let* ((id
           (tree-selector-state-label-edit-id
            state))
         (input
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            (tree-selector-state-label-input
             state)))
         (label
           (and (plusp (length input))
                input)))
    (when
        (and id
             (tree-selector-state-label-callback
              state))
      (funcall
       (tree-selector-state-label-callback state)
       id label))
    (let ((entry
            (find
             id
             (tree-selector-state-entries state)
             :key
             (lambda (candidate)
               (getf candidate :id))
             :test #'equal)))
      (when entry
        (setf
         (getf entry :label)
         label
         (getf entry :label-timestamp)
         (and label
              (tree-selector-iso-timestamp)))))
    (setf
     (tree-selector-state-mode state) :list
     (tree-selector-state-label-edit-id state)
     nil
     (tree-selector-state-label-input state)
     "")
    (tree-selector-apply-filter state)))

(defun tree-selector-cancel-label (state)
  (setf
   (tree-selector-state-mode state) :list
   (tree-selector-state-label-edit-id state)
   nil
   (tree-selector-state-label-input state)
   "")
  state)

(defun tree-selector-app-key-p
    (state data name)
  (selector-keybinding-matches-p
   (tree-selector-state-keybindings state)
   data name))

(defun tree-selector-handle-raw-input
    (state data)
  (when (eq :label
            (tree-selector-state-mode state))
    (return-from tree-selector-handle-raw-input
      (values nil nil nil)))
  (labels
      ((changed (thunk)
         (funcall thunk)
         (values :changed nil t))
       (toggle (mode)
         (tree-selector-set-filter
          state
          (if
              (eq mode
                  (tree-selector-state-filter
                   state))
              :default
              mode))))
    (cond
      ((tree-selector-app-key-p
        state data "app.tree.foldOrUp")
       (changed
        (lambda ()
          (tree-selector-fold-or-up state))))
      ((tree-selector-app-key-p
        state data "app.tree.unfoldOrDown")
       (changed
        (lambda ()
          (tree-selector-unfold-or-down state))))
      ((tree-selector-app-key-p
        state data "app.message.copy")
       (changed
        (lambda ()
          (tree-selector-copy-selected state))))
      ((tree-selector-app-key-p
        state data "app.tree.editLabel")
       (changed
        (lambda ()
          (tree-selector-start-label-edit
           state))))
      ((tree-selector-app-key-p
        state data
        "app.tree.toggleLabelTimestamp")
       (changed
        (lambda ()
          (tree-selector-toggle-label-timestamps
           state))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.default")
       (changed
        (lambda ()
          (tree-selector-set-filter
           state :default))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.noTools")
       (changed
        (lambda () (toggle :no-tools))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.userOnly")
       (changed
        (lambda () (toggle :user-only))))
      ((tree-selector-app-key-p
        state data
        "app.tree.filter.labeledOnly")
       (changed
        (lambda () (toggle :labeled-only))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.all")
       (changed
        (lambda () (toggle :all))))
      ((tree-selector-app-key-p
        state data
        "app.tree.filter.cycleForward")
       (changed
        (lambda ()
          (tree-selector-cycle-filter state 1))))
      ((tree-selector-app-key-p
        state data
        "app.tree.filter.cycleBackward")
       (changed
        (lambda ()
          (tree-selector-cycle-filter state -1))))
      (t
       (values nil nil nil)))))

(defun tree-selector-handle-label-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:escape
     (tree-selector-cancel-label state)
     (values :changed nil))
    (:enter
     (tree-selector-confirm-label state)
     (values :changed nil))
    (:backspace
     (let ((input
             (tree-selector-state-label-input
              state)))
       (when (plusp (length input))
         (setf
          (tree-selector-state-label-input state)
          (subseq
           input 0
           (cadr-tui::previous-cluster-boundary
            input (length input))))))
     (values :changed nil))
    (:text
     (setf
      (tree-selector-state-label-input state)
      (concatenate
       'string
       (tree-selector-state-label-input state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun tree-selector-handle-event
    (state event)
  (when (eq :label
            (tree-selector-state-mode state))
    (return-from tree-selector-handle-event
      (tree-selector-handle-label-event
       state event)))
  (case (cadr-tui:input-event-kind event)
    (:up
     (tree-selector-move state -1)
     (values :changed nil))
    (:down
     (tree-selector-move state 1)
     (values :changed nil))
    (:page-up
     (tree-selector-move state -10)
     (values :changed nil))
    (:page-down
     (tree-selector-move state 10)
     (values :changed nil))
    (:enter
     (let ((id
             (tree-selector-state-selected-id
              state)))
       (if id
           (values :select id)
           (values nil nil))))
    (:escape
     (if (plusp
          (length
           (tree-selector-state-query state)))
         (progn
           (tree-selector-set-query state "")
           (values :changed nil))
         (values :cancel nil)))
    (:backspace
     (let ((query
             (tree-selector-state-query state)))
       (when (plusp (length query))
         (tree-selector-set-query
          state
          (subseq
           query 0
           (cadr-tui::previous-cluster-boundary
            query (length query))))))
     (values :changed nil))
    (:text
     (tree-selector-set-query
      state
      (concatenate
       'string
       (tree-selector-state-query state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun tree-selector-format-label-timestamp
    (value &optional (now (get-universal-time))
                     display-timezone)
  (multiple-value-bind
        (match registers)
      (cl-ppcre:scan-to-strings
       "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.\\d+)?)?(Z|[+-]\\d{2}:?\\d{2})?$"
       (or value ""))
    (declare (ignore match))
    (if registers
        (handler-case
            (let* ((year (parse-integer (aref registers 0)))
                   (month (parse-integer (aref registers 1)))
                   (day (parse-integer (aref registers 2)))
                   (hour (parse-integer (aref registers 3)))
                   (minute (parse-integer (aref registers 4)))
                   (second
                     (if (aref registers 5)
                         (parse-integer (aref registers 5))
                         0))
                   (zone (aref registers 6))
                   (source-timezone
                     (cond
                       ((null zone) display-timezone)
                       ((string= zone "Z") 0)
                       (t
                        (let* ((east-p (char= (char zone 0) #\+))
                               (offset-hours
                                 (parse-integer zone :start 1 :end 3))
                               (offset-minutes
                                 (parse-integer
                                  zone :start
                                  (if (char= (char zone 3) #\:)
                                      4 3)))
                               (offset
                                 (+ offset-hours
                                    (/ offset-minutes 60))))
                          (if east-p (- offset) offset)))))
                   (timestamp
                     (if source-timezone
                         (encode-universal-time
                          second minute hour day month year
                          source-timezone)
                         (encode-universal-time
                          second minute hour day month year))))
              (multiple-value-bind
                    (shown-second shown-minute shown-hour shown-day
                     shown-month shown-year)
                  (if display-timezone
                      (decode-universal-time
                       timestamp display-timezone)
                      (decode-universal-time timestamp))
                (declare (ignore shown-second))
                (multiple-value-bind
                      (now-second now-minute now-hour now-day
                       now-month now-year)
                    (if display-timezone
                        (decode-universal-time now display-timezone)
                        (decode-universal-time now))
                  (declare
                   (ignore now-second now-minute now-hour))
                  (let ((time
                          (format nil "~2,'0D:~2,'0D"
                                  shown-hour shown-minute)))
                    (cond
                      ((and (= shown-year now-year)
                            (= shown-month now-month)
                            (= shown-day now-day))
                       time)
                      ((= shown-year now-year)
                       (format nil "~D/~D ~A"
                               shown-month shown-day time))
                      (t
                       (format nil "~2,'0D/~D/~D ~A"
                               (mod shown-year 100)
                               shown-month shown-day time)))))))
          (error () (or value "")))
        (or value ""))))

(defun tree-selector-status-labels (state)
  (format
   nil "~@[ [~A]~]~@[ [+label time]~]"
   (case
       (tree-selector-state-filter state)
     (:no-tools "no-tools")
     (:user-only "user")
     (:labeled-only "labeled")
     (:all "all")
     (otherwise nil))
   (tree-selector-state-show-label-timestamps-p
    state)))

(defun tree-selector-visual-nodes (state)
  (let* ((children
           (tree-selector-state-visible-children state))
         (roots (copy-list (gethash nil children)))
         (multiple-roots-p (> (length roots) 1))
         (visuals (make-hash-table :test #'equal))
         (stack nil))
    (loop for id in (reverse roots)
          for index downfrom (1- (length roots))
          do
          (push
           (list id
                 (if multiple-roots-p 1 0)
                 multiple-roots-p
                 multiple-roots-p
                 (= index (1- (length roots)))
                 nil
                 multiple-roots-p)
           stack))
    (loop while stack
          for item = (pop stack)
          for id = (first item)
          for indent = (second item)
          for just-branched-p = (third item)
          for show-connector-p = (fourth item)
          for last-p = (fifth item)
          for gutters = (sixth item)
          for virtual-root-child-p = (seventh item)
          for node-children = (copy-list
                               (gethash id children))
          for multiple-children-p =
            (> (length node-children) 1)
          do
          (setf
           (gethash id visuals)
           (list
            :indent indent
            :show-connector-p show-connector-p
            :last-p last-p
            :gutters gutters
            :virtual-root-child-p
            virtual-root-child-p))
          (let* ((child-indent
                   (cond
                     (multiple-children-p (1+ indent))
                     ((and just-branched-p
                           (plusp indent))
                      (1+ indent))
                     (t indent)))
                 (connector-displayed-p
                   (and show-connector-p
                        (not virtual-root-child-p)))
                 (display-indent
                   (if multiple-roots-p
                       (max 0 (1- indent))
                       indent))
                 (connector-position
                   (max 0 (1- display-indent)))
                 (child-gutters
                   (if connector-displayed-p
                       (append
                        gutters
                        (list
                         (cons connector-position
                               (not last-p))))
                       gutters)))
            (loop for child in (reverse node-children)
                  for index downfrom
                    (1- (length node-children))
                  do
                  (push
                   (list
                    child child-indent
                    multiple-children-p
                    multiple-children-p
                    (= index
                       (1- (length node-children)))
                    child-gutters nil)
                   stack))))
    (values visuals multiple-roots-p)))

(defun tree-selector-prefix
    (state id visual multiple-roots-p)
  (let* ((indent (getf visual :indent))
         (display-indent
           (if multiple-roots-p
               (max 0 (1- indent))
               indent))
         (show-connector-p
           (and (getf visual :show-connector-p)
                (not
                 (getf visual
                       :virtual-root-child-p))))
         (connector-position
           (and show-connector-p
                (1- display-indent)))
         (last-p (getf visual :last-p))
         (folded-p
           (gethash id
                    (tree-selector-state-folded state)))
         (foldable-p
           (tree-selector-foldable-p state id)))
    (with-output-to-string (output)
      (loop for level below display-indent
            for gutter =
              (assoc level (getf visual :gutters))
            do
            (cond
              (gutter
               (write-string
                (if (cdr gutter) "│  " "   ")
                output))
              ((and connector-position
                    (= level connector-position))
               (write-string
                (if last-p "└" "├") output)
               (write-string
                (cond
                  (folded-p "⊞")
                  (foldable-p "⊟")
                  (t "─"))
                output)
               (write-char #\Space output))
              (t
               (write-string "   " output)))))))

(defun tree-selector-normalize-display-text (text)
  (string-trim
   '(#\Space #\Tab #\Newline #\Return)
   (cl-ppcre:regex-replace-all
    "[\\n\\t]" (or text "") " ")))

(defun tree-selector-shorten-path (path)
  (let ((home (or (uiop:getenv "HOME") "")))
    (if
        (and
         (plusp (length home))
         (<= (length home) (length path))
         (string= home path :end2 (length home)))
        (concatenate
         'string "~" (subseq path (length home)))
        path)))

(defun tree-selector-tool-argument
    (arguments name &optional fallback)
  (or
   (and arguments
        (cadr-ai::json-get arguments name))
   (and fallback arguments
        (cadr-ai::json-get arguments fallback))))

(defun tree-selector-format-tool-call
    (name arguments)
  (cond
    ((string= name "read")
     (let* ((path
              (tree-selector-shorten-path
               (or
                (tree-selector-tool-argument
                 arguments "path" "file_path")
                "")))
            (offset-present-p
              (cadr-ai::json-present-p
               arguments "offset"))
            (limit-present-p
              (cadr-ai::json-present-p
               arguments "limit"))
            (offset
              (and offset-present-p
                   (cadr-ai::json-get
                    arguments "offset")))
            (limit
              (and limit-present-p
                   (cadr-ai::json-get
                    arguments "limit"))))
       (format
        nil "[read: ~A~A]"
        path
        (if (or offset-present-p limit-present-p)
            (let* ((start (or offset 1))
                   (end
                     (and limit
                          (+ start limit -1))))
              (format nil ":~A~@[-~A~]"
                      start end))
            ""))))
    ((member name '("write" "edit")
             :test #'string=)
     (format
      nil "[~A: ~A]" name
      (tree-selector-shorten-path
       (or
        (tree-selector-tool-argument
         arguments "path" "file_path")
        ""))))
    ((string= name "bash")
     (let* ((raw
              (or
               (tree-selector-tool-argument
                arguments "command")
               ""))
            (normalized
              (tree-selector-normalize-display-text
               raw))
            (command
              (subseq normalized 0
                      (min 50
                           (length normalized)))))
       (format nil "[bash: ~A~A]"
               command
               (if (> (length raw) 50)
                   "..." ""))))
    ((string= name "grep")
     (format
      nil "[grep: /~A/ in ~A]"
      (or
       (tree-selector-tool-argument
        arguments "pattern")
       "")
      (tree-selector-shorten-path
       (or
        (tree-selector-tool-argument
         arguments "path")
        "."))))
    ((string= name "find")
     (format
      nil "[find: ~A in ~A]"
      (or
       (tree-selector-tool-argument
        arguments "pattern")
       "")
      (tree-selector-shorten-path
       (or
        (tree-selector-tool-argument
         arguments "path")
        "."))))
    ((string= name "ls")
     (format
      nil "[ls: ~A]"
      (tree-selector-shorten-path
       (or
        (tree-selector-tool-argument
         arguments "path")
        "."))))
    (t
     (let* ((json
              (cadr-ai::stringify-json
               arguments))
            (short
              (subseq json 0
                      (min 40 (length json)))))
       (format nil "[~A: ~A~A]"
               name short
               (if (> (length json) 40)
                   "..." ""))))))

(defun tree-selector-entry-display-text
    (entry selected-p)
  (let* ((type (getf entry :type))
         (role (getf entry :role))
         (text
           (tree-selector-normalize-display-text
            (getf entry :text)))
         (result
           (case type
             (:message
              (case role
                (:user
                 (concatenate
                  'string
                  (cadr-tui:theme-foreground
                   :accent "user: ")
                  text))
                (:assistant
                 (concatenate
                  'string
                  (cadr-tui:theme-foreground
                   :success "assistant: ")
                  (if (plusp (length text))
                      text
                      (cadr-tui:theme-foreground
                       :muted
                       (if (getf entry :error-p)
                           "(aborted)"
                           "(no content)")))))
                ((:tool-result :toolresult)
                 (cadr-tui:theme-foreground
                  :muted
                  (let ((name
                          (getf entry
                                :tool-call-name))
                        (arguments
                          (getf entry
                                :tool-call-arguments)))
                    (if (and name arguments)
                        (tree-selector-format-tool-call
                         name arguments)
                        (format nil "[~A]"
                                (or name "tool"))))))
                (:bash-execution
                 (cadr-tui:theme-foreground
                  :dim
                  (format nil "[bash]: ~A" text)))
                (otherwise
                 (cadr-tui:theme-foreground
                  :dim
                  (format nil "[~(~A~)]" role)))))
             ((:custom-message :custom_message)
              (concatenate
               'string
               (cadr-tui:theme-foreground
                :custom-message-label
                (format nil "[~A]: "
                        (or (getf entry :custom-type)
                            "custom")))
               text))
             (:compaction
              (cadr-tui:theme-foreground
               :border-accent
               (if (plusp (length text))
                   (format nil "[compaction]: ~A" text)
                   "[compaction]")))
             (:branch-summary
              (concatenate
               'string
               (cadr-tui:theme-foreground
                :warning "[branch summary]: ")
               text))
             (:model-change
              (cadr-tui:theme-foreground
               :dim
               (format nil "[model: ~A]"
                       (or (getf entry :model-id)
                           text))))
             (:thinking-level-change
              (cadr-tui:theme-foreground
               :dim
               (format nil "[thinking: ~A]"
                       (or (getf entry :thinking-level)
                           text))))
             (:custom
              (cadr-tui:theme-foreground
               :dim
               (format nil "[custom: ~A]"
                       (or (getf entry :custom-type)
                           "custom"))))
             (:label
              (cadr-tui:theme-foreground
               :dim
               (format nil "[label: ~A]"
                       (or (getf entry :label)
                           "(cleared)"))))
             (:session-info
              (cadr-tui:theme-foreground
               :dim
               (format nil "[title: ~A]"
                       (or (getf entry :name)
                           "empty"))))
             (otherwise text))))
    (if selected-p
        (cadr-tui:theme-bold result)
        result)))

(defun tree-selector-horizontal-viewport
    (rows width)
  (let* ((gutter-width 2)
         (viewport-width
           (max 0 (- width gutter-width)))
         (maximum-body-width
           (loop for row in rows
                 maximize (getf row :body-width)
                   into maximum
                 finally (return (or maximum 0))))
         (maximum-scroll
           (max 0
                (- maximum-body-width
                   viewport-width)))
         (selected
           (find-if
            (lambda (row)
              (getf row :selected-p))
            rows))
         (scroll 0))
    (when (and selected
               (plusp maximum-scroll))
      (let ((minimum-content
              (min 20
                   (max 4
                        (floor viewport-width 3)))))
        (when
            (> (getf selected :anchor-column)
               (- viewport-width minimum-content))
          (let ((context
                  (min 12
                       (max 2
                            (floor viewport-width 4)))))
            (setf
             scroll
             (min maximum-scroll
                  (- (getf selected :anchor-column)
                     context)))))))
    (loop for row in rows
          collect
          (selector-fit-line
           (if (plusp scroll)
               (concatenate
                'string
                (getf row :gutter)
                (cadr-tui:slice-by-column
                 (getf row :body)
                 scroll viewport-width t)
                (format nil "~C[0m" #\Escape))
               (concatenate
                'string
                (getf row :gutter)
                (getf row :body)))
           width))))

(defun tree-selector-render-lines (state width)
  (let* ((by-id
           (tree-selector-entry-map
            (tree-selector-state-entries state)))
         (ids
           (tree-selector-state-visible-ids state))
         (selected
           (tree-selector-state-selected-id state))
         (selected-index
           (or (position selected ids :test #'equal)
               0))
         (active-path
           (tree-selector-active-path
            (tree-selector-state-entries state)
            (tree-selector-state-current-leaf-id
             state))))
    (multiple-value-bind
          (visible start end total)
        (centered-visible-slice
         ids selected-index
         (tree-selector-state-max-visible-lines
          state))
      (declare (ignore end))
      (multiple-value-bind
            (visuals multiple-roots-p)
          (tree-selector-visual-nodes state)
        (let ((rows
                (loop
                  for id in visible
                  for index from start
                  for entry = (gethash id by-id)
                  for visual = (gethash id visuals)
                  for selected-p = (= index selected-index)
                  for prefix =
                    (tree-selector-prefix
                     state id visual multiple-roots-p)
                  for root-fold-marker =
                    (and
                     (gethash
                      id
                      (tree-selector-state-folded state))
                     (not
                      (and
                       (getf visual :show-connector-p)
                       (not
                        (getf visual
                              :virtual-root-child-p))))
                     (cadr-tui:theme-foreground
                      :accent "⊞ "))
                  for path-marker =
                    (and
                     (gethash id active-path)
                     (cadr-tui:theme-foreground
                      :accent "• "))
                  for prefix-part =
                    (concatenate
                     'string
                     (cadr-tui:theme-foreground
                      :dim prefix)
                     (or root-fold-marker "")
                     (or path-marker ""))
                  for label = (getf entry :label)
                  for label-part =
                    (and label
                         (cadr-tui:theme-foreground
                          :warning
                          (format nil "[~A] " label)))
                  for timestamp-part =
                    (and
                     label
                     (tree-selector-state-show-label-timestamps-p
                      state)
                     (cadr-tui:theme-foreground
                      :muted
                      (format
                       nil "~A "
                       (tree-selector-format-label-timestamp
                        (getf entry :label-timestamp)))))
                  for cursor =
                    (if selected-p
                        (cadr-tui:theme-foreground
                         :accent "› ")
                        "  ")
                  for body =
                    (concatenate
                     'string prefix-part
                     (or label-part "")
                     (or timestamp-part "")
                     (tree-selector-entry-display-text
                      entry selected-p))
                  when selected-p
                    do
                    (setf
                     cursor
                     (cadr-tui:theme-background
                      :selected-bg cursor)
                     body
                     (cadr-tui:theme-background
                      :selected-bg body))
                  collect
                  (list
                   :gutter cursor
                   :body body
                   :anchor-column
                   (cadr-tui:visible-width prefix-part)
                   :body-width
                   (cadr-tui:visible-width body)
                   :selected-p selected-p))))
          (append
           (if rows
               (tree-selector-horizontal-viewport
                rows width)
               (list
                (selector-muted-line
                 "  No entries found" width)))
           (list
            (selector-muted-line
             (format
              nil "  (~D/~D)~A"
              (if selected
                  (1+ selected-index)
                  0)
              total
              (tree-selector-status-labels state))
             width))))))))

(defun tree-selector-help-key
    (state name)
  (or
   (first
    (cadr-tui:keybinding-keys
     (tree-selector-state-keybindings state)
     name))
   (cdr
    (assoc
     name
     '(("tui.select.up" . "up")
       ("tui.select.down" . "down")
       ("tui.editor.cursorLeft" . "left")
       ("tui.editor.cursorRight" . "right"))
     :test #'string=))))

(defun tree-selector-help-keys
    (state names)
  (let ((keys
          (remove
           nil
           (mapcar
            (lambda (name)
              (tree-selector-help-key state name))
            names))))
    (when keys
      (let* ((parts
               (mapcar
                (lambda (key)
                  (let ((separator
                          (position #\+ key
                                    :from-end t)))
                    (if separator
                        (cons
                         (subseq key 0 (1+ separator))
                         (subseq key (1+ separator)))
                        (cons "" key))))
                keys))
             (prefix (caar parts))
             (compact
               (if
                   (and
                    (string= prefix "ctrl+")
                    (every
                     (lambda (part)
                       (string= prefix (car part)))
                     parts))
                   (concatenate
                    'string prefix
                    (format nil "~{~A~^/~}"
                            (mapcar #'cdr parts)))
                   (format nil "~{~A~^/~}" keys))))
        (reduce
         (lambda (text replacement)
           (cl-ppcre:regex-replace-all
            (car replacement) text
            (cdr replacement)))
         '(("\\bup\\b" . "↑")
           ("\\bdown\\b" . "↓")
           ("\\bleft\\b" . "←")
           ("\\bright\\b" . "→"))
         :initial-value compact)))))

(defun tree-selector-help-lines (state width)
  (let* ((items
           (mapcar
            (lambda (entry)
              (let ((keys
                      (tree-selector-help-keys
                       state (first entry))))
                (if (getf (cddr entry) :label-first)
                    (format nil "~A ~A"
                            (second entry) keys)
                    (format nil "~A ~A"
                            keys (second entry)))))
            '((("tui.select.up" "tui.select.down")
               "move")
              (("tui.editor.cursorLeft"
                "tui.editor.cursorRight")
               "page")
              (("app.tree.foldOrUp"
                "app.tree.unfoldOrDown")
               "branch")
              (("app.message.copy") "copy")
              (("app.tree.editLabel") "label")
              (("app.tree.toggleLabelTimestamp")
               "label time")
              (("app.tree.filter.default"
                "app.tree.filter.noTools"
                "app.tree.filter.userOnly"
                "app.tree.filter.labeledOnly"
                "app.tree.filter.all")
               "filters" :label-first t)
              (("app.tree.filter.cycleForward"
                "app.tree.filter.cycleBackward")
               "cycle" :label-first t))))
         (lines nil)
         (current ""))
    (dolist (item items)
      (let* ((indented
               (concatenate 'string "  " item))
             (candidate
               (if (zerop (length current))
                   (if
                       (<= (cadr-tui:visible-width indented)
                           width)
                       indented item)
                   (concatenate
                    'string current " · " item))))
        (if
            (or (zerop (length current))
                (<= (cadr-tui:visible-width candidate)
                    width))
            (setf current candidate)
            (progn
              (setf lines
                    (nconc
                     lines
                     (cadr-tui:wrap-text
                      (string-right-trim " " current)
                      width)))
              (setf current
                    (if
                        (<=
                         (cadr-tui:visible-width indented)
                         width)
                        indented item))))))
    (when (plusp (length current))
      (setf lines
            (nconc
             lines
             (cadr-tui:wrap-text
              (string-right-trim " " current)
              width))))
    (mapcar
     (lambda (line)
       (selector-dim-line line width))
     lines)))

(defun render-tree-selector (state width)
  (append
   (list
    ""
    (selector-border-line width)
    (selector-fit-line
     (cadr-tui:theme-bold "  Session Tree")
     width))
   (tree-selector-help-lines state width)
   (list
    (selector-fit-line
     (concatenate
      'string "  "
      (cadr-tui:theme-foreground
       :muted "Type to search:")
      (if
          (plusp
           (length
            (tree-selector-state-query state)))
          (concatenate
           'string " "
           (cadr-tui:theme-foreground
            :accent
            (tree-selector-state-query state)))
          ""))
     width)
    (selector-border-line width)
    "")
   (if (eq :label
           (tree-selector-state-mode state))
       (list
        (selector-muted-line
         "  Label (empty to remove):" width)
        (selector-fit-line
         (concatenate
          'string "  "
          (cadr-tui:theme-foreground
           :accent
           (tree-selector-state-label-input state)))
         width)
        (selector-dim-line
         "  enter save  escape cancel" width))
       (tree-selector-render-lines state width))
   (list ""
         (selector-border-line width))))

(defun project-trust-options (cwd)
  (let* ((path
           (canonical-directory-name cwd))
         (parent
           (parent-directory
            (uiop:ensure-directory-pathname
             cwd)))
         (parent-path
           (and parent
                (canonical-directory-name
                 parent))))
    (append
     (list
      (list
       :label "Trust"
       :trusted-p t
       :saved-path path
       :updates
       (list
        (list :path path :decision t))))
     (and
      parent-path
      (list
       (list
        :label
        (format nil
                "Trust parent folder (~A)"
                parent-path)
        :trusted-p t
        :saved-path parent-path
        :updates
        (list
         (list
          :path parent-path
          :decision t)
         (list
          :path path
          :decision :remove)))))
     (list
      (list
       :label "Do not trust"
       :trusted-p nil
       :saved-path path
       :updates
       (list
        (list
         :path path
         :decision nil)))))))

(defstruct (trust-selector-state
            (:constructor
                %make-trust-selector-state))
  (cwd "" :type string)
  saved-entry
  (project-trusted-p nil :type boolean)
  (options nil :type list)
  (selected 0 :type (integer 0 *))
  keybindings)

(defun trust-option-saved-p
    (option saved-entry)
  (and
   saved-entry
   (equal
    (not (null
          (getf saved-entry :decision)))
    (not (null
          (getf option :trusted-p))))
   (string=
    (getf saved-entry :path)
    (getf option :saved-path))))

(defun make-trust-selector-state
    (&key cwd saved-entry project-trusted-p
       keybindings)
  (let* ((path
           (canonical-directory-name cwd))
         (options
           (project-trust-options cwd))
         (saved-position
           (position-if
            (lambda (option)
              (trust-option-saved-p
               option saved-entry))
            options)))
    (%make-trust-selector-state
     :cwd path
     :saved-entry saved-entry
     :project-trusted-p
     (not (null project-trusted-p))
     :options options
     :selected (or saved-position 0)
     :keybindings
     (or keybindings
         (cadr-tui:make-keybindings-manager)))))

(defun trust-selector-move
    (state delta)
  (let ((count
          (length
           (trust-selector-state-options state))))
    (when (plusp count)
      (setf
       (trust-selector-state-selected state)
       (mod
        (+ (trust-selector-state-selected state)
           delta)
        count))))
  state)

(defun trust-selector-selection (state)
  (let ((option
          (nth
           (trust-selector-state-selected state)
           (trust-selector-state-options state))))
    (and option
         (list
          :trusted-p
          (getf option :trusted-p)
          :updates
          (copy-tree
           (getf option :updates))))))

(defun trust-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:up
     (trust-selector-move state -1)
     (values :changed nil))
    (:down
     (trust-selector-move state 1)
     (values :changed nil))
    ((:enter :submit)
     (values
      :select
      (trust-selector-selection state)))
    ((:escape :cancel)
     (values :cancel nil))
    (:text
     (let ((text
             (or
              (cadr-tui:input-event-text event)
              "")))
       (cond
         ((string= text "k")
          (trust-selector-move state -1)
          (values :changed nil))
         ((string= text "j")
          (trust-selector-move state 1)
          (values :changed nil))
         (t
          (values nil nil)))))
    (otherwise
     (values nil nil))))

(defun trust-selector-handle-raw-input
    (state data)
  (cond
    ((or
      (string= data "k")
      (selector-keybinding-matches-p
       (trust-selector-state-keybindings state)
       data "tui.select.up"))
     (trust-selector-move state -1)
     (values :changed nil t))
    ((or
      (string= data "j")
      (selector-keybinding-matches-p
       (trust-selector-state-keybindings state)
       data "tui.select.down"))
     (trust-selector-move state 1)
     (values :changed nil t))
    ((or
      (string= data (string #\Newline))
      (selector-keybinding-matches-p
       (trust-selector-state-keybindings state)
       data "tui.select.confirm"))
     (values
      :select
      (trust-selector-selection state)
      t))
    ((selector-keybinding-matches-p
      (trust-selector-state-keybindings state)
      data "tui.select.cancel")
     (values :cancel nil t))
    (t
     (values nil nil nil))))

(defun trust-decision-description
    (state)
  (let ((entry
          (trust-selector-state-saved-entry
           state)))
    (if (null entry)
        "none"
        (let* ((decision
                 (if
                     (getf entry :decision)
                     "trusted"
                     "untrusted"))
               (path (getf entry :path)))
          (if (string= path
                       (trust-selector-state-cwd
                        state))
              (format nil "~A (~A)"
                      decision path)
              (format nil
                      "~A (inherited from ~A)"
                      decision path))))))

(defun render-trust-selector
    (state width)
  (append
   (list
    (selector-border-line width)
    ""
    (selector-title-line "Project trust" width)
    (selector-muted-line
     (trust-selector-state-cwd state)
     width)
    ""
    (selector-muted-line
     (format nil "Saved decision: ~A"
             (trust-decision-description state))
     width)
    (selector-muted-line
     (format nil "Current session: ~A"
             (if
                 (trust-selector-state-project-trusted-p
                  state)
                 "trusted"
                 "untrusted"))
     width)
    "")
   (loop
     for option
       in (trust-selector-state-options state)
     for index from 0
     for selected-p =
       (= index
          (trust-selector-state-selected state))
     for saved-p =
       (trust-option-saved-p
        option
        (trust-selector-state-saved-entry state))
     for line =
       (concatenate
        'string
        (if selected-p
            (cadr-tui:theme-foreground
             :accent "→ ")
            "  ")
        (if selected-p
            (cadr-tui:theme-foreground
             :accent (getf option :label))
            (getf option :label))
        (if saved-p
            (cadr-tui:theme-foreground
             :success " ✓")
            ""))
     collect
       (selector-fit-line line width))
   (list
    ""
    (selector-dim-line
     "↑↓ navigate  enter save  escape cancel"
     width)
    ""
    (selector-border-line width))))

(defstruct settings-option
  id
  label
  description
  value
  (values nil :type list)
  format-function
  submenu)

(defstruct (settings-selector-state
            (:constructor
                %make-settings-selector-state))
  (options nil :type list)
  (filtered-options nil :type list)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  (mode :main :type symbol)
  (submenu-selected 0 :type (integer 0 *))
  (theme-names nil :type list)
  (single-theme "dark" :type string)
  (light-theme "dark" :type string)
  (dark-theme "dark" :type string)
  (original-theme "dark" :type string)
  (terminal-theme :dark :type symbol)
  change-callback
  keybindings)

(defun make-settings-selector-state
    (&key options change-callback keybindings
       theme-names (current-theme "dark")
       (terminal-theme :dark))
  (let* ((themes
           (or (copy-list theme-names)
               (let ((theme-option
                       (find "theme" options
                             :key #'settings-option-id
                             :test #'string=)))
                 (and theme-option
                      (copy-list
                       (settings-option-values
                        theme-option))))
               (list "dark")))
         (automatic (parse-auto-theme-setting current-theme))
         (default-single
           (if (and (stringp current-theme)
                    (member current-theme themes
                            :test #'string=))
               current-theme
               (or (find "dark" themes :test #'string=)
                   (first themes)
                   "dark")))
         (light
           (or (getf automatic :light-theme)
               default-single))
         (dark
           (or (getf automatic :dark-theme)
               default-single))
         (single
           (if automatic
               (if (eq terminal-theme :light)
                   light
                   dark)
               default-single))
         (state
           (%make-settings-selector-state
            :options (copy-list options)
            :filtered-options (copy-list options)
            :theme-names themes
            :single-theme single
            :light-theme
            light
            :dark-theme
            dark
            :original-theme current-theme
            :terminal-theme terminal-theme
            :change-callback change-callback
            :keybindings
            (or keybindings
                (cadr-tui:make-keybindings-manager)))))
    state))

(defun settings-display-value (value)
  (cond
    ((eq value t) "true")
    ((null value) "false")
    ((symbolp value)
     (string-downcase (symbol-name value)))
    (t (princ-to-string value))))

(defun settings-option-display-value (option)
  (if (settings-option-format-function option)
      (funcall
       (settings-option-format-function option)
       (settings-option-value option))
      (settings-display-value
       (settings-option-value option))))

(defun settings-selector-visible-options (state)
  (settings-selector-state-filtered-options state))

(defun settings-selector-apply-filter (state)
  (let ((query (settings-selector-state-query state)))
    (setf
     (settings-selector-state-filtered-options state)
     (if (zerop (length query))
         (copy-list (settings-selector-state-options state))
         (selector-fuzzy-filter
          (settings-selector-state-options state)
          query #'settings-option-label))
     (settings-selector-state-selected state) 0))
  state)

(defun settings-selector-move (state delta)
  (let ((count
          (length
           (settings-selector-visible-options state))))
    (when (plusp count)
      (setf
       (settings-selector-state-selected state)
       (mod (+ (settings-selector-state-selected state)
               delta)
            count))))
  state)

(defun settings-selector-selected-option (state)
  (nth
   (settings-selector-state-selected state)
   (settings-selector-visible-options state)))

(defun settings-selector-notify-change (state id value)
  (let ((option
          (find id (settings-selector-state-options state)
                :key #'settings-option-id :test #'string=)))
    (when option
      (setf (settings-option-value option) value)))
  (when (settings-selector-state-change-callback state)
    (funcall (settings-selector-state-change-callback state)
             id value))
  (list :id id :value value))

(defun settings-selector-cycle (state)
  (let ((option
          (settings-selector-selected-option state)))
    (when option
      (let* ((values
               (settings-option-values option))
             (position
               (position
                (settings-option-value option)
                values
                :test #'equal))
             (next
               (and values
                    (nth
                     (mod (1+
                           (or position -1))
                          (length values))
                     values))))
        (when values
          (setf
           (settings-option-value option)
           next)
          (settings-selector-notify-change
           state (settings-option-id option) next))))))

(defun settings-thinking-description (value)
  (cdr
   (assoc value
          '((:off . "No reasoning")
            (:minimal . "Very brief reasoning (~1k tokens)")
            (:low . "Light reasoning (~2k tokens)")
            (:medium . "Moderate reasoning (~8k tokens)")
            (:high . "Deep reasoning (~16k tokens)")
            (:xhigh . "Extra-high reasoning (~32k tokens)")
            (:max . "Maximum reasoning")))))

(defun settings-selector-open-submenu (state option)
  (setf (settings-selector-state-submenu-selected state) 0)
  (case (settings-option-submenu option)
    (:warnings
     (setf (settings-selector-state-mode state) :warnings))
    (:thinking
     (setf (settings-selector-state-mode state) :thinking
           (settings-selector-state-submenu-selected state)
           (or (position (settings-option-value option)
                         (settings-option-values option)
                         :test #'equal)
               0)))
    (:theme
     (let* ((setting (settings-option-value option))
            (automatic
              (parse-auto-theme-setting setting))
            (fixed
              (if automatic
                  nil
                  (if (member setting
                              (settings-selector-state-theme-names state)
                              :test #'string=)
                      setting
                      (or (find
                           "dark"
                           (settings-selector-state-theme-names state)
                           :test #'string=)
                          (first
                           (settings-selector-state-theme-names state))
                          "dark")))))
       (setf (settings-selector-state-light-theme state)
             (or (getf automatic :light-theme) fixed)
             (settings-selector-state-dark-theme state)
             (or (getf automatic :dark-theme) fixed)
             (settings-selector-state-single-theme state)
             (or fixed
                 (settings-selector-active-automatic-theme state)))
       (setf (settings-selector-state-mode state)
             (if automatic :theme-automatic :theme-single)
             (settings-selector-state-original-theme state)
             setting
             (settings-selector-state-submenu-selected state)
             (if automatic
                 0
                 (1+
                  (or (position
                       fixed
                       (settings-selector-state-theme-names state)
                       :test #'string=)
                      -1)))))))
  state)

(defun settings-selector-automatic-theme-setting (state)
  (format nil "~A/~A"
          (settings-selector-state-light-theme state)
          (settings-selector-state-dark-theme state)))

(defun settings-selector-active-automatic-theme (state)
  (if (eq :light
          (settings-selector-state-terminal-theme state))
      (settings-selector-state-light-theme state)
      (settings-selector-state-dark-theme state)))

(defun settings-selector-theme-preview-change (state)
  (let* ((mode (settings-selector-state-mode state))
         (option
           (nth
            (settings-selector-state-submenu-selected state)
            (settings-selector-submenu-options state)))
         (value
           (case mode
             (:theme-single
              (and option
                   (if (string=
                        (settings-option-value option) "/")
                       (settings-selector-automatic-theme-setting
                        state)
                       (settings-option-value option))))
             ((:theme-light :theme-dark)
              (and option
                   (settings-option-value option)))
             (otherwise nil))))
    (and value
         (list :id "theme-preview" :value value))))

(defun settings-selector-submenu-options (state)
  (case (settings-selector-state-mode state)
    (:warnings
     (let ((main
             (find "warnings"
                   (settings-selector-state-options state)
                   :key #'settings-option-id :test #'string=)))
       (list
        (make-settings-option
         :id "anthropic-extra-usage"
         :label "Anthropic extra usage"
         :description
         "Warn when Anthropic subscription auth may use paid extra usage"
         :value (if (and main
                         (consp (settings-option-value main)))
                    (getf (settings-option-value main)
                          :anthropic-extra-usage t)
                    t)
         :values (list t nil)))))
    (:thinking
     (let ((main
             (find "thinking"
                   (settings-selector-state-options state)
                   :key #'settings-option-id :test #'string=)))
       (loop for value in (and main
                               (settings-option-values main))
             collect
             (make-settings-option
              :id (string-downcase (symbol-name value))
              :label (string-downcase (symbol-name value))
              :description (settings-thinking-description value)
              :value value))))
    (:theme-single
     (cons
      (make-settings-option
       :id "automatic" :label "Automatic" :value "/"
       :description
       "Use separate themes for light and dark terminal appearance")
      (loop for name in (settings-selector-state-theme-names state)
            collect
            (make-settings-option
             :id name :label name :value name))))
    (:theme-automatic
     (list
      (make-settings-option
       :id "light-theme" :label "Light theme"
       :description
       "Theme to use in automatic mode when the terminal is light"
       :value (settings-selector-state-light-theme state)
       :submenu :theme-light)
      (make-settings-option
       :id "dark-theme" :label "Dark theme"
       :description
       "Theme to use in automatic mode when the terminal is dark"
       :value (settings-selector-state-dark-theme state)
       :submenu :theme-dark)
      (make-settings-option
       :id "apply" :label "Apply"
       :description "Save and go back"
       :value "save and go back"
       :values (list "save and go back"))
      (make-settings-option
       :id "single-mode" :label "Change mode"
       :description "Switch to one theme for light and dark"
       :value "switch to single theme"
       :values (list "switch to single theme"))))
    ((:theme-light :theme-dark)
     (loop for name in (settings-selector-state-theme-names state)
           collect
           (make-settings-option
            :id name :label name :value name)))
    (otherwise nil)))

(defun settings-selector-submenu-move (state delta)
  (let ((count
          (length (settings-selector-submenu-options state))))
    (when (plusp count)
      (setf (settings-selector-state-submenu-selected state)
            (mod (+ (settings-selector-state-submenu-selected state)
                    delta)
                 count))))
  (values state
          (settings-selector-theme-preview-change state)))

(defun settings-selector-close-submenu (state)
  (setf (settings-selector-state-mode state) :main)
  state)

(defun settings-selector-activate-submenu (state)
  (let* ((mode (settings-selector-state-mode state))
         (option
           (nth (settings-selector-state-submenu-selected state)
                (settings-selector-submenu-options state))))
    (let ((change nil))
      (when option
        (case mode
          (:warnings
           (let* ((main
                    (find "warnings"
                          (settings-selector-state-options state)
                          :key #'settings-option-id :test #'string=))
                  (current
                    (if (and main
                             (consp (settings-option-value main)))
                        (getf (settings-option-value main)
                              :anthropic-extra-usage t)
                        t))
                  (next (not current)))
             (when main
               (setf (settings-option-value main)
                     (list :anthropic-extra-usage next)))
             (when (settings-selector-state-change-callback state)
               (funcall (settings-selector-state-change-callback state)
                        "anthropic-extra-usage" next))))
          (:thinking
           (setf change
                 (settings-selector-notify-change
                  state "thinking"
                  (settings-option-value option)))
           (settings-selector-close-submenu state))
          (:theme-single
           (if (string= (settings-option-value option) "/")
               (progn
                 (setf (settings-selector-state-mode state)
                       :theme-automatic
                       (settings-selector-state-submenu-selected state) 0)
                 (setf change
                       (list
                        :id "theme-preview"
                        :value
                        (settings-selector-automatic-theme-setting
                         state))))
               (let ((setting (settings-option-value option)))
                 (setf (settings-selector-state-single-theme state)
                       setting
                       change
                       (settings-selector-notify-change
                        state "theme" setting)
                       (settings-selector-state-original-theme state)
                       setting)
                 (settings-selector-close-submenu state))))
          (:theme-automatic
           (cond
             ((string= (settings-option-id option) "light-theme")
              (setf (settings-selector-state-mode state) :theme-light
                    (settings-selector-state-submenu-selected state)
                    (or (position
                         (settings-selector-state-light-theme state)
                         (settings-selector-state-theme-names state)
                         :test #'string=)
                        0)))
             ((string= (settings-option-id option) "dark-theme")
              (setf (settings-selector-state-mode state) :theme-dark
                    (settings-selector-state-submenu-selected state)
                    (or (position
                         (settings-selector-state-dark-theme state)
                         (settings-selector-state-theme-names state)
                         :test #'string=)
                        0)))
             ((string= (settings-option-id option) "apply")
              (let ((setting
                      (settings-selector-automatic-theme-setting
                       state)))
                (setf change
                      (settings-selector-notify-change
                       state "theme" setting)
                      (settings-selector-state-original-theme state)
                      setting)
                (settings-selector-close-submenu state)))
             ((string= (settings-option-id option) "single-mode")
              (let ((active
                      (settings-selector-active-automatic-theme
                       state)))
                (setf (settings-selector-state-single-theme state)
                      active
                      (settings-selector-state-mode state) :theme-single
                      (settings-selector-state-submenu-selected state)
                      (1+ (or (position
                               active
                               (settings-selector-state-theme-names state)
                               :test #'string=)
                              -1))
                      change
                      (list :id "theme-preview" :value active))))))
          (:theme-light
           (setf (settings-selector-state-light-theme state)
                 (settings-option-value option)
                 (settings-selector-state-mode state) :theme-automatic
                 (settings-selector-state-submenu-selected state) 0
                 change
                 (list
                  :id "theme-preview"
                  :value
                  (settings-selector-automatic-theme-setting state))))
          (:theme-dark
           (setf (settings-selector-state-dark-theme state)
                 (settings-option-value option)
                 (settings-selector-state-mode state) :theme-automatic
                 (settings-selector-state-submenu-selected state) 1
                 change
                 (list
                  :id "theme-preview"
                  :value
                  (settings-selector-automatic-theme-setting state))))))
      (values state change))))

(defun settings-selector-handle-event
    (state event)
  (unless (eq (settings-selector-state-mode state) :main)
    (case (cadr-tui:input-event-kind event)
      (:up
       (multiple-value-bind (updated change)
           (settings-selector-submenu-move state -1)
         (declare (ignore updated))
         (return-from settings-selector-handle-event
           (values :changed change))))
      (:down
       (multiple-value-bind (updated change)
           (settings-selector-submenu-move state 1)
         (declare (ignore updated))
         (return-from settings-selector-handle-event
           (values :changed change))))
      (:page-up
       (multiple-value-bind (updated change)
           (settings-selector-submenu-move state -10)
         (declare (ignore updated))
         (return-from settings-selector-handle-event
           (values :changed change))))
      (:page-down
       (multiple-value-bind (updated change)
           (settings-selector-submenu-move state 10)
         (declare (ignore updated))
         (return-from settings-selector-handle-event
           (values :changed change))))
      ((:enter :submit)
       (multiple-value-bind (updated change)
           (settings-selector-activate-submenu state)
         (declare (ignore updated))
         (return-from settings-selector-handle-event
           (values :changed change))))
      (:text
       (when (string= (or (cadr-tui:input-event-text event) "")
                      " ")
         (multiple-value-bind (updated change)
             (settings-selector-activate-submenu state)
           (declare (ignore updated))
           (return-from settings-selector-handle-event
             (values :changed change)))))
      ((:escape :cancel)
       (let ((mode (settings-selector-state-mode state))
             (change nil))
         (if (member mode '(:theme-light :theme-dark))
             (progn
               (setf (settings-selector-state-mode state)
                     :theme-automatic)
               (setf change
                     (list
                      :id "theme-preview"
                      :value
                      (settings-selector-automatic-theme-setting
                       state))))
             (progn
               (when (member mode
                             '(:theme-single :theme-automatic))
                 (setf change
                       (list
                        :id "theme-preview"
                        :value
                        (settings-selector-state-original-theme
                         state))))
               (settings-selector-close-submenu state)))
       (return-from settings-selector-handle-event
           (values :changed change))))))
  (case (cadr-tui:input-event-kind event)
    (:up
     (settings-selector-move state -1)
     (values :changed nil))
    (:down
     (settings-selector-move state 1)
     (values :changed nil))
    (:page-up
     (settings-selector-move state -8)
     (values :changed nil))
    (:page-down
     (settings-selector-move state 8)
     (values :changed nil))
    ((:enter :submit)
     (let ((option (settings-selector-selected-option state)))
       (cond
         ((and option (settings-option-submenu option))
          (settings-selector-open-submenu state option)
          (values :changed nil))
         (t
          (let ((change (settings-selector-cycle state)))
            (if change
                (values :changed change)
                (values nil nil)))))))
    ((:escape :cancel)
     (values :cancel nil))
    (:backspace
     (setf (settings-selector-state-query state)
           (selector-delete-query-character
            (settings-selector-state-query state)))
     (settings-selector-apply-filter state)
     (values :changed nil))
    (:text
     (let* ((text
              (or (cadr-tui:input-event-text event) ""))
            (sanitized
              (remove #\Space text)))
       (if (string= text " ")
           (let ((option (settings-selector-selected-option state)))
             (cond
               ((and option (settings-option-submenu option))
                (settings-selector-open-submenu state option)
                (values :changed nil))
               (t
                (let ((change (settings-selector-cycle state)))
                  (if change
                      (values :changed change)
                      (values nil nil))))))
           (progn
             (when (plusp (length sanitized))
               (setf (settings-selector-state-query state)
                     (concatenate
                      'string
                      (settings-selector-state-query state)
                      sanitized))
               (settings-selector-apply-filter state))
             (values :changed nil)))))
    (otherwise
     (values nil nil))))

(defun settings-selector-handle-raw-input
    (state data)
  (let ((keybindings
          (settings-selector-state-keybindings state)))
    (cond
      ((selector-keybinding-matches-p
        keybindings data "tui.select.up")
       (multiple-value-bind (action value)
           (settings-selector-handle-event
            state (cadr-tui:make-input-event :kind :up))
         (values action value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.down")
       (multiple-value-bind (action value)
           (settings-selector-handle-event
            state (cadr-tui:make-input-event :kind :down))
         (values action value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.pageUp")
       (multiple-value-bind (action value)
           (settings-selector-handle-event
            state (cadr-tui:make-input-event :kind :page-up))
         (values action value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.pageDown")
       (multiple-value-bind (action value)
           (settings-selector-handle-event
            state (cadr-tui:make-input-event :kind :page-down))
         (values action value t)))
      ((or (string= data (string #\Newline))
           (selector-keybinding-matches-p
         keybindings data "tui.select.confirm"))
       (multiple-value-bind (action value)
           (settings-selector-handle-event
            state (cadr-tui:make-input-event :kind :enter))
         (values action value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.cancel")
       (multiple-value-bind (action value)
           (settings-selector-handle-event
            state (cadr-tui:make-input-event :kind :escape))
         (values action value t)))
      ((and (= (length data) 1)
            (graphic-char-p (char data 0)))
       (multiple-value-bind (action value)
           (settings-selector-handle-event
            state
            (cadr-tui:make-input-event
             :kind :text :text data))
         (values action value t)))
      (t (values nil nil nil)))))

(defun settings-selector-visible-slice
    (options selected maximum)
  (let* ((count (length options))
         (start
           (max 0
                (min (- selected (floor maximum 2))
                     (- count maximum))))
         (end (min count (+ start maximum))))
    (values (subseq options start end) start end count)))

(defun settings-selector-max-label-width (options)
  (min 30
       (loop for option in options
             maximize
             (cadr-tui:visible-width
              (settings-option-label option)))))

(defun render-settings-option-list
    (options all-options selected width maximum
     &key search-query search-p)
  (multiple-value-bind (visible start end total)
      (settings-selector-visible-slice options selected maximum)
    (let ((label-width
            (if all-options
                (settings-selector-max-label-width all-options)
                1)))
      (append
       (when search-p
         (list
          (selector-fit-line
           (concatenate
            'string
            (cadr-tui:theme-foreground :muted "> ")
            (cadr-tui:theme-foreground :accent
                                       (or search-query "")))
           width)
          ""))
       (if visible
           (loop for option in visible
                 for index from start
                 for selected-p = (= index selected)
                 for label = (settings-option-label option)
                 for padding =
                   (make-string
                    (max 0 (- label-width
                              (cadr-tui:visible-width label)))
                    :initial-element #\Space)
                 for line =
                   (concatenate
                    'string
                    (if selected-p
                        (cadr-tui:theme-foreground :accent "→ ")
                        "  ")
                    (if selected-p
                        (cadr-tui:theme-foreground :accent label)
                        label)
                    padding "  "
                    (cadr-tui:theme-foreground
                     (if selected-p :accent :muted)
                     (settings-option-display-value option)))
                 collect (selector-fit-line line width))
           (list (selector-muted-line
                  "  No matching settings" width)))
       (when (or (> start 0) (< end total))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)" (1+ selected) total)
           width)))
       (let ((option (nth selected options)))
         (when (and option (settings-option-description option))
           (append
            (list "")
            (mapcar
             (lambda (line)
               (selector-dim-line
                (concatenate 'string "  " line) width))
             (cadr-tui:wrap-text
              (settings-option-description option)
              (max 1 (- width 4)))))))
       (list
        ""
        (selector-dim-line
         (if search-p
             "  Type to search · Enter/Space to change · Esc to cancel"
             "  Enter/Space to change · Esc to cancel")
         width))))))

(defun render-settings-select-submenu
    (state width title description)
  (let* ((options (settings-selector-submenu-options state))
         (selected (settings-selector-state-submenu-selected state)))
    (append
     (list
      (selector-title-line title width)
      "")
     (mapcar
      (lambda (line) (selector-muted-line line width))
      (cadr-tui:wrap-text description width))
     (list "")
     (multiple-value-bind (visible start end total)
         (settings-selector-visible-slice options selected 10)
       (let ((primary-width
               (max 12
                    (min 32
                         (loop for option in options
                               maximize
                               (+ 2 (cadr-tui:visible-width
                                     (settings-option-label option))))))))
         (append
          (loop for option in visible
                for index from start
                for selected-p = (= index selected)
                for label = (settings-option-label option)
                for desc = (settings-option-description option)
                for prefix = (if selected-p "→ " "  ")
                for primary =
                  (if (and desc (> width 40))
                      (concatenate
                       'string label
                       (make-string
                        (max 1 (- primary-width
                                  (cadr-tui:visible-width label)))
                        :initial-element #\Space)
                       desc)
                      label)
                collect
                (selector-fit-line
                 (concatenate
                  'string
                  (if selected-p
                      (cadr-tui:theme-foreground :accent prefix)
                      prefix)
                  (if selected-p
                      (cadr-tui:theme-foreground :accent primary)
                      primary))
                 width))
          (when (or (> start 0) (< end total))
            (list
             (selector-muted-line
              (format nil "  (~D/~D)" (1+ selected) total)
              width))))))
     (list ""
           (selector-dim-line
            "  Enter to select · Esc to go back" width)))))

(defun render-settings-selector
    (state width)
  (append
   (list (selector-border-line width))
   (case (settings-selector-state-mode state)
     (:main
      (render-settings-option-list
       (settings-selector-visible-options state)
       (settings-selector-state-options state)
       (settings-selector-state-selected state)
       width 10
       :search-query (settings-selector-state-query state)
       :search-p t))
     (:warnings
      (render-settings-option-list
       (settings-selector-submenu-options state)
       (settings-selector-submenu-options state)
       (settings-selector-state-submenu-selected state)
       width 1))
     (:thinking
      (render-settings-select-submenu
       state width "Thinking Level"
       "Select reasoning depth for thinking-capable models"))
     (:theme-single
      (render-settings-select-submenu
       state width "Theme"
       "Select a theme, or choose Automatic to follow terminal appearance."))
     (:theme-light
      (render-settings-select-submenu
       state width "Light Theme"
       "Select the theme to use for light terminal appearance"))
     (:theme-dark
      (render-settings-select-submenu
       state width "Dark Theme"
       "Select the theme to use for dark terminal appearance"))
     (:theme-automatic
      (append
       (list
        (selector-title-line "Automatic Theme" width)
        ""
        (selector-muted-line
         "Choose themes for terminal light and dark appearance."
         width)
        (selector-muted-line
         "Light/dark detection requires terminal support."
         width)
        "")
       (render-settings-option-list
        (settings-selector-submenu-options state)
        (settings-selector-submenu-options state)
        (settings-selector-state-submenu-selected state)
        width 4)))
     (otherwise nil))
   (list (selector-border-line width))))

(defstruct oauth-selector-option
  id
  name
  auth-type
  method-name
  status)

(defstruct (login-method-selector-state
            (:constructor
                %make-login-method-selector-state))
  select-list)

(defun make-login-method-selector-state ()
  (%make-login-method-selector-state
   :select-list
   (cadr-tui:make-select-list
    :items
    (list
     (cadr-tui:make-select-item
      :label "Sign in with an account"
      :value :oauth)
     (cadr-tui:make-select-item
      :label "Sign in with an API key"
      :value :api-key))
    :height 2
    :show-filter-p nil)))

(defun login-method-selector-handle-event
    (state event)
  (if
      (member
       (cadr-tui:input-event-kind event)
       '(:clear :interrupt))
      (values :cancel nil)
      (cadr-tui:select-list-handle-event
       (login-method-selector-state-select-list
        state)
       event)))

(defun render-login-method-selector (state width)
  (append
   (list
    (selector-border-line width)
    ""
    (selector-fit-line " Select authentication method:" width)
    "")
   (mapcar
    (lambda (line)
      (selector-fit-line
       (concatenate 'string " " line)
       width))
    (cadr-tui:render-select-list
     (login-method-selector-state-select-list state)
     (max 0 (1- width))
     :ansi-theme-p t))
   (list
    ""
    (selector-fit-line
     " ↑↓ navigate  enter select  escape/ctrl+c cancel"
     width)
    ""
    (selector-border-line width))))

(defstruct (api-key-input-state
            (:constructor
                %make-api-key-input-state))
  option
  input)

(defmethod print-object ((value api-key-input-state) stream)
  (print-unreadable-object (value stream :type t)
    (format stream ":provider ~A :input [REDACTED]"
            (oauth-selector-option-id
             (api-key-input-state-option value)))))

(defun make-api-key-input-state (option)
  (%make-api-key-input-state
   :option option
   :input
   (cadr-tui:make-single-line-input
    :prompt "> ")))

(defun api-key-input-state-handle-event
    (state event)
  (if
      (member
       (cadr-tui:input-event-kind event)
       '(:escape :cancel :clear :interrupt :eof))
      (values :cancel nil)
      (multiple-value-bind (action value)
          (cadr-tui:single-line-input-handle-event
           (api-key-input-state-input state)
           event)
        (if (eq action :submit)
            (if (cadr-ai::non-empty-string-p value)
                (values
                 :select
                 (list
                  :option
                  (api-key-input-state-option state)
                  :key value))
                (values :changed nil))
            (values action value)))))

(defun render-api-key-input-state (state width)
  (let* ((option
           (api-key-input-state-option state))
         (input
           (api-key-input-state-input state))
         (masked
           (cadr-tui:make-single-line-input
            :value
            (make-string
             (length
              (cadr-tui:single-line-input-value
               input))
             :initial-element #\*)
            :prompt "> ")))
    (setf
     (cadr-tui::single-line-input-cursor masked)
     (cadr-tui::single-line-input-cursor input))
    (multiple-value-bind (input-lines row column)
        (cadr-tui:render-single-line-input
         masked width)
      (declare (ignore row column))
      (append
       (list
        (selector-border-line width)
        (selector-fit-line
         (concatenate
          'string
          " "
          (cadr-tui:theme-foreground
           :accent
           (cadr-tui:theme-bold
            (format nil "Login to ~A"
                    (oauth-selector-option-name option))
            :enabled-p t)
           :enabled-p t))
         width)
        ""
        (selector-fit-line
         (format nil " Enter ~A API key"
                 (oauth-selector-option-name option))
         width))
       input-lines
       (list
        (selector-fit-line
         " (escape/ctrl+c to cancel, enter to submit)"
         width)
        (selector-border-line width))))))

(defstruct (oauth-selector-state
            (:constructor
                %make-oauth-selector-state))
  (mode :login :type symbol)
  (options nil :type list)
  (filtered-options nil :type list)
  (selected 0 :type (integer 0 *))
  (query "" :type string)
  keybindings)

(defun login-provider-options
    (definitions &key auth-type status-function)
  (sort
   (loop
     for definition in definitions
     append
     (loop
       for candidate
         in (cadr-ai:provider-definition-auth-types
             definition)
       when
         (or (null auth-type)
             (eq candidate auth-type))
         collect
         (make-oauth-selector-option
          :id
          (cadr-ai:provider-definition-id
           definition)
          :name
          (cadr-ai:provider-definition-name
           definition)
          :auth-type candidate
          :method-name
          (let ((metadata
                  (and
                   (eq candidate :oauth)
                   (cadr-ai:provider-definition-oauth-metadata
                    definition))))
            (if metadata
                (cadr-ai:oauth-provider-metadata-method-name
                 metadata)
                (format
                 nil "~A ~A"
                 (cadr-ai:provider-definition-name definition)
                 (if (eq candidate :oauth)
                     "account"
                     "API key"))))
          :status
          (and status-function
               (funcall
                status-function
                (cadr-ai:provider-definition-id
                 definition))))))
   #'string-lessp
   :key #'oauth-selector-option-name))

(defun credential-entry-auth-type (kind)
  (let ((normalized
          (string-downcase
           (etypecase kind
             (string kind)
             (symbol (symbol-name kind))))))
    (cond
      ((member normalized '("oauth") :test #'string=)
       :oauth)
      ((member normalized '("api-key" "api_key")
               :test #'string=)
       :api-key)
      (t
       (error "Unsupported credential type: ~A" kind)))))

(defun logout-provider-options
    (definitions credential-entries)
  (sort
   (loop
     for (provider-key . kind) in credential-entries
     for provider = (provider-symbol-from-key provider-key)
     for definition =
       (find provider definitions
             :key #'cadr-ai:provider-definition-id
             :test #'eq)
     for auth-type = (credential-entry-auth-type kind)
     for name =
       (if definition
           (cadr-ai:provider-definition-name definition)
           provider-key)
     collect
       (make-oauth-selector-option
        :id provider
        :name name
        :auth-type auth-type
        :method-name
        (format nil "~A ~A" name
                (if (eq auth-type :oauth)
                    "account"
                    "API key"))
        :status
        (list :type auth-type
              :source "stored credential")))
   #'string-lessp :key #'oauth-selector-option-name))

(defun make-oauth-selector-state
    (&key (mode :login) options (query "") keybindings)
  (let ((state
          (%make-oauth-selector-state
           :mode mode
           :options (copy-list options)
           :filtered-options (copy-list options)
           :query query
           :keybindings
           (or keybindings
               (cadr-tui:make-keybindings-manager)))))
    (oauth-selector-apply-filter state)
    state))

(defun oauth-selector-search-text (option)
  (format nil "~A ~A ~A ~A"
          (oauth-selector-option-name option)
          (provider-key (oauth-selector-option-id option))
          (oauth-selector-option-auth-type option)
          (or (oauth-selector-option-method-name option) "")))

(defun oauth-selector-apply-filter (state)
  (let ((query (oauth-selector-state-query state)))
    (setf
     (oauth-selector-state-filtered-options state)
     (if (zerop (length query))
         (copy-list (oauth-selector-state-options state))
         (selector-fuzzy-filter
          (oauth-selector-state-options state)
          query #'oauth-selector-search-text))
     (oauth-selector-state-selected state) 0))
  state)

(defun oauth-selector-move (state delta)
  (let ((count
          (length
           (oauth-selector-state-filtered-options state))))
    (when (plusp count)
      (setf
       (oauth-selector-state-selected state)
       (mod
        (+ (oauth-selector-state-selected state)
           delta)
        count))))
  state)

(defun oauth-selector-selection (state)
  (nth
   (oauth-selector-state-selected state)
   (oauth-selector-state-filtered-options state)))

(defun oauth-environment-source-p (source)
  (and
   (stringp source)
   (find #\_ source)
   (every
    (lambda (character)
      (or
       (upper-case-p character)
       (digit-char-p character)
       (char= character #\_)))
    source)))

(defun oauth-option-status-label (option)
  (let* ((status
           (oauth-selector-option-status option))
         (type (getf status :type))
         (source (getf status :source)))
    (cond
      ((null status) "• unconfigured")
      ((and
        type
        (not (eq type
                 (oauth-selector-option-auth-type option))))
       (format nil "• ~A configured"
               (if (eq type :oauth)
                   "subscription"
                   "API key")))
      ((or (null source)
           (member source '("OAuth" "stored credential")
                   :test #'string=))
       "✓ configured")
      ((oauth-environment-source-p source)
       (format nil "✓ env: ~A" source))
      (source
       (format nil "✓ ~A" source))
      (t "✓ configured"))))

(defun oauth-option-status-rendered (option)
  (let* ((status (oauth-selector-option-status option))
         (type (getf status :type))
         (label (oauth-option-status-label option)))
    (cond
      ((null status)
       (cadr-tui:theme-foreground
        :muted label :enabled-p t))
      ((and type
            (not (eq type
                     (oauth-selector-option-auth-type option))))
       (concatenate
        'string
        (cadr-tui:theme-foreground
         :muted "• " :enabled-p t)
        (cadr-tui:theme-foreground
         :warning (subseq label 2) :enabled-p t)))
      (t
       (cadr-tui:theme-foreground
        :success label :enabled-p t)))))

(defun oauth-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:up
     (oauth-selector-move state -1)
     (values :changed nil))
    (:down
     (oauth-selector-move state 1)
     (values :changed nil))
    (:page-up
     (oauth-selector-move state -8)
     (values :changed nil))
    (:page-down
     (oauth-selector-move state 8)
     (values :changed nil))
    ((:enter :submit)
     (values
      :select
      (oauth-selector-selection state)))
    ((:escape :cancel)
     (values :cancel nil))
    (:backspace
     (setf
      (oauth-selector-state-query state)
      (selector-delete-query-character
       (oauth-selector-state-query state)))
     (oauth-selector-apply-filter state)
     (values :changed nil))
    (:text
     (setf
      (oauth-selector-state-query state)
      (concatenate
       'string
       (oauth-selector-state-query state)
       (or (cadr-tui:input-event-text event) "")))
     (oauth-selector-apply-filter state)
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun oauth-selector-handle-raw-input
    (state data)
  (let ((keybindings
          (oauth-selector-state-keybindings state)))
    (cond
      ((selector-keybinding-matches-p
        keybindings data "tui.select.up")
       (oauth-selector-move state -1)
       (values :changed nil t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.down")
       (oauth-selector-move state 1)
       (values :changed nil t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.pageUp")
       (oauth-selector-move state -8)
       (values :changed nil t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.pageDown")
       (oauth-selector-move state 8)
       (values :changed nil t))
      ((or
        (string= data (string #\Newline))
        (selector-keybinding-matches-p
         keybindings data "tui.select.confirm"))
       (values
        :select
        (oauth-selector-selection state)
        t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.cancel")
       (values :cancel nil t))
      ((and (= (length data) 1)
            (graphic-char-p (char data 0)))
       (multiple-value-bind (action value)
           (oauth-selector-handle-event
            state
            (cadr-tui:make-input-event
             :kind :text :text data))
         (values action value t)))
      (t
       (values nil nil nil)))))

(defun render-oauth-selector (state width)
  (let* ((options
           (oauth-selector-state-filtered-options state))
         (selected (oauth-selector-state-selected state))
         (show-auth-type-labels-p
           (> (length
               (remove-duplicates
                (mapcar #'oauth-selector-option-auth-type
                        (oauth-selector-state-options state))))
              1)))
    (multiple-value-bind (visible start end total)
        (settings-selector-visible-slice options selected 8)
      (append
       (list
        (selector-border-line width)
        ""
        (selector-fit-line
         (concatenate
          'string
          " "
          (cadr-tui:theme-foreground
           :accent
           (cadr-tui:theme-bold
            (if (eq (oauth-selector-state-mode state) :logout)
                "Select provider to logout:"
                "Select provider to configure:")
            :enabled-p t)
           :enabled-p t))
         width)
        ""
        (selector-fit-line
         (concatenate 'string "> "
                      (oauth-selector-state-query state))
         width)
        "")
       (if visible
           (loop
             for option in visible
             for index from start
             collect
               (let* ((selected-p (= index selected))
                      (prefix
                        (if selected-p
                            (cadr-tui:theme-foreground
                             :accent "→ " :enabled-p t)
                            "  "))
                      (name
                        (cadr-tui:theme-foreground
                         (if selected-p :accent :text)
                         (oauth-selector-option-name option)
                         :enabled-p t))
                      (auth-type
                        (if show-auth-type-labels-p
                            (cadr-tui:theme-foreground
                             :muted
                             (format nil " [~A]"
                                     (if (eq
                                          (oauth-selector-option-auth-type
                                           option)
                                          :oauth)
                                         "subscription"
                                         "API key"))
                             :enabled-p t)
                            "")))
                 (selector-fit-line
                  (concatenate
                   'string " " prefix name auth-type " "
                   (oauth-option-status-rendered option))
                  width)))
           (list
            (selector-muted-line
             (cond
               ((plusp (length
                        (oauth-selector-state-options state)))
                "  No matching providers")
               ((eq (oauth-selector-state-mode state) :logout)
                "  No providers logged in. Use /login first.")
               (t "  No providers available"))
             width)))
       (when (or (> start 0) (< end total))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)" (1+ selected) total)
           width)))
       (list "" (selector-border-line width))))))

(defparameter +models-selector-keybinding-definitions+
  (append
   (copy-tree
    cadr-tui::+tui-keybinding-definitions+)
   '(("app.models.save" . ("ctrl+s"))
     ("app.models.enableAll" . ("ctrl+a"))
     ("app.models.clearAll" . ("ctrl+x"))
     ("app.models.toggleProvider" . ("ctrl+p"))
     ("app.models.reorderUp" . ("alt+up"))
     ("app.models.reorderDown" . ("alt+down"))
     ("app.models.clearSearchOrCancel"
      . ("ctrl+c")))))

(defun make-models-selector-keybindings
    (&optional user-bindings)
  (cadr-tui:make-keybindings-manager
   :definitions
   +models-selector-keybinding-definitions+
   :user-bindings user-bindings))

(defun qualified-model-id (model)
  (format nil "~(~A~)/~A"
          (cadr-ai:model-provider model)
          (cadr-ai:model-id model)))

(defun model-selector-search-text (model)
  (format nil "~(~A~) ~A ~(~A~) ~A~@[ ~A~]"
          (cadr-ai:model-provider model)
          (qualified-model-id model)
          (cadr-ai:model-provider model)
          (cadr-ai:model-id model)
          (let ((name
                  (cadr-ai::model-name model)))
            (and (stringp name)
                 (plusp (length name))
                 name))))

(defun scoped-model-selector-search-text
    (model)
  (format nil "~A ~(~A~) ~A ~(~A~) ~A~@[ ~A~]"
          (cadr-ai:model-id model)
          (cadr-ai:model-provider model)
          (qualified-model-id model)
          (cadr-ai:model-provider model)
          (cadr-ai:model-id model)
          (let ((name
                  (cadr-ai::model-name model)))
            (and (stringp name)
                 (plusp (length name))
                 name))))

(defun selector-fuzzy-filter
    (items query text-function)
  (let ((tokens
          (cadr-tui::fuzzy-query-tokens query)))
    (when (null tokens)
      (return-from selector-fuzzy-filter
        (copy-list items)))
    (let ((matches nil))
      (dolist (item items)
        (let ((score 0d0)
              (matched-p t)
              (text
                (funcall text-function item)))
          (dolist (token tokens)
            (multiple-value-bind
                  (token-matched-p token-score)
                (cadr-tui:fuzzy-match token text)
              (unless token-matched-p
                (setf matched-p nil)
                (return))
              (incf score token-score)))
          (when matched-p
            (push (cons item score) matches))))
      (mapcar
       #'car
       (stable-sort
        (nreverse matches)
        #'< :key #'cdr)))))

(defun model-equal-p (left right)
  (and left right
       (cadr-ai::models-equal-p left right)))

(defun sort-model-selector-models
    (models current-model)
  (stable-sort
   (copy-list models)
   (lambda (left right)
     (cond
       ((model-equal-p left current-model)
        (not
         (model-equal-p right current-model)))
       ((model-equal-p right current-model)
        nil)
       (t
        (string<
         (provider-key
          (cadr-ai:model-provider left))
         (provider-key
          (cadr-ai:model-provider right))))))))

(defstruct (model-selector-state
            (:constructor
                %make-model-selector-state))
  (all-models nil :type list)
  (scoped-models nil :type list)
  current-model
  (scope :all)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  refresh-status-message
  keybindings)

(defun model-selector-active-models (state)
  (if (eq :scoped
          (model-selector-state-scope state))
      (model-selector-state-scoped-models state)
      (model-selector-state-all-models state)))

(defun model-selector-visible-models (state)
  (let ((models
          (model-selector-active-models state))
        (query
          (model-selector-state-query state)))
    (if (zerop (length query))
        (copy-list models)
        (selector-fuzzy-filter
         models query
         #'model-selector-search-text))))

(defun model-selector-clamp-selected (state)
  (let ((count
          (length
           (model-selector-visible-models state))))
    (setf
     (model-selector-state-selected state)
     (if (zerop count)
         0
         (min
          (model-selector-state-selected state)
          (1- count)))))
  state)

(defun model-selector-select-current (state)
  (let* ((models
           (model-selector-visible-models state))
         (index
           (position
            (model-selector-state-current-model state)
            models
            :test #'model-equal-p)))
    (setf
     (model-selector-state-selected state)
     (or index 0)))
  state)

(defun make-model-selector-state
    (&key all-models scoped-models
       current-model refresh-status-message
       keybindings)
  (let ((state
          (%make-model-selector-state
           :all-models
           (sort-model-selector-models
            all-models current-model)
           :scoped-models
           (copy-list scoped-models)
           :current-model current-model
           :refresh-status-message
           refresh-status-message
           :scope
           (if scoped-models :scoped :all)
           :keybindings
           (or keybindings
               (make-models-selector-keybindings)))))
    (model-selector-select-current state)))

(defun model-selector-selected-model (state)
  (nth
   (model-selector-state-selected state)
   (model-selector-visible-models state)))

(defun model-selector-set-query (state query)
  (setf
   (model-selector-state-query state)
   (or query ""))
  (if (plusp
       (length
        (model-selector-state-query state)))
      (setf
       (model-selector-state-selected state)
       0)
      (model-selector-clamp-selected state))
  state)

(defun model-selector-toggle-scope (state)
  (when (model-selector-state-scoped-models state)
    (setf
     (model-selector-state-scope state)
     (if
         (eq :all
             (model-selector-state-scope state))
         :scoped :all))
    (model-selector-select-current state)
    (when
        (plusp
         (length
          (model-selector-state-query state)))
      (setf
       (model-selector-state-selected state)
       0)))
  state)

(defun model-selector-move (state delta)
  (let ((count
          (length
           (model-selector-visible-models state))))
    (when (plusp count)
      (setf
       (model-selector-state-selected state)
       (mod
        (+ (model-selector-state-selected state)
           delta)
        count))))
  state)

(defun model-selector-key-p
    (state data name)
  (selector-keybinding-matches-p
   (model-selector-state-keybindings state)
   data name))

(defun model-selector-handle-raw-input
    (state data)
  (cond
    ((model-selector-key-p
      state data "tui.input.tab")
     (model-selector-toggle-scope state)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.up")
     (model-selector-move state -1)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.down")
     (model-selector-move state 1)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.pageUp")
     (model-selector-move state -10)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.pageDown")
     (model-selector-move state 10)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.confirm")
     (let ((model
             (model-selector-selected-model state)))
       (values
        (and model :select)
        model t)))
    ((model-selector-key-p
      state data "tui.select.cancel")
     (values :cancel nil t))
    (t
     (values nil nil nil))))

(defun selector-delete-query-character (query)
  (if (zerop (length query))
      query
      (subseq
       query 0
       (cadr-tui::previous-cluster-boundary
        query (length query)))))

(defun model-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:tab
     (model-selector-toggle-scope state)
     (values :changed nil))
    (:up
     (model-selector-move state -1)
     (values :changed nil))
    (:down
     (model-selector-move state 1)
     (values :changed nil))
    (:page-up
     (model-selector-move state -10)
     (values :changed nil))
    (:page-down
     (model-selector-move state 10)
     (values :changed nil))
    (:enter
     (let ((model
             (model-selector-selected-model state)))
       (values
        (and model :select)
        model)))
    ((:escape :interrupt)
     (values :cancel nil))
    (:backspace
     (model-selector-set-query
      state
      (selector-delete-query-character
       (model-selector-state-query state)))
     (values :changed nil))
    (:text
     (model-selector-set-query
      state
      (concatenate
       'string
       (model-selector-state-query state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun model-selector-visible-slice
    (state maximum)
  (let* ((models
           (model-selector-visible-models state))
         (selected
           (model-selector-state-selected state))
         (start
           (max
            0
            (min
             (- selected (floor maximum 2))
             (- (length models) maximum))))
         (end
           (min (+ start maximum)
                (length models))))
    (values
     (subseq models start end)
     start
     (length models))))

(defun render-model-selector (state width)
  (multiple-value-bind
        (models start total)
      (model-selector-visible-slice state 10)
    (let ((selected
            (model-selector-state-selected state))
          (current
            (model-selector-state-current-model state)))
      (append
       (append
        (list
         (selector-border-line width)
         ""
         (selector-fit-line
          (if
              (model-selector-state-scoped-models state)
              (let ((scoped-p
                      (eq :scoped
                          (model-selector-state-scope
                           state))))
                (concatenate
                 'string
                 (cadr-tui:theme-foreground
                  :muted "Scope: ")
                 (cadr-tui:theme-foreground
                  (if scoped-p :muted :accent)
                  "all")
                 (cadr-tui:theme-foreground
                  :muted " | ")
                 (cadr-tui:theme-foreground
                  (if scoped-p :accent :muted)
                  "scoped")))
              (cadr-tui:theme-foreground
               :warning
               "Only showing models from configured providers. Use /login to add providers."))
          width))
        (list
         ""
         (selector-fit-line
          (concatenate
           'string
           (cadr-tui:theme-foreground
            :muted "> ")
           (cadr-tui:theme-foreground
            :accent
            (model-selector-state-query state)))
          width)
         ""))
       (if models
           (loop
             for model in models
             for index from start
             for selected-p = (= index selected)
             for current-p =
               (model-equal-p model current)
             collect
             (selector-fit-line
              (concatenate
               'string
               (if selected-p
                   (cadr-tui:theme-foreground
                    :accent "→ ")
                   "  ")
               (if selected-p
                   (cadr-tui:theme-foreground
                    :accent
                    (cadr-ai:model-id model))
                   (cadr-ai:model-id model))
               " "
               (cadr-tui:theme-foreground
                :muted
                (format nil "[~(~A~)]"
                        (cadr-ai:model-provider
                         model)))
               (if current-p
                   (cadr-tui:theme-foreground
                    :success " ✓")
                   ""))
              width))
           (list
            (selector-muted-line
             "  No matching models" width)))
       (when (> total (length models))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)"
                   (1+ selected) total)
           width)))
       (when
           (and models
                (model-selector-selected-model state))
         (list
          ""
          (selector-muted-line
           (format
            nil "  Model Name: ~A"
            (cadr-ai::model-name
             (model-selector-selected-model state)))
           width)))
       (when
           (model-selector-state-refresh-status-message
            state)
         (list
          ""
          (selector-fit-line
           (cadr-tui:theme-foreground
            :success
            (format
             nil "  ~A"
             (model-selector-state-refresh-status-message
              state)))
           width)))
       (list
        ""
        (selector-border-line width))))))

(defstruct (scoped-models-selector-state
            (:constructor
                %make-scoped-models-selector-state))
  (all-models nil :type list)
  (all-ids nil :type list)
  (enabled-ids :all)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  (dirty-p nil :type boolean)
  change-callback
  persist-callback
  cancel-callback
  keybindings)

(defun scoped-models-copy-enabled (enabled)
  (if (eq enabled :all)
      :all
      (copy-list enabled)))

(defun scoped-models-model-by-id
    (state id)
  (find
   id
   (scoped-models-selector-state-all-models state)
   :key #'qualified-model-id
   :test #'string=))

(defun scoped-model-id-enabled-p
    (state id)
  (or
   (eq :all
       (scoped-models-selector-state-enabled-ids
        state))
   (member
    id
    (scoped-models-selector-state-enabled-ids
     state)
    :test #'string=)))

(defun scoped-models-sorted-ids (state)
  (let ((enabled
          (scoped-models-selector-state-enabled-ids
           state))
        (all
          (scoped-models-selector-state-all-ids
           state)))
    (if (eq enabled :all)
        (copy-list all)
        (append
         (copy-list enabled)
         (remove-if
          (lambda (id)
            (member id enabled :test #'string=))
          all)))))

(defun scoped-models-selector-items (state)
  (loop
    for id in (scoped-models-sorted-ids state)
    collect
    (list
     :id id
     :model
     (scoped-models-model-by-id state id)
     :enabled-p
     (not
      (null
       (scoped-model-id-enabled-p state id))))))

(defun scoped-model-item-search-text (item)
  (let ((model (getf item :model)))
    (if model
        (scoped-model-selector-search-text
         model)
        (getf item :id))))

(defun scoped-models-selector-visible-items
    (state)
  (let ((items
          (scoped-models-selector-items state))
        (query
          (scoped-models-selector-state-query
           state)))
    (if (zerop (length query))
        items
        (selector-fuzzy-filter
         items query
         #'scoped-model-item-search-text))))

(defun scoped-models-selector-clamp-selected
    (state)
  (let ((count
          (length
           (scoped-models-selector-visible-items
            state))))
    (setf
     (scoped-models-selector-state-selected state)
     (if (zerop count)
         0
         (min
          (scoped-models-selector-state-selected
           state)
          (1- count)))))
  state)

(defun make-scoped-models-selector-state
    (&key all-models
       (enabled-ids :all)
       change-callback
       persist-callback
       cancel-callback
       keybindings)
  (%make-scoped-models-selector-state
   :all-models (copy-list all-models)
   :all-ids
   (mapcar #'qualified-model-id all-models)
   :enabled-ids
   (scoped-models-copy-enabled enabled-ids)
   :change-callback change-callback
   :persist-callback persist-callback
   :cancel-callback cancel-callback
   :keybindings
   (or keybindings
       (make-models-selector-keybindings))))

(defun scoped-models-selector-selected-item
    (state)
  (nth
   (scoped-models-selector-state-selected state)
   (scoped-models-selector-visible-items state)))

(defun scoped-models-selector-select-id
    (state id)
  (let ((position
          (position
           id
           (scoped-models-selector-visible-items state)
           :key
           (lambda (item)
             (getf item :id))
           :test #'string=)))
    (when position
      (setf
       (scoped-models-selector-state-selected state)
       position)))
  state)

(defun scoped-models-selector-notify-change
    (state)
  (when
      (scoped-models-selector-state-change-callback
       state)
    (funcall
     (scoped-models-selector-state-change-callback
      state)
     (scoped-models-copy-enabled
      (scoped-models-selector-state-enabled-ids
       state))))
  state)

(defun scoped-models-selector-mark-changed
    (state)
  (setf
   (scoped-models-selector-state-dirty-p state)
   t)
  (scoped-models-selector-clamp-selected state)
  (scoped-models-selector-notify-change state))

(defun scoped-models-toggle-id (enabled id)
  (cond
    ((eq enabled :all)
     (list id))
    ((member id enabled :test #'string=)
     (remove id enabled :test #'string=))
    (t
     (append enabled (list id)))))

(defun all-known-model-ids-enabled-p
    (enabled all-ids)
  (and
   (listp enabled)
   (= (length enabled)
      (length all-ids))
   (every
    (lambda (id)
      (member id all-ids :test #'string=))
    enabled)))

(defun scoped-models-enable-ids
    (enabled all-ids targets)
  (when (eq enabled :all)
    (return-from scoped-models-enable-ids
      :all))
  (let ((result (copy-list enabled)))
    (dolist (id targets)
      (unless (member id result :test #'string=)
        (setf result
              (append result (list id)))))
    (if (all-known-model-ids-enabled-p
         result all-ids)
        :all
        result)))

(defun scoped-models-clear-ids
    (enabled all-ids targets)
  (if (eq enabled :all)
      (remove-if
       (lambda (id)
         (member id targets :test #'string=))
       all-ids)
      (remove-if
       (lambda (id)
         (member id targets :test #'string=))
       enabled)))

(defun scoped-models-selector-toggle-selected
    (state)
  (let ((item
          (scoped-models-selector-selected-item
           state)))
    (when item
      (setf
       (scoped-models-selector-state-enabled-ids
        state)
       (scoped-models-toggle-id
        (scoped-models-selector-state-enabled-ids
         state)
        (getf item :id)))
      (scoped-models-selector-mark-changed
       state)))
  state)

(defun scoped-models-selector-target-ids
    (state)
  (if
      (plusp
       (length
        (scoped-models-selector-state-query
         state)))
      (mapcar
       (lambda (item)
         (getf item :id))
       (scoped-models-selector-visible-items
        state))
      (copy-list
       (scoped-models-selector-state-all-ids
        state))))

(defun scoped-models-selector-enable-all
    (state)
  (setf
   (scoped-models-selector-state-enabled-ids state)
   (scoped-models-enable-ids
    (scoped-models-selector-state-enabled-ids
     state)
    (scoped-models-selector-state-all-ids state)
    (scoped-models-selector-target-ids state)))
  (scoped-models-selector-mark-changed state))

(defun scoped-models-selector-clear-all
    (state)
  (setf
   (scoped-models-selector-state-enabled-ids state)
   (scoped-models-clear-ids
    (scoped-models-selector-state-enabled-ids
     state)
    (scoped-models-selector-state-all-ids state)
    (scoped-models-selector-target-ids state)))
  (scoped-models-selector-mark-changed state))

(defun scoped-models-selector-toggle-provider
    (state)
  (let* ((item
           (scoped-models-selector-selected-item
            state))
         (model (and item (getf item :model))))
    (when model
      (let* ((provider
               (cadr-ai:model-provider model))
             (ids
               (loop
                 for candidate in
                 (scoped-models-selector-state-all-models
                  state)
                 when
                   (eq provider
                       (cadr-ai:model-provider
                        candidate))
                   collect
                   (qualified-model-id
                    candidate)))
             (enabled
               (scoped-models-selector-state-enabled-ids
                state))
             (all-enabled-p
               (every
                (lambda (id)
                  (or
                   (eq enabled :all)
                   (member id enabled
                           :test #'string=)))
                ids)))
        (setf
         (scoped-models-selector-state-enabled-ids
          state)
         (if all-enabled-p
             (scoped-models-clear-ids
              enabled
              (scoped-models-selector-state-all-ids
               state)
              ids)
             (scoped-models-enable-ids
              enabled
              (scoped-models-selector-state-all-ids
               state)
              ids)))
        (scoped-models-selector-mark-changed
         state))))
  state)

(defun move-list-item (items index new-index)
  (if
      (or (< new-index 0)
          (>= new-index (length items)))
      (copy-list items)
      (let ((result (copy-list items)))
        (rotatef
         (nth index result)
         (nth new-index result))
        result)))

(defun scoped-models-selector-reorder
    (state delta)
  (let* ((enabled
           (scoped-models-selector-state-enabled-ids
            state))
         (item
           (scoped-models-selector-selected-item
            state))
         (id (and item (getf item :id))))
    (when
        (and
         (listp enabled)
         id
         (member id enabled :test #'string=))
      (let* ((index
               (position id enabled
                         :test #'string=))
             (new-index (+ index delta)))
        (when
            (and (>= new-index 0)
                 (< new-index (length enabled)))
          (setf
           (scoped-models-selector-state-enabled-ids
            state)
           (move-list-item
            enabled index new-index))
          (scoped-models-selector-mark-changed
           state)
          (scoped-models-selector-select-id
           state id)))))
  state)

(defun scoped-models-selector-persist (state)
  (when
      (scoped-models-selector-state-persist-callback
       state)
    (funcall
     (scoped-models-selector-state-persist-callback
      state)
     (scoped-models-copy-enabled
      (scoped-models-selector-state-enabled-ids
       state))))
  (setf
   (scoped-models-selector-state-dirty-p state)
   nil)
  state)

(defun scoped-models-selector-key-p
    (state data name)
  (selector-keybinding-matches-p
   (scoped-models-selector-state-keybindings state)
   data name))

(defun scoped-models-selector-handle-raw-input
    (state data)
  (labels
      ((changed (function)
         (funcall function state)
         (values :changed nil t)))
    (cond
      ((scoped-models-selector-key-p
        state data "app.models.reorderUp")
       (changed
        (lambda (state)
          (scoped-models-selector-reorder
           state -1))))
      ((scoped-models-selector-key-p
        state data "app.models.reorderDown")
       (changed
        (lambda (state)
          (scoped-models-selector-reorder
           state 1))))
      ((scoped-models-selector-key-p
        state data "app.models.enableAll")
       (changed
        #'scoped-models-selector-enable-all))
      ((scoped-models-selector-key-p
        state data "app.models.clearAll")
       (changed
        #'scoped-models-selector-clear-all))
      ((scoped-models-selector-key-p
        state data "app.models.toggleProvider")
       (changed
        #'scoped-models-selector-toggle-provider))
      ((scoped-models-selector-key-p
        state data "app.models.save")
       (changed
        #'scoped-models-selector-persist))
      ((scoped-models-selector-key-p
        state data
        "app.models.clearSearchOrCancel")
       (if
           (plusp
            (length
             (scoped-models-selector-state-query
              state)))
           (progn
             (setf
              (scoped-models-selector-state-query
               state)
              "")
             (scoped-models-selector-clamp-selected
              state)
             (values :changed nil t))
           (values :cancel nil t)))
      ((scoped-models-selector-key-p
        state data "tui.select.up")
       (scoped-models-selector-move state -1)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.down")
       (scoped-models-selector-move state 1)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.pageUp")
       (scoped-models-selector-move state -8)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.pageDown")
       (scoped-models-selector-move state 8)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.confirm")
       (changed
        #'scoped-models-selector-toggle-selected))
      ((scoped-models-selector-key-p
        state data "tui.select.cancel")
       (values :cancel nil t))
      (t
       (values nil nil nil)))))

(defun scoped-models-selector-move
    (state delta)
  (let ((count
          (length
           (scoped-models-selector-visible-items
            state))))
    (when (plusp count)
      (setf
       (scoped-models-selector-state-selected
        state)
       (mod
        (+
         (scoped-models-selector-state-selected
          state)
         delta)
        count))))
  state)

(defun scoped-models-selector-set-query
    (state query)
  (setf
   (scoped-models-selector-state-query state)
   (or query ""))
  (scoped-models-selector-clamp-selected state))

(defun scoped-models-selector-cancel (state)
  (when
      (scoped-models-selector-state-cancel-callback
       state)
    (funcall
     (scoped-models-selector-state-cancel-callback
      state)))
  state)

(defun scoped-models-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:up
     (scoped-models-selector-move state -1)
     (values :changed nil))
    (:down
     (scoped-models-selector-move state 1)
     (values :changed nil))
    (:page-up
     (scoped-models-selector-move state -8)
     (values :changed nil))
    (:page-down
     (scoped-models-selector-move state 8)
     (values :changed nil))
    (:enter
     (scoped-models-selector-toggle-selected state)
     (values :changed nil))
    (:escape
     (scoped-models-selector-cancel state)
     (values :cancel nil))
    (:interrupt
     (if
         (plusp
          (length
           (scoped-models-selector-state-query
            state)))
         (progn
           (scoped-models-selector-set-query
            state "")
           (values :changed nil))
         (progn
           (scoped-models-selector-cancel state)
           (values :cancel nil))))
    (:backspace
     (scoped-models-selector-set-query
      state
      (selector-delete-query-character
       (scoped-models-selector-state-query
        state)))
     (values :changed nil))
    (:text
     (scoped-models-selector-set-query
      state
      (concatenate
       'string
       (scoped-models-selector-state-query
        state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun session-scoped-models
    (all-models enabled-ids)
  (when (eq enabled-ids :all)
    (return-from session-scoped-models nil))
  (let* ((all-ids
           (mapcar #'qualified-model-id all-models))
         (available
           (loop
             for id in enabled-ids
             for model =
               (find id all-models
                     :key #'qualified-model-id
                     :test #'string=)
             when model
               collect model))
         (all-enabled-p
           (every
            (lambda (id)
              (member id enabled-ids
                      :test #'string=))
            all-ids)))
    (if
        (and available
             (not all-enabled-p))
        available
        nil)))

(defun scoped-models-selector-counts (state)
  (let ((enabled
          (scoped-models-selector-state-enabled-ids
           state)))
    (if (eq enabled :all)
        (values
         (length
          (scoped-models-selector-state-all-ids
           state))
         0 t)
        (values
         (count-if
          (lambda (id)
            (member
             id
             (scoped-models-selector-state-all-ids
              state)
             :test #'string=))
          enabled)
         (count-if
          (lambda (id)
            (not
             (member
              id
              (scoped-models-selector-state-all-ids
               state)
              :test #'string=)))
          enabled)
         nil))))

(defun scoped-models-binding-label
    (state name)
  (or
   (first
    (cadr-tui:keybinding-keys
     (scoped-models-selector-state-keybindings
      state)
     name))
   name))

(defun render-scoped-models-selector
    (state width)
  (let* ((items
           (scoped-models-selector-visible-items
            state))
         (selected
           (scoped-models-selector-state-selected
            state))
         (maximum 8)
         (start
           (max
            0
            (min
             (- selected (floor maximum 2))
             (- (length items) maximum))))
         (end
           (min (+ start maximum)
                (length items)))
         (visible
           (subseq items start end)))
    (multiple-value-bind
          (enabled unavailable all-p)
        (scoped-models-selector-counts state)
      (append
       (list
        (selector-border-line width)
        ""
        (selector-title-line
         "Model Configuration" width)
        (selector-muted-line
         (format
          nil "Session-only. ~A to save to settings."
          (scoped-models-binding-label
           state "app.models.save"))
         width)
        ""
        (selector-fit-line
         (concatenate
          'string
          (cadr-tui:theme-foreground
           :muted "> ")
          (cadr-tui:theme-foreground
           :accent
           (scoped-models-selector-state-query
            state)))
         width)
        "")
       (if visible
           (loop
             for item in visible
             for index from start
             for model = (getf item :model)
             for selected-p = (= index selected)
             for identifier =
               (if model
                   (cadr-ai:model-id model)
                   (getf item :id))
             for provider =
               (if model
                   (provider-key
                    (cadr-ai:model-provider model))
                   "unavailable")
             for status =
               (cond
                 ((null model)
                  (cadr-tui:theme-foreground
                   :dim " ✗"))
                 (all-p "")
                 ((getf item :enabled-p)
                  (cadr-tui:theme-foreground
                   :success " ✓"))
                 (t
                  (cadr-tui:theme-foreground
                   :dim " ✗")))
             for line =
               (concatenate
                'string
                (if selected-p
                    (cadr-tui:theme-foreground
                     :accent "→ ")
                    "  ")
                (if selected-p
                    (cadr-tui:theme-foreground
                     :accent identifier)
                    identifier)
                (cadr-tui:theme-foreground
                 :muted
                 (format nil " [~A]" provider))
                status)
             collect
               (selector-fit-line line width))
           (list
            (selector-muted-line
             "  No matching models" width)))
       (when
           (or (> start 0)
               (< end (length items)))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)"
                   (1+ selected)
                   (length items))
           width)))
       (when visible
         (let* ((item
                  (scoped-models-selector-selected-item
                   state))
                (model
                  (and item
                       (getf item :model))))
           (list
            ""
            (selector-muted-line
             (format
              nil "  ~A"
              (if model
                  (format nil "Model Name: ~A"
                          (cadr-ai::model-name
                           model))
                  "Model unavailable"))
             width))))
       (list
        ""
        (selector-fit-line
         (concatenate
          'string
          (cadr-tui:theme-foreground
           :dim
           (format
            nil
            "~A toggle · ~A all · ~A clear · ~A provider · ~A/~A reorder · ~A save · ~A"
            (scoped-models-binding-label
             state "tui.select.confirm")
            (scoped-models-binding-label
             state "app.models.enableAll")
            (scoped-models-binding-label
             state "app.models.clearAll")
            (scoped-models-binding-label
             state "app.models.toggleProvider")
            (scoped-models-binding-label
             state "app.models.reorderUp")
            (scoped-models-binding-label
             state "app.models.reorderDown")
            (scoped-models-binding-label
             state "app.models.save")
            (if all-p
                "all enabled"
                (format
                 nil "~D/~D enabled~@[ · ~D unavailable~]"
                 enabled
                 (length
                  (scoped-models-selector-state-all-ids
                   state))
                 (and (plusp unavailable)
                      unavailable)))))
          (if
              (scoped-models-selector-state-dirty-p
               state)
              (cadr-tui:theme-foreground
               :warning " (unsaved)")
              ""))
         width)
        (selector-border-line width))))))

(defstruct (tool-render-session
            (:constructor make-tool-render-session
                (&key name arguments
                      call-renderer
                      result-renderer)))
  name
  arguments
  call-renderer
  result-renderer
  (state (make-hash-table :test #'equal))
  result
  (pending-p t :type boolean))

(defun update-tool-render-session
    (session result &key pending-p)
  (setf
   (tool-render-session-result session)
   result
   (tool-render-session-pending-p session)
   (not (null pending-p)))
  session)

(defun render-tool-session (session)
  (let ((call
          (if
              (tool-render-session-call-renderer
               session)
              (funcall
               (tool-render-session-call-renderer
                session)
               (tool-render-session-arguments session)
               (tool-render-session-state session))
              (format nil "~A ~S"
                      (tool-render-session-name session)
                      (tool-render-session-arguments
                       session))))
        (result
          (and
           (not
            (tool-render-session-pending-p
             session))
           (tool-render-session-result session)
           (if
               (tool-render-session-result-renderer
                session)
               (funcall
                (tool-render-session-result-renderer
                 session)
                (tool-render-session-result session)
                (tool-render-session-arguments
                 session)
                (tool-render-session-state session))
               (princ-to-string
                (tool-render-session-result
                 session))))))
    (remove
     ""
     (remove nil (list call result))
     :test #'string=)))
