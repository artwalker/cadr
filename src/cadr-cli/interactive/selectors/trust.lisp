(in-package #:cadr-cli)

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
                (display-directory-name parent-path))
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
     :cwd (display-directory-name path)
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
    (setf
     (trust-selector-state-selected state)
     (selector-frame-move-index
      (trust-selector-state-selected state)
      count delta)))
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
          (if (string= (display-directory-name path)
                       (trust-selector-state-cwd state))
              (format nil "~A (~A)"
                      decision
                      (display-directory-name path))
              (format nil
                      "~A (inherited from ~A)"
                      decision
                      (display-directory-name path)))))))

(defun render-trust-selector
    (state width)
  (render-selector-frame
   (make-selector-frame
    :items (trust-selector-state-options state)
    :selected (trust-selector-state-selected state)
    :maximum (max 1 (length
                     (trust-selector-state-options state)))
    :sections
    (list
     :border :blank
     (list :title "Project trust")
     (list
      :lines
      (list
       (selector-component-text-line
        (cadr-tui:theme-foreground
         :muted
         (trust-selector-state-cwd state))
        width)))
     :blank
     (list
      :lines
      (list
       (selector-component-text-line
        (cadr-tui:theme-foreground
         :muted
         (format nil "Saved decision: ~A"
                 (trust-decision-description state)))
        width)
       (selector-component-text-line
        (cadr-tui:theme-foreground
         :muted
         (format nil "Current session: ~A"
                 (if
                     (trust-selector-state-project-trusted-p
                      state)
                     "trusted"
                     "untrusted")))
        width)))
     :blank :viewport :blank
     (list
      :lines
      (list
       (selector-component-text-line
        (concatenate
         'string
         (raw-key-hint "↑↓" "navigate") "  "
         (selector-keybinding-hint
          (trust-selector-state-keybindings state)
          "tui.select.confirm" "save") "  "
         (selector-keybinding-hint
          (trust-selector-state-keybindings state)
          "tui.select.cancel" "cancel"))
        width)))
     :blank :border)
    :item-renderer
    (lambda (option index selected-p total item-width)
      (declare (ignore index total))
      (let ((saved-p
              (trust-option-saved-p
               option
               (trust-selector-state-saved-entry state))))
        (selector-component-text-line
         (concatenate
          'string
          (if selected-p
              (cadr-tui:theme-foreground
               :accent "→ ")
              "  ")
          (if selected-p
              (cadr-tui:theme-foreground
               :accent (getf option :label))
              (cadr-tui:theme-foreground
               :text (getf option :label)))
          (if saved-p
              (cadr-tui:theme-foreground
               :success " ✓")
              ""))
         item-width))))
   width))
