(in-package #:cadr-cli)

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
  (list-origin nil)
  (mouse-pressed nil)
  (mode :main :type symbol)
  (submenu-selected 0 :type (integer 0 *))
  (submenu-query "" :type string)
  (theme-names nil :type list)
  (available-models nil :type list)
  (model-thinking-key nil :type (or null string))
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
       (terminal-theme :dark)
       (available-models nil))
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
                (cadr-tui:make-keybindings-manager))
            :available-models
            (copy-list available-models))))
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
    (setf
     (settings-selector-state-selected state)
     (selector-frame-move-index
      (settings-selector-state-selected state)
      count delta)))
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


(defun settings-model-thinking-main-option (state)
  (find "model-thinking"
        (settings-selector-state-options state)
        :key #'settings-option-id
        :test #'string=))

(defun settings-model-thinking-item-label (model)
  (concatenate
   'string
   (cadr-ai:model-id model)
   " "
   (cadr-tui:theme-foreground
    :muted
    (format nil "[~(~A~)]"
            (cadr-ai:model-provider model)))))

(defun settings-model-thinking-sort-models (models current-model default-provider default-model)
  (stable-sort
   (copy-list models)
   (lambda (left right)
     ;; labels: default-p calls key (flet bindings are not mutually visible).
     (labels ((key (model)
                (model-setting-key
                 (cadr-ai:model-provider model)
                 (cadr-ai:model-id model)))
              (default-p (model)
                (and default-provider default-model
                     (string=
                      (key model)
                      (model-setting-key default-provider default-model))))
              (current-p (model)
                (and current-model
                     (cadr-ai:models-equal-p model current-model))))
       (cond
         ((current-p left) (not (current-p right)))
         ((current-p right) nil)
         ((default-p left) (not (default-p right)))
         ((default-p right) nil)
         (t
          (string<
           (provider-key (cadr-ai:model-provider left))
           (provider-key (cadr-ai:model-provider right)))))))))

(defun settings-model-thinking-model-options (state)
  (let* ((main (settings-model-thinking-main-option state))
         (value (and main (settings-option-value main)))
         (models
           (settings-model-thinking-sort-models
            (settings-selector-state-available-models state)
            (getf value :current-model)
            (getf value :default-provider)
            (getf value :default-model)))
         (overrides (getf value :overrides)))
    (if models
        (loop for model in models
              for model-key =
                (model-setting-key
                 (cadr-ai:model-provider model)
                 (cadr-ai:model-id model))
              for override = (cdr (assoc model-key overrides :test #'string=))
              collect
              (make-settings-option
               :id model-key
               :label (settings-model-thinking-item-label model)
               :description
               (and override (settings-display-value override))
               :value model-key))
        (list
         (make-settings-option
          :id "__none__"
          :label "No models available"
          :description
          "Log in to a provider or configure an API key first"
          :value "__none__")))))

(defun settings-model-thinking-level-options (state)
  (let* ((model-key (settings-selector-state-model-thinking-key state))
         (model
           (find model-key
                 (settings-selector-state-available-models state)
                 :key
                 (lambda (candidate)
                   (model-setting-key
                    (cadr-ai:model-provider candidate)
                    (cadr-ai:model-id candidate)))
                 :test #'string=))
         (main (settings-model-thinking-main-option state))
         (value (and main (settings-option-value main)))
         (overrides (getf value :overrides))
         (global-default (getf value :global-default)))
    (when model
      (let* ((levels
               (if (cadr-ai:model-reasoning-p model)
                   (cadr-ai:supported-thinking-levels model)
                   '(:off)))
             (items
               (loop for level in levels
                     collect
                     (make-settings-option
                      :id (string-downcase (symbol-name level))
                      :label (string-downcase (symbol-name level))
                      :description (settings-thinking-description level)
                      :value level))))
        (when (assoc model-key overrides :test #'string=)
          (setf items
                (append items
                        (list
                         (make-settings-option
                          :id "clear-override"
                          :label "(clear override)"
                          :description
                          (format nil "Revert to global default (~A)"
                                    (settings-display-value
                                     (or global-default :medium)))
                          :value :clear)))))
        items))))

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

(defun settings-selector-searchable-submenu-p (state)
  (eq (settings-selector-state-mode state) :model-thinking))

(defun settings-selector-reset-submenu-query (state)
  (setf (settings-selector-state-submenu-query state) ""
        (settings-selector-state-submenu-selected state) 0)
  state)

(defun settings-selector-open-submenu (state option)
  (setf (settings-selector-state-submenu-selected state) 0
        (settings-selector-state-submenu-query state) "")
  (case (settings-option-submenu option)
    (:warnings
     (setf (settings-selector-state-mode state) :warnings))
    (:model-thinking
     (setf (settings-selector-state-mode state) :model-thinking))
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
    (:model-thinking
     (let ((options (settings-model-thinking-model-options state))
           (query (settings-selector-state-submenu-query state)))
       (if (plusp (length query))
           (selector-fuzzy-filter
            options query
            (lambda (option)
              (format nil "~A ~A"
                      (or (settings-option-label option) "")
                      (or (settings-option-description option) ""))))
           options)))
    (:model-thinking-level
     (settings-model-thinking-level-options state))
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
    (setf
     (settings-selector-state-submenu-selected state)
     (selector-frame-move-index
      (settings-selector-state-submenu-selected state)
      count delta)))
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
          (:model-thinking
           (unless (string= (settings-option-id option) "__none__")
             (setf (settings-selector-state-model-thinking-key state)
                   (settings-option-value option)
                   (settings-selector-state-mode state)
                   :model-thinking-level)
             (settings-selector-reset-submenu-query state)))
          (:model-thinking-level
           (let* ((model-key
                    (settings-selector-state-model-thinking-key state))
                  (level (settings-option-value option))
                  (main (settings-model-thinking-main-option state)))
             (setf change
                   (settings-selector-notify-change
                    state "model-thinking-level"
                    (list :model-key model-key :level level)))
             (when main
               (let* ((value (copy-list (settings-option-value main)))
                      (overrides (copy-list (getf value :overrides))))
                 (if (eq level :clear)
                     (setf overrides
                           (remove model-key overrides
                                   :key #'car :test #'string=))
                     (setf overrides
                           (append
                            (remove model-key overrides
                                    :key #'car :test #'string=)
                            (list (cons model-key level)))))
                 (setf (getf value :overrides) overrides
                       (settings-option-value main) value)))
             (setf (settings-selector-state-mode state) :model-thinking)
             (settings-selector-reset-submenu-query state)))
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
    (flet ((unwrap (updater)
             (multiple-value-bind (updated change)
                 (funcall updater)
               (declare (ignore updated))
               (return-from settings-selector-handle-event
                 (values :changed change)))))
      (return-from settings-selector-handle-event
        (case (cadr-tui:input-event-kind event)
          (:up
           (unwrap (lambda ()
                     (settings-selector-submenu-move state -1))))
          (:down
           (unwrap (lambda ()
                     (settings-selector-submenu-move state 1))))
          (:page-up
           (unwrap (lambda ()
                     (settings-selector-submenu-move state -10))))
          (:page-down
           (unwrap (lambda ()
                     (settings-selector-submenu-move state 10))))
          ((:enter :submit)
           (unwrap (lambda ()
                     (settings-selector-activate-submenu state))))
          (:backspace
           (if (settings-selector-searchable-submenu-p state)
               (progn
                 (setf (settings-selector-state-submenu-query state)
                       (selector-delete-query-character
                        (settings-selector-state-submenu-query state))
                       (settings-selector-state-submenu-selected state)
                       0)
                 (values :changed nil))
               (values nil nil)))
          (:text
           (let ((text
                   (or (cadr-tui:input-event-text event) "")))
             (cond
               ((settings-selector-searchable-submenu-p state)
                (when (plusp (length text))
                  (setf (settings-selector-state-submenu-query state)
                        (concatenate
                         'string
                         (settings-selector-state-submenu-query state)
                         text)
                        (settings-selector-state-submenu-selected state)
                        0))
                (values :changed nil))
               ((string= text " ")
                (unwrap (lambda ()
                          (settings-selector-activate-submenu state))))
               (t (values nil nil)))))
          ((:escape :cancel)
           (let ((mode (settings-selector-state-mode state))
                 (change nil))
             (cond
               ((eq mode :model-thinking-level)
                (setf (settings-selector-state-mode state)
                      :model-thinking)
                (settings-selector-reset-submenu-query state)
                (values :changed nil))
               ((member mode '(:theme-light :theme-dark))
                (setf (settings-selector-state-mode state)
                      :theme-automatic)
                (setf change
                      (list
                       :id "theme-preview"
                       :value
                       (settings-selector-automatic-theme-setting
                        state)))
                (values :changed change))
               (t
                (when (member mode
                              '(:theme-single :theme-automatic))
                  (setf change
                        (list
                         :id "theme-preview"
                         :value
                         (settings-selector-state-original-theme
                          state))))
                (settings-selector-close-submenu state)
                (settings-selector-reset-submenu-query state)
                (values :changed change)))))
          (otherwise (values nil nil))))))
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

(defun settings-selector-handle-mouse (state gesture local-y)
  (unless (and (eq :main (settings-selector-state-mode state))
               (integerp (settings-selector-state-list-origin state))
               (integerp local-y))
    (return-from settings-selector-handle-mouse nil))
  (let ((y (- local-y (settings-selector-state-list-origin state)))
        (options (settings-selector-visible-options state)))
    (when (minusp y)
      (return-from settings-selector-handle-mouse nil))
    (multiple-value-bind (next action)
        (cadr-tui:centered-list-mouse
         (length options)
         (settings-selector-state-selected state)
         10 y
         (getf gesture :type)
         (getf gesture :button)
         (getf gesture :wheel-delta)
         :pressed (settings-selector-state-mouse-pressed state))
      (case action
        (:wheel
         (setf (settings-selector-state-selected state) next)
         (values t nil nil))
        (:press
         (setf (settings-selector-state-mouse-pressed state) next
               (settings-selector-state-selected state) next)
         (values t nil nil))
        (:click
         (setf (settings-selector-state-selected state) next
               (settings-selector-state-mouse-pressed state) nil)
         (multiple-value-bind (kind value)
             (settings-selector-handle-event
              state (cadr-tui:make-input-event :kind :enter))
           (values t kind value)))
        (t nil)))))

(defun settings-selector-visible-slice
    (options selected maximum)
  (selector-frame-visible-slice
   options selected maximum))

(defun settings-selector-max-label-width (options)
  (min 30
       (loop for option in options
             maximize
             (cadr-tui:visible-width
              (settings-option-label option)))))

(defun render-settings-option-list
    (options all-options selected width maximum
     &key search-query search-p
       (include-input-p search-p))
  (multiple-value-bind (visible start end total)
      (settings-selector-visible-slice options selected maximum)
    (let ((label-width
            (if all-options
                (settings-selector-max-label-width all-options)
                1)))
      (append
       (when include-input-p
         (list
          (selector-input-line (or search-query "") width)
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
                        (cadr-tui:theme-foreground
                         :accent
                         (concatenate 'string label padding))
                        label)
                    (if selected-p "" padding) "  "
                    (cadr-tui:theme-foreground
                     (if selected-p :accent :muted)
                     (settings-option-display-value option)))
                 collect (selector-fit-line line width))
           (list (selector-muted-line
                  "  No matching settings" width)))
       (when (or (> start 0) (< end total))
         (list
          (selector-dim-line
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
        (selector-fit-line
         (cadr-tui:truncate-to-width
          (cadr-tui:theme-foreground
           :dim
           (if search-p
               "  Type to search · Enter/Space to change · Esc to cancel"
               "  Enter/Space to change · Esc to cancel"))
          width "...")
         width))))))

(defun render-settings-select-submenu
    (state width title description &key searchable)
  (let* ((options (settings-selector-submenu-options state))
         (selected (settings-selector-state-submenu-selected state)))
    (append
     (list
      (selector-component-text-line
       (cadr-tui:theme-foreground
        :accent
        (cadr-tui:theme-bold title))
       width :padding-x 0)
      "")
     (component-text-lines
      (cadr-tui:theme-foreground :muted description)
      width :padding-x 0)
     (if searchable
         (append
          (list "")
          (multiple-value-bind (lines row column)
              (selector-input-rendering
               (settings-selector-state-submenu-query state)
               width)
            (declare (ignore row column))
            lines)
          (list ""))
         (list ""))
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
                for label-padding =
                  (and desc (> width 40)
                       (make-string
                        (max 1 (- primary-width
                                  (cadr-tui:visible-width label)))
                        :initial-element #\Space))
                for description-start =
                  (+ (cadr-tui:visible-width prefix)
                     (cadr-tui:visible-width label)
                     (if label-padding
                         (cadr-tui:visible-width label-padding)
                         0))
                for fitted-desc =
                  (and label-padding
                       (cadr-tui:truncate-to-width
                        desc
                        (max 0 (- width description-start 2))
                        ""))
                collect
                (if selected-p
                    (cadr-tui:theme-foreground
                     :accent
                     (concatenate
                      'string prefix label
                      (or label-padding "")
                      (or fitted-desc "")))
                    (concatenate
                     'string prefix label
                     (if label-padding
                         (cadr-tui:theme-foreground
                          :muted
                          (concatenate
                           'string label-padding fitted-desc))
                         ""))))
          (when (or (> start 0) (< end total))
            (list
             (cadr-tui:theme-foreground
              :muted
              (format nil "  (~D/~D)" (1+ selected) total)))))))
     (list "")
     (component-text-lines
      (cadr-tui:theme-foreground
       :dim
       (if searchable
           "  Type to filter · Enter to select · Esc to go back"
           "  Enter to select · Esc to go back"))
      width :padding-x 0))))

(defun render-settings-automatic-theme-chrome (width body)
  (append
   (list
    (selector-component-text-line
     (cadr-tui:theme-foreground
      :accent
      (cadr-tui:theme-bold "Automatic Theme"))
     width :padding-x 0)
    "")
   (component-text-lines
    (cadr-tui:theme-foreground
     :muted
     "Choose themes for terminal light and dark appearance.")
    width :padding-x 0)
   (list
    (component-text-line
     (cadr-tui:theme-foreground
      :muted
      "Light/dark detection requires terminal support.")
     width :padding-x 0)
    "")
   body))

(defun render-settings-selector
    (state width)
    (when (eq :main (settings-selector-state-mode state))
    (multiple-value-bind (input-lines input-row input-column)
        (selector-input-rendering
         (settings-selector-state-query state) width)
      (setf (settings-selector-state-list-origin state)
            (+ 1 (length input-lines) 1))
      (return-from render-settings-selector
        (multiple-value-bind (lines cursor-row cursor-column)
            (render-selector-frame
             (make-selector-frame
              :sections
              (list
               :border
               (list :component input-lines input-row input-column)
               :blank
               (list
                :lines
                (render-settings-option-list
                 (settings-selector-visible-options state)
                 (settings-selector-state-options state)
                 (settings-selector-state-selected state)
                 width 10
                 :search-query
                 (settings-selector-state-query state)
                 :search-p t
                 :include-input-p nil))
               :border))
             width)
          (declare (ignore cursor-row cursor-column))
          (values lines nil nil)))))
  (setf (settings-selector-state-list-origin state) nil)
  (render-selector-frame
   (make-selector-frame
    :sections
    (list
     :border
     (list
      :lines
      (case (settings-selector-state-mode state)
        (:warnings
         (render-settings-option-list
          (settings-selector-submenu-options state)
          (settings-selector-submenu-options state)
          (settings-selector-state-submenu-selected state)
          width 1))
        (:model-thinking
         (render-settings-select-submenu
          state width "Per-Model Thinking Level"
          "Step 1/2 · Select a model to configure"
          :searchable t))
        (:model-thinking-level
         (let* ((model-key
                  (settings-selector-state-model-thinking-key state))
                (model
                  (find model-key
                        (settings-selector-state-available-models state)
                        :key
                        (lambda (candidate)
                          (model-setting-key
                           (cadr-ai:model-provider candidate)
                           (cadr-ai:model-id candidate)))
                        :test #'string=)))
           (render-settings-select-submenu
            state width
            (if model
                (format nil "Thinking Level for ~A"
                        (settings-model-thinking-item-label model))
                "Thinking Level")
            "Step 2/2 · Select default thinking level for this model")))
        (:theme-single
         (render-settings-select-submenu
          state width "Theme"
          "Select a theme, or choose Automatic to follow terminal appearance."))
        (:theme-light
         (render-settings-automatic-theme-chrome
          width
          (render-settings-select-submenu
           state width "Light Theme"
           "Select the theme to use for light terminal appearance")))
        (:theme-dark
         (render-settings-automatic-theme-chrome
          width
          (render-settings-select-submenu
           state width "Dark Theme"
           "Select the theme to use for dark terminal appearance")))
        (:theme-automatic
         (render-settings-automatic-theme-chrome
          width
          (render-settings-option-list
           (settings-selector-submenu-options state)
           (settings-selector-submenu-options state)
           (settings-selector-state-submenu-selected state)
           width 4)))
        (otherwise nil)))
     :border))
   width))
