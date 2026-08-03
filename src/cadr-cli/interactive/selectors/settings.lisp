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
  (render-selector-frame
   (make-selector-frame
    :sections
    (list
     :border
     (list
      :lines
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
        (otherwise nil)))
     :border))
   width))
