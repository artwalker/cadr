(in-package #:cadr-cli)

(defstruct oauth-selector-option
  id
  name
  auth-type
  method-name
  login-label
  status
  structured-login-p)

(defstruct (login-method-selector-state
            (:constructor
                %make-login-method-selector-state))
  (title "Select authentication method:" :type string)
  select-list)

(defun make-login-method-selector-state
    (&key
       (title "Select authentication method:")
       (items
         (list
          (cadr-tui:make-select-item
           :label "Sign in with an account"
           :value :oauth)
          (cadr-tui:make-select-item
           :label "Sign in with an API key"
           :value :api-key))))
  (%make-login-method-selector-state
   :title title
   :select-list
   (cadr-tui:make-select-list
    :items items
    :height (length items)
    :show-filter-p nil)))

(defun login-auth-type-route
    (provider-options &key generic-p)
  (when generic-p
    (return-from login-auth-type-route
      (values :select (make-login-method-selector-state))))
  (let* ((oauth
           (find :oauth provider-options
                 :key #'oauth-selector-option-auth-type))
         (api-key
           (find :api-key provider-options
                 :key #'oauth-selector-option-auth-type))
         (options (remove nil (list oauth api-key))))
    (case (length options)
      (0
       (values :none "No login methods available."))
      (1
       (values :direct (first options)))
      (otherwise
       (values
        :select
        (make-login-method-selector-state
         :title
         (format nil "Select authentication method for ~A:"
                 (oauth-selector-option-name (first options)))
         :items
         (loop for option in options
               collect
               (cadr-tui:make-select-item
                :label
                (if (eq :oauth
                        (oauth-selector-option-auth-type option))
                    (or (oauth-selector-option-login-label option)
                        "Sign in with an account")
                    "Sign in with an API key")
                :value option))))))))

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
  (let* ((select-list
           (login-method-selector-state-select-list state))
         (items
           (cadr-tui::select-list-filtered-items select-list))
         (selected
           (if items
               (min (cadr-tui::select-list-selected select-list)
                    (1- (length items)))
               0))
         (keybindings (cadr-tui:get-keybindings)))
    (render-selector-frame
     (make-selector-frame
      :sections
      (list
       (list :border :border)
       :blank
       (list :title
             (login-method-selector-state-title state)
             :overlay)
       :blank
       (list
        :lines
        (loop for item in items
              for index from 0
              for selected-p = (= index selected)
              collect
              (selector-component-text-line
               (concatenate
                'string
                (if selected-p
                    (cadr-tui:theme-foreground :accent "→ ")
                    "  ")
                (cadr-tui:theme-foreground
                 (if selected-p :accent :text)
                 (cadr-tui:select-item-label item)))
               width)))
       :blank
       (list
        :lines
        (component-text-lines
         (concatenate
          'string
          (raw-key-hint "↑↓" "navigate") "  "
          (selector-keybinding-hint
           keybindings "tui.select.confirm" "select") "  "
          (selector-keybinding-hint
           keybindings "tui.select.cancel" "cancel"))
         width))
       :blank
       (list :border :border)))
     width)))

(defstruct (api-key-input-state
            (:constructor
                %make-api-key-input-state))
  option
  input)

(cadr-core:define-redacted-print-object
    (api-key-input-state value stream)
  (format stream ":provider ~A :input [REDACTED]"
          (oauth-selector-option-id
           (api-key-input-state-option value))))

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
      (render-selector-frame
       (make-selector-frame
        :sections
        (list
         (list :border :border)
         (list
          :title
          (format nil "Login to ~A"
                  (oauth-selector-option-name option))
          :overlay)
         :blank
         (list
         :lines
          (list
           (selector-component-text-line
            (cadr-tui:theme-foreground
             :text
             "Enter API key")
            width)))
         (list :component input-lines row column)
         (list
          :lines
          (list
           (selector-component-text-line
            (format
             nil "(~A ~A)"
             (selector-keybinding-hint
              (cadr-tui:get-keybindings)
              "tui.select.cancel" "to cancel,")
             (selector-keybinding-hint
              (cadr-tui:get-keybindings)
              "tui.select.confirm" "to submit"))
            width)))
         (list :border :border)))
       width))))

(defstruct (oauth-selector-state
            (:constructor
                %make-oauth-selector-state))
  (mode :login :type symbol)
  (options nil :type list)
  (filtered-options nil :type list)
  (selected 0 :type (integer 0 *))
  (query "" :type string)
  keybindings)

(defparameter +login-selector-hidden-providers+
  '(:kimi-coding)
  "Built-in providers kept in the registry but not offered by /login.")

(defun login-selector-hidden-p (provider-id)
  (and provider-id
       (member provider-id +login-selector-hidden-providers+)))

(defun login-provider-options
    (definitions &key auth-type status-function)
  (stable-sort
   (loop
     for definition in definitions
     unless
       (login-selector-hidden-p
        (cadr-ai:provider-definition-id definition))
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
          :login-label
          (let ((metadata
                  (and
                   (eq candidate :oauth)
                   (cadr-ai:provider-definition-oauth-metadata
                    definition))))
            (and metadata
                 (cadr-ai:oauth-provider-metadata-login-label
                  metadata)))
          :status
          (and status-function
               (funcall
                status-function
                (cadr-ai:provider-definition-id
                 definition)))
          :structured-login-p
          (and
           (eq candidate :api-key)
           (cadr-ai:provider-definition-structured-api-key-login-p
            definition)))))
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
    (setf
     (oauth-selector-state-selected state)
     (selector-frame-move-index
      (oauth-selector-state-selected state)
      count delta)))
  state)

