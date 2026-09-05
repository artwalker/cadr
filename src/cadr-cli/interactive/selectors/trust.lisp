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

;; Width-keyed chrome for trust paint; interned pointer/check.
(defparameter *trust-selector-arrow-accent* nil)
(defparameter *trust-selector-check-success* nil)
(defparameter *trust-selector-session-by-key*
  (make-hash-table :test #'equal))
(defparameter *trust-selector-footer-by-key*
  (make-hash-table :test #'equal))
(defparameter *trust-selector-cwd-by-key*
  (make-hash-table :test #'equal))
(defparameter *trust-selector-saved-by-key*
  (make-hash-table :test #'equal))
(defparameter *trust-selector-accent-by-text*
  (make-hash-table :test #'equal))
(defparameter *trust-selector-text-by-text*
  (make-hash-table :test #'equal))

(defun trust-selector-arrow-accent ()
  (or *trust-selector-arrow-accent*
      (setf *trust-selector-arrow-accent*
            (cadr-tui:theme-foreground :accent "→ "))))

(defun trust-selector-check-success ()
  (or *trust-selector-check-success*
      (setf *trust-selector-check-success*
            (cadr-tui:theme-foreground :success " ✓"))))

(defun trust-selector-accent (text)
  (or (gethash text *trust-selector-accent-by-text*)
      (setf (gethash text *trust-selector-accent-by-text*)
            (cadr-tui:theme-foreground :accent text))))

(defun trust-selector-text (text)
  (or (gethash text *trust-selector-text-by-text*)
      (setf (gethash text *trust-selector-text-by-text*)
            (cadr-tui:theme-foreground :text text))))

(defun trust-selector-cwd-line (cwd width)
  (let ((key (cons cwd width)))
    (or (gethash key *trust-selector-cwd-by-key*)
        (setf (gethash key *trust-selector-cwd-by-key*)
              (selector-component-text-line
               (cadr-tui:theme-foreground :muted cwd)
               width)))))

(defun trust-selector-saved-lines (state width)
  (let* ((desc (trust-decision-description state))
         (key (cons desc width)))
    (or (gethash key *trust-selector-saved-by-key*)
        (setf (gethash key *trust-selector-saved-by-key*)
              (component-text-lines
               (cadr-tui:theme-foreground
                :muted
                (format nil "Saved decision: ~A" desc))
               width)))))

(defun trust-selector-session-line (trusted-p width)
  (let ((key (cons trusted-p width)))
    (or (gethash key *trust-selector-session-by-key*)
        (setf (gethash key *trust-selector-session-by-key*)
              (selector-component-text-line
               (cadr-tui:theme-foreground
                :muted
                (format nil "Current session: ~A"
                        (if trusted-p "trusted" "untrusted")))
               width)))))

(defun trust-selector-footer-line (state width)
  (or (gethash width *trust-selector-footer-by-key*)
      (setf (gethash width *trust-selector-footer-by-key*)
            (let ((keybindings
                    (or (trust-selector-state-keybindings state)
                        (cadr-tui:get-keybindings))))
              (selector-component-text-line
               (concatenate
                'string
                (raw-key-hint "↑↓" "navigate") "  "
                (selector-keybinding-hint
                 keybindings "tui.select.confirm" "save") "  "
                (selector-keybinding-hint
                 keybindings "tui.select.cancel" "cancel"))
               width)))))

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
       (trust-selector-cwd-line
        (trust-selector-state-cwd state)
        width)))
     :blank
     (list
      :lines
      (append
       (trust-selector-saved-lines state width)
       (list
        (trust-selector-session-line
         (trust-selector-state-project-trusted-p state)
         width))))
     :blank :viewport :blank
     (list
      :lines
      (list (trust-selector-footer-line state width)))
     :blank :border)
    :item-renderer
    (lambda (option index selected-p total item-width)
      (declare (ignore index total))
      (let ((saved-p
              (trust-option-saved-p
               option
               (trust-selector-state-saved-entry state)))
            (label (getf option :label)))
        (component-text-lines
         (concatenate
          'string
          (if selected-p
              (trust-selector-arrow-accent)
              "  ")
          (if selected-p
              (trust-selector-accent label)
              (trust-selector-text label))
          (if saved-p
              (trust-selector-check-success)
              ""))
         item-width))))
   width))
