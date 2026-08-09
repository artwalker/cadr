(in-package #:cadr-cli)

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
   ;; Baseline session-selector-search.ts: the haystack is
   ;; `${id} ${name ?? ""} ${allMessagesText} ${cwd}`.
   (format nil "~A ~@[~A ~]~A ~@[~A~]"
           (session-search-record-id record)
           (session-search-record-name record)
           (session-search-record-all-messages-text
            record)
           (and
            (session-search-record-cwd record)
            (etypecase
                (session-search-record-cwd record)
              (string (session-search-record-cwd record))
              (pathname
               (namestring
                (session-search-record-cwd record))))))))

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

(defparameter +session-selector-keybinding-definitions+
  (append
   (copy-tree
    cadr-tui::+tui-keybinding-definitions+)
   '(("app.session.toggleNamedFilter" . ("ctrl+n"))
     ("app.session.togglePath" . ("ctrl+p"))
     ("app.session.toggleSort" . ("ctrl+s"))
     ("app.session.rename" . ("ctrl+r"))
     ("app.session.delete" . ("ctrl+d"))
     ("app.session.deleteNoninvasive"
      . ("ctrl+backspace")))))

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
         ;; Baseline session-manager.ts: the search corpus holds user
         ;; and assistant texts only (tool results are skipped), and
         ;; firstMessage is the first user message with text.
         (user-texts
           (loop for message in messages
                 when (typep message 'cadr-ai:user-message)
                 collect (session-message-search-text message)))
         (corpus-texts
           (loop for message in messages
                 when (typep message
                             '(or cadr-ai:user-message
                               cadr-ai:assistant-message))
                 collect (session-message-search-text message))))
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
       user-texts)
     :message-count (length messages)
     :modified
     (or (cadr-agent::session-modified-timestamp
          session)
         (cadr-agent:session-timestamp session)
         0)
     :all-messages-text
      (format nil "~{~A~^~%~}" corpus-texts)
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
    (setf
     (session-selector-state-selected selector)
     (selector-frame-move-index
      (session-selector-state-selected selector)
      count delta)))
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
              ""))))
      (if (plusp (length text))
          text
          ;; Baseline session-manager.ts: firstMessage falls back to
          ;; "(no messages)", and the selector shows
          ;; name ?? firstMessage verbatim.
          "(no messages)")))))

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

(defun render-session-selector (selector width)
  (when
      (eq :rename
          (session-selector-state-mode selector))
    (return-from render-session-selector
      (multiple-value-bind (input-lines input-row input-column)
          (selector-input-rendering
           (session-selector-state-rename-input selector)
           width)
        (render-selector-frame
         (make-selector-frame
          :sections
          (list
           :blank
           (list :border :accent)
           :blank
           (list :title "Rename Session" :plain)
           :blank
           (list :component input-lines input-row input-column)
           :blank
           (list
            :help
            (list
             (format nil "~A to save · ~A to cancel"
                     (selector-keybinding-text
                      (session-selector-state-keybindings selector)
                      "tui.select.confirm")
                     (selector-keybinding-text
                      (session-selector-state-keybindings selector)
                      "tui.select.cancel")))
            :muted)
           :blank
           (list :border :accent)))
         width))))
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
       (let* ((keybindings
                (session-selector-state-keybindings selector))
              (confirm-hint
                (concatenate
                 'string
                 "Delete session? "
                 (selector-keybinding-hint
                  keybindings "tui.select.confirm" "confirm")
                 " · "
                 (selector-keybinding-hint
                  keybindings "tui.select.cancel" "cancel"))))
         (setf
          hint-1
          (cadr-tui:theme-foreground
           :error
           (cadr-tui:truncate-to-width
            confirm-hint width "…"))
          hint-2 "")))
      ((session-selector-state-status-message selector)
       (setf
        hint-1
        (cadr-tui:theme-foreground
         :accent
         (session-selector-state-status-message
          selector))
        hint-2 ""))
      (t
       (let* ((keybindings
                (session-selector-state-keybindings selector))
              (separator
                (cadr-tui:theme-foreground :muted " · "))
              (hint-2-parts
                (append
                 (list
                  (selector-keybinding-hint
                   keybindings "app.session.toggleSort" "sort")
                  (selector-keybinding-hint
                   keybindings "app.session.toggleNamedFilter" "named")
                  (selector-keybinding-hint
                   keybindings "app.session.delete" "delete")
                  (selector-keybinding-hint
                   keybindings "app.session.togglePath"
                   (format
                    nil "path (~A)"
                    (if
                        (session-selector-state-show-path-p selector)
                        "on" "off"))))
                 (when
                     (session-selector-state-show-rename-hint-p
                      selector)
                   (list
                    (selector-keybinding-hint
                     keybindings "app.session.rename" "rename"))))))
         (setf
          hint-1
          (concatenate
           'string
           (selector-keybinding-hint
            keybindings "tui.input.tab" "scope")
           separator
           (cadr-tui:theme-foreground
            :muted "re:<pattern> regex · \"phrase\" exact"))
          hint-2
          (if hint-2-parts
              (reduce
               (lambda (left right)
                 (concatenate 'string left separator right))
               hint-2-parts)
              "")))))
    (let ((lines
            (render-selector-frame
             (make-selector-frame
      :sections
      (list
       (list
        :lines
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
        (selector-fit-line
         (cadr-tui:truncate-to-width hint-1 width "…") width)
        (selector-fit-line
         (cadr-tui:truncate-to-width hint-2 width "…") width)
        ""
        (first
         (nth-value
          0
          (selector-input-rendering
           (session-selector-state-query selector)
           width)))
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
             for confirming-delete-p =
               (same-session-path-p
                (session-search-record-path record)
                (session-selector-state-confirming-delete-path
                 selector))
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
               (let ((colored-label
                       (cond
                         (confirming-delete-p
                          (cadr-tui:theme-foreground
                           :error fitted-label))
                         (current-p
                          (cadr-tui:theme-foreground
                           :accent fitted-label))
                         (name-p
                          (cadr-tui:theme-foreground
                           :warning fitted-label))
                         (t fitted-label))))
                 (if selected-p
                     (cadr-tui:theme-bold colored-label)
                     colored-label))
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
                 (if confirming-delete-p :error :dim)
                 right-part))
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
                 (selector-border-line width :accent)))))))
             width)))
      (values
       lines 7
       (min (max 0 (1- width))
            (+ 2
               (cadr-tui:visible-width
                (session-selector-state-query selector))))))))