(defun oauth-selector-selection (state)
  (nth
   (oauth-selector-state-selected state)
   (oauth-selector-state-filtered-options state)))

(defun oauth-environment-source-p (source)
  (and
   (stringp source)
   (not
    (null
     (cl-ppcre:scan
      "^[A-Z][A-Z0-9_]*(?:, [A-Z][A-Z0-9_]*)*$"
      source)))))

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
        :muted
        (concatenate 'string " " label)
        :enabled-p t))
      ((and type
            (not (eq type
                     (oauth-selector-option-auth-type option))))
       (concatenate
        'string
        (cadr-tui:theme-foreground
         :muted " • " :enabled-p t)
        (cadr-tui:theme-foreground
         :warning (subseq label 2) :enabled-p t)))
      (t
       (cadr-tui:theme-foreground
        :success
        (concatenate 'string " " label)
        :enabled-p t)))))

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
    (render-selector-frame
     (make-selector-frame
      :items options
      :selected selected
      :maximum 8
      :sections
      (list
       (list :border :border)
       :blank
       (list
        :title
        (if (eq (oauth-selector-state-mode state) :logout)
            "Select provider to logout:"
            "Select provider to configure:")
        :overlay)
       :blank
       (list :input (oauth-selector-state-query state))
       :blank :viewport :count :blank
       (list :border :border))
      :item-renderer
      (lambda (option index selected-p total item-width)
        (declare (ignore index total))
        (let* ((prefix
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
          (selector-component-text-line
           (concatenate
            'string prefix name auth-type
            (oauth-option-status-rendered option))
           item-width)))
      :count-renderer
      (lambda (current total item-width)
        (list
         (selector-component-text-line
          (cadr-tui:theme-foreground
           :muted
           (format nil "  (~D/~D)" (1+ current) total))
          item-width)))
      :empty-renderer
      (lambda (item-width total)
        (declare (ignore total))
        (list
         (selector-component-text-line
          (cadr-tui:theme-foreground
           :muted
           (cond
             ((plusp (length
                      (oauth-selector-state-options state)))
              "  No matching providers")
             ((eq (oauth-selector-state-mode state) :logout)
              "  No providers logged in. Use /login first.")
             (t "  No providers available")))
          item-width))))
     width)))
