;;; The login dialog mirrors the fixed baseline LoginDialogComponent
;;; (packages/coding-agent/src/modes/interactive/components/login-dialog.ts):
;;; a bordered frame titled "Login to <provider>" whose content is driven by
;;; the OAuth event stream (auth URL, device code, waiting, progress, manual
;;; input) rather than by transcript status lines.
(in-package #:cadr-cli)

(defstruct (login-dialog-state
            (:constructor %make-login-dialog-state))
  (provider-name "" :type string)
  (sections nil :type list)
  input
  cancel-function)

(cadr-core:define-redacted-print-object
    (login-dialog-state value stream)
  (format stream ":provider ~A :input [REDACTED]"
          (login-dialog-state-provider-name value)))

(defun make-login-dialog-state (provider-name)
  (%make-login-dialog-state :provider-name provider-name))

(defun login-dialog-show-auth (state url instructions)
  ;; Baseline showAuth: clear, Spacer, accent URL, dim click hint, and an
  ;; optional Spacer + warning instructions block.
  (setf (login-dialog-state-sections state)
        (append
         (list '(:kind :blank)
               (list :kind :url :url url))
         (when (and instructions (plusp (length instructions)))
           (list '(:kind :blank)
                 (list :kind :warning :text instructions)))))
  state)

(defun login-dialog-show-device-code (state url user-code)
  ;; Baseline showDeviceCode: clear, Spacer, accent URL, dim click hint,
  ;; Spacer, warning "Enter code: <user-code>".
  (setf (login-dialog-state-sections state)
        (list '(:kind :blank)
              (list :kind :url :url url)
              '(:kind :blank)
              (list :kind :warning
                    :text (format nil "Enter code: ~A" user-code))))
  state)

(defun login-dialog-show-waiting (state message)
  ;; Baseline showWaiting: Spacer, dim message, cancel key hint.
  (setf (login-dialog-state-sections state)
        (append (login-dialog-state-sections state)
                (list '(:kind :blank)
                      (list :kind :dim :text message)
                      '(:kind :hint-cancel))))
  state)

(defun login-dialog-show-progress (state message)
  ;; Baseline showProgress: append one dim line.
  (setf (login-dialog-state-sections state)
        (append (login-dialog-state-sections state)
                (list (list :kind :dim :text message))))
  state)

(defun login-dialog-show-manual-input (state message cancel-function)
  ;; Baseline showManualInput: Spacer, dim prompt, input, cancel key hint.
  (setf (login-dialog-state-input state)
        (cadr-tui:make-single-line-input :prompt "> ")
        (login-dialog-state-cancel-function state) cancel-function
        (login-dialog-state-sections state)
        (append (login-dialog-state-sections state)
                (list '(:kind :blank)
                      (list :kind :dim :text message)
                      '(:kind :input)
                      '(:kind :hint-cancel))))
  state)

(defun login-dialog-show-prompt (state message placeholder cancel-function)
  ;; Baseline showPrompt: Spacer, text message, optional dim "e.g., ...",
  ;; input, cancel+submit key hint.
  (setf (login-dialog-state-input state)
        (cadr-tui:make-single-line-input :prompt "> ")
        (login-dialog-state-cancel-function state) cancel-function
        (login-dialog-state-sections state)
        (append (login-dialog-state-sections state)
                (append
                 (list '(:kind :blank)
                       (list :kind :text :text message))
                 (when (and placeholder (plusp (length placeholder)))
                   (list (list :kind :dim
                               :text (format nil "e.g., ~A" placeholder))))
                 (list '(:kind :input)
                       '(:kind :hint-cancel-submit)))))
  state)

(defun login-dialog-show-info (state message links show-close-hint-p)
  ;; Baseline showInfo: Spacer, text-colored message, one accent hyperlink
  ;; per link ("label: url" or the bare URL), and an optional Spacer +
  ;; close hint.
  (setf (login-dialog-state-sections state)
        (append (login-dialog-state-sections state)
                (list '(:kind :blank)
                      (list :kind :text :text message))
                (mapcar
                 (lambda (link)
                   (list :kind :link
                         :text (let ((label (getf link :label))
                                     (url (getf link :url)))
                                 (if (and label (plusp (length label)))
                                     (format nil "~A: ~A" label url)
                                     url))
                         :url (getf link :url)))
                 links)
                (when show-close-hint-p
                  (list '(:kind :blank)
                        '(:kind :hint-close)))))
  state)

(defun login-dialog-show-details (state lines)
  ;; Baseline showDetails: clear, Spacer, then one caller-styled line per
  ;; entry.  LINES are (kind text) pairs using the section style keywords.
  (setf (login-dialog-state-sections state)
        (append (list '(:kind :blank))
                (mapcar
                 (lambda (line)
                   (list :kind (first line) :text (second line)))
                 lines)))
  state)

(defun login-dialog-complete-input (state value)
  ;; Baseline replaceInputWithSubmittedText: the input line becomes a plain
  ;; "> <value>" line and the dialog stays open until the flow settles.
  (setf (login-dialog-state-input state) nil
        (login-dialog-state-sections state)
        (mapcar
         (lambda (section)
           (if (eq (getf section :kind) :input)
               (list :kind :submitted :text value)
               section))
         (login-dialog-state-sections state)))
  state)

(defun login-dialog-state-handle-event (state event)
  (if (member (cadr-tui:input-event-kind event)
              '(:escape :cancel :clear :interrupt :eof))
      (progn
        (when (login-dialog-state-cancel-function state)
          (ignore-errors
            (funcall (login-dialog-state-cancel-function state))))
        (values :cancel nil))
      (if (login-dialog-state-input state)
          (multiple-value-bind (action value)
              (cadr-tui:single-line-input-handle-event
               (login-dialog-state-input state) event)
            (values (if (eq action :submit) :select action) value))
          (values :changed nil))))

(defun render-login-dialog-state (state width)
  (let ((keybindings (cadr-tui:get-keybindings))
        (input (login-dialog-state-input state)))
    (multiple-value-bind (input-lines input-row input-column)
        (if input
            (cadr-tui:render-single-line-input input width)
            (values nil nil nil))
      (flet ((frame-section (section)
               (case (getf section :kind)
                 (:blank (list :blank))
                 (:url
                  (list
                   (list
                    :lines
                    (mapcar
                     (lambda (line)
                       (selector-component-text-line line width))
                     (render-auth-url-lines
                      (getf section :url)
                      (max 1 (- width 2)))))))
                 ((:warning :dim :text)
                  (list
                   (list
                    :lines
                    (component-text-lines
                     (cadr-tui:theme-foreground
                      (getf section :kind)
                      (getf section :text)
                      :enabled-p t)
                     width))))
                 (:muted
                  (list
                   (list
                    :lines
                    (component-text-lines
                     (cadr-tui:theme-foreground
                      :muted
                      (getf section :text)
                      :enabled-p t)
                     width))))
                 (:accent
                  (list
                   (list
                    :lines
                    (component-text-lines
                     (cadr-tui:theme-foreground
                      :accent
                      (getf section :text)
                      :enabled-p t)
                     width))))
                 (:link
                  (list
                   (list
                    :lines
                    (mapcar
                     (lambda (line)
                       (selector-component-text-line line width))
                     (cadr-tui:wrap-text
                      (cadr-tui:theme-foreground
                       :accent
                       (terminal-hyperlink
                        (getf section :url)
                        (getf section :text))
                       :enabled-p t)
                      (max 1 (- width 2)))))))
                 (:submitted
                  (list
                   (list
                    :lines
                    (list
                     (selector-fit-line
                      (format nil "> ~A" (getf section :text))
                      width)))))
                 (:input
                  (list (list :component input-lines input-row input-column)))
                 (:hint-cancel
                  (list
                   (list
                    :lines
                    (list
                     (selector-component-text-line
                      (format
                       nil "(~A)"
                       (selector-keybinding-hint
                         keybindings "tui.select.cancel" "to cancel"))
                      width)))))
                 (:hint-cancel-submit
                  (list
                   (list
                    :lines
                     (list
                      (selector-component-text-line
                       (format
                        nil "(~A ~A)"
                        (selector-keybinding-hint
                         keybindings "tui.select.cancel" "to cancel,")
                        (selector-keybinding-hint
                         keybindings "tui.select.confirm" "to submit"))
                      width)))))
                 (:hint-close
                  (list
                   (list
                    :lines
                    (list
                     (selector-component-text-line
                      (format
                       nil "(~A)"
                       (selector-keybinding-hint
                         keybindings "tui.select.cancel" "to close"))
                      width))))))))
        (render-selector-frame
         (make-selector-frame
          :sections
          (append
           (list (list :border :border)
                 (list
                  :title
                  (format
                   nil "Login to ~A"
                   (login-dialog-state-provider-name state))
                  :overlay))
           (mapcan #'frame-section
                   (login-dialog-state-sections state))
           (list (list :border :border))))
         width)))))
