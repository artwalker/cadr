(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Goal 26: editor-slot extension dialogs stack (pi #11166 #9909).
;;; Locked to packages/coding-agent/test/interactive-mode-extension-dialogs.test.ts
;;; and the “overlay custom UI reclaims input after non-overlay custom UI
;;; closes” case in interactive-mode-status.test.ts at v1.4.0 (4a080252).

(defclass goal26-input-log (cadr-tui:component)
  ((label
    :initarg :label
    :reader goal26-input-log-label)
   (inputs
    :initform nil
    :accessor goal26-input-log-inputs)
   (on-text
    :initarg :on-text
    :initform nil)))

(defmethod cadr-tui:component-render
    ((component goal26-input-log) width &key focused-p)
  (declare (ignore width focused-p))
  (list (goal26-input-log-label component)))

(defmethod cadr-tui:component-handle-event
    ((component goal26-input-log) event)
  (when (eq (cadr-tui:input-event-kind event) :text)
    (push (cadr-tui:input-event-text event)
          (goal26-input-log-inputs component))
    (let ((hook (slot-value component 'on-text)))
      (when hook
        (funcall hook event))))
  (values nil nil))

(defclass goal26-dialog-stack-terminal (footer-sync-test-terminal)
  ((program-status
    :initform nil
    :accessor goal26-dialog-stack-terminal-program-status)))

(defmethod cadr-tui:terminal-set-program-status
    ((terminal goal26-dialog-stack-terminal) status)
  (setf (goal26-dialog-stack-terminal-program-status terminal)
        (and status
             (not (eq :clear (cadr-tui:program-status-state status)))
             status))
  status)

(defun goal26-dialog-stack-screen (terminal)
  (format nil "~{~A~^~%~}"
          (mapcar #'cadr-tui:strip-terminal-sequences
                  (cadr-tui:virtual-terminal-snapshot terminal))))

(defun goal26-dialog-stack-program-status (terminal)
  (goal26-dialog-stack-terminal-program-status terminal))

(test goal26-extension-confirm-stack-restores-earlier-dialog
  ;; pi #11166: answering the later confirm shows the earlier one again.
  (let ((extension-ui nil)
        (first-worker nil)
        (second-worker nil)
        (first-result :pending)
        (second-result :pending)
        (first-opened (sb-thread:make-semaphore :count 0))
        (second-opened (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'goal26-dialog-stack-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/stack-confirms")
       (footer-sync-wait-for-screen-text "Second")
       (lambda (terminal)
         (let ((status (goal26-dialog-stack-program-status terminal)))
           (is (eq :blocked (cadr-tui:program-status-state status)))
           (is (eq :permission (cadr-tui:program-status-kind status)))
           (is (string= "Second"
                        (cadr-tui:program-status-message status))))
         (is (search "Second" (goal26-dialog-stack-screen terminal)))
         (is (not (search "First"
                          (goal26-dialog-stack-screen terminal))))
         t)
       (string #\Escape)
       (footer-sync-wait-for-screen-text "First")
       (lambda (terminal)
         (is (equal second-result nil))
         (let ((status (goal26-dialog-stack-program-status terminal)))
           (is (eq :blocked (cadr-tui:program-status-state status)))
           (is (eq :permission (cadr-tui:program-status-kind status)))
           (is (string= "First"
                        (cadr-tui:program-status-message status))))
         (is (search "First" (goal26-dialog-stack-screen terminal)))
         t)
       (string #\Return)
       (lambda (terminal)
         (declare (ignore terminal))
         (and (eq first-result t)
              (eq second-result nil)))
       (footer-sync-submit-input "/quit")))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (let ((opens 0))
       (lambda ()
         (incf opens)
         (sb-thread:signal-semaphore
          (if (= opens 1) first-opened second-opened))))
     :command-function
     (lambda (line)
       (when (string= line "/stack-confirms")
         (setf
          first-worker
          (sb-thread:make-thread
           (lambda ()
             (setf first-result
                   (funcall
                    extension-ui :confirm
                    '(:title "First" :message "first dialog")))
             nil)
           :name "cadr-goal26-confirm-first"))
         (sb-thread:wait-on-semaphore first-opened :timeout 2d0)
         (setf
          second-worker
          (sb-thread:make-thread
           (lambda ()
             (setf second-result
                   (funcall
                    extension-ui :confirm
                    '(:title "Second" :message "second dialog")))
             nil)
           :name "cadr-goal26-confirm-second"))
         (sb-thread:wait-on-semaphore second-opened :timeout 2d0))
       t))
    (when first-worker
      (sb-thread:join-thread first-worker :timeout 2))
    (when second-worker
      (sb-thread:join-thread second-worker :timeout 2))
    (is (eq t first-result))
    (is (eq nil second-result))))

(test goal26-extension-confirm-hidden-abort-leaves-visible-dialog
  ;; pi #11166: aborting a buried confirm leaves the visible one.
  (let* ((extension-ui nil)
         (first-worker nil)
         (second-worker nil)
         (first-result :pending)
         (second-result :pending)
         (cancel-signal
           (cadr-agent:make-extension-cancellation-signal))
         (first-opened (sb-thread:make-semaphore :count 0))
         (second-opened (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'goal26-dialog-stack-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/stack-abort")
       (footer-sync-wait-for-screen-text "Second")
       (lambda (terminal)
         (declare (ignore terminal))
         (cadr-agent:abort-extension-cancellation-signal cancel-signal)
         t)
       (let ((tries 0))
         (lambda (terminal)
           (when (> (incf tries) 100)
             (error "buried confirm did not abort. result=~S~%~A"
                    first-result
                    (goal26-dialog-stack-screen terminal)))
           (unless (and (eq first-result nil)
                        (search "Second"
                                (goal26-dialog-stack-screen terminal)))
             (sleep 0.02))
           (and (eq first-result nil)
                (search "Second"
                        (goal26-dialog-stack-screen terminal)))))
       (string #\Return)
       (let ((tries 0))
         (lambda (terminal)
           (declare (ignore terminal))
           (when (> (incf tries) 400)
             (error "visible confirm did not resolve. result=~S"
                    second-result))
           (eq second-result t)))
       (footer-sync-submit-input "/quit")))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (let ((opens 0))
       (lambda ()
         (incf opens)
         (sb-thread:signal-semaphore
          (if (= opens 1) first-opened second-opened))))
     :command-function
     (lambda (line)
       (when (string= line "/stack-abort")
         (setf
          first-worker
          (sb-thread:make-thread
           (lambda ()
             (setf first-result
                   (funcall
                    extension-ui :confirm
                    (list :title "First"
                          :message "first dialog"
                          :signal cancel-signal)))
             nil)
           :name "cadr-goal26-confirm-abort-first"))
         (sb-thread:wait-on-semaphore first-opened :timeout 2d0)
         (setf
          second-worker
          (sb-thread:make-thread
           (lambda ()
             (setf second-result
                   (funcall
                    extension-ui :confirm
                    '(:title "Second" :message "second dialog")))
             nil)
           :name "cadr-goal26-confirm-abort-second"))
         (sb-thread:wait-on-semaphore second-opened :timeout 2d0))
       t))
    (when first-worker
      (sb-thread:join-thread first-worker :timeout 2))
    (when second-worker
      (sb-thread:join-thread second-worker :timeout 2))
    (is (eq nil first-result))
    (is (eq t second-result))))

(test goal26-inline-custom-components-stack
  ;; pi #9909: concurrent inline custom() components stack.
  (let ((extension-ui nil)
        (first-worker nil)
        (second-worker nil)
        (first-result :pending)
        (second-result :pending)
        (close-first nil)
        (close-second nil)
        (first-opened (sb-thread:make-semaphore :count 0))
        (second-opened (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'goal26-dialog-stack-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/stack-customs")
       (footer-sync-wait-for-screen-text "custom two")
       (lambda (terminal)
         (is (search "custom two"
                     (goal26-dialog-stack-screen terminal)))
         (is (not (search "custom one"
                          (goal26-dialog-stack-screen terminal))))
         (funcall close-second "two")
         t)
       (footer-sync-wait-for-screen-text "custom one")
       (lambda (terminal)
         (is (equal second-result "two"))
         (is (search "custom one"
                     (goal26-dialog-stack-screen terminal)))
         (funcall close-first "one")
         t)
       (lambda (terminal)
         (declare (ignore terminal))
         (and (equal first-result "one")
              (equal second-result "two")))
       (footer-sync-submit-input "/quit")))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (let ((opens 0))
       (lambda ()
         (incf opens)
         (sb-thread:signal-semaphore
          (if (= opens 1) first-opened second-opened))))
     :command-function
     (lambda (line)
       (when (string= line "/stack-customs")
         (setf
          first-worker
          (sb-thread:make-thread
           (lambda ()
             (setf first-result
                   (funcall
                    extension-ui :custom-component
                    (list
                     :factory
                     (lambda (tui theme keybindings done)
                       (declare (ignore tui theme keybindings))
                       (setf close-first done)
                       (cadr-tui:make-text-component
                        "custom one"
                        :padding-x 0 :padding-y 0))
                     :overlay-p nil)))
             nil)
           :name "cadr-goal26-custom-first"))
         (sb-thread:wait-on-semaphore first-opened :timeout 2d0)
         (setf
          second-worker
          (sb-thread:make-thread
           (lambda ()
             (setf second-result
                   (funcall
                    extension-ui :custom-component
                    (list
                     :factory
                     (lambda (tui theme keybindings done)
                       (declare (ignore tui theme keybindings))
                       (setf close-second done)
                       (cadr-tui:make-text-component
                        "custom two"
                        :padding-x 0 :padding-y 0))
                     :overlay-p nil)))
             nil)
           :name "cadr-goal26-custom-second"))
         (sb-thread:wait-on-semaphore second-opened :timeout 2d0))
       t))
    (when first-worker
      (sb-thread:join-thread first-worker :timeout 2))
    (when second-worker
      (sb-thread:join-thread second-worker :timeout 2))
    (is (equal "one" first-result))
    (is (equal "two" second-result))))

(test goal26-overlay-custom-reclaims-input-after-inline-closes
  ;; pi v1.4.0 interactive-mode-status.test.ts: overlay custom UI
  ;; reclaims input after non-overlay custom UI closes. Key "x" reaches
  ;; the overlay, not the editor, and the overlay stays on screen.
  (let ((extension-ui nil)
        (overlay-worker nil)
        (inline-worker nil)
        (overlay-result :pending)
        (inline-result :pending)
        (overlay-component nil)
        (close-overlay nil)
        (close-inline nil)
        (overlay-opened (sb-thread:make-semaphore :count 0))
        (inline-opened (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'goal26-dialog-stack-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/overlay-then-inline")
       (footer-sync-wait-for-screen-text "OVERLAY")
       (footer-sync-wait-for-screen-text "REPLACEMENT")
       (lambda (terminal)
         (declare (ignore terminal))
         (funcall close-inline "done")
         t)
       ;; OVERLAY is composited while the inline is up, so waiting for
       ;; OVERLAY alone can succeed on the pre-close frame. Wait until
       ;; REPLACEMENT is gone (pi: inline unmount restores overlay focus).
       (let ((tries 0))
         (lambda (terminal)
           (when (> (incf tries) 200)
             (error "inline custom did not leave. result=~S~%~A"
                    inline-result
                    (goal26-dialog-stack-screen terminal)))
           (let ((screen (goal26-dialog-stack-screen terminal)))
             (unless (and (equal inline-result "done")
                          (search "OVERLAY" screen)
                          (not (search "REPLACEMENT" screen)))
               (sleep 0.02))
             (and (equal inline-result "done")
                  (search "OVERLAY" screen)
                  (not (search "REPLACEMENT" screen))))))
       (lambda (terminal)
         (is (not (search "REPLACEMENT"
                          (goal26-dialog-stack-screen terminal))))
         (is (equal "done" inline-result))
         t)
       "x"
       (lambda (terminal)
         (is (equal '("x")
                    (reverse
                     (goal26-input-log-inputs overlay-component))))
         (is (search "OVERLAY"
                     (goal26-dialog-stack-screen terminal)))
         (is (not (search "x"
                          (goal26-dialog-stack-screen terminal))))
         (funcall close-overlay "closed")
         t)
       (lambda (terminal)
         (declare (ignore terminal))
         (equal overlay-result "closed"))
       (footer-sync-submit-input "/quit")))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (let ((opens 0))
       (lambda ()
         (incf opens)
         (sb-thread:signal-semaphore
          (if (= opens 1) overlay-opened inline-opened))))
     :command-function
     (lambda (line)
       (when (string= line "/overlay-then-inline")
         (setf
          overlay-worker
          (sb-thread:make-thread
           (lambda ()
             (setf overlay-result
                   (funcall
                    extension-ui :custom-component
                    (list
                     :factory
                     (lambda (tui theme keybindings done)
                       (declare (ignore tui theme keybindings))
                       (setf close-overlay done
                             overlay-component
                             (make-instance
                              'goal26-input-log
                              :label "OVERLAY")))
                     :overlay-p t)))
             nil)
           :name "cadr-goal26-overlay-custom"))
         (sb-thread:wait-on-semaphore overlay-opened :timeout 2d0)
         (setf
          inline-worker
          (sb-thread:make-thread
           (lambda ()
             (setf inline-result
                   (funcall
                    extension-ui :custom-component
                    (list
                     :factory
                     (lambda (tui theme keybindings done)
                       (declare (ignore tui theme keybindings))
                       (setf close-inline done)
                       (cadr-tui:make-text-component
                        "REPLACEMENT"
                        :padding-x 0 :padding-y 0))
                     :overlay-p nil)))
             nil)
           :name "cadr-goal26-inline-custom"))
         (sb-thread:wait-on-semaphore inline-opened :timeout 2d0))
       t))
    (when overlay-worker
      (sb-thread:join-thread overlay-worker :timeout 2))
    (when inline-worker
      (sb-thread:join-thread inline-worker :timeout 2))
    (is (equal "closed" overlay-result))
    (is (equal "done" inline-result))
    (is (equal '("x")
               (reverse (goal26-input-log-inputs overlay-component))))))

(test goal26-confirm-from-inline-custom-restores-component
  ;; pi #9909: confirm opened from an inline component's handleInput
  ;; returns immediately. Escape then closes the confirm and the custom
  ;; is visible again. The call runs on the TUI input thread.
  (let ((extension-ui nil)
        (custom-worker nil)
        (custom-result :pending)
        (confirmed nil)
        (close-custom nil)
        (custom-opened (sb-thread:make-semaphore :count 0)))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :terminal
     (make-instance
      'goal26-dialog-stack-terminal
      :columns 80 :rows 16
      :inputs
      (list
       (footer-sync-submit-input "/custom-then-confirm")
       (footer-sync-wait-for-screen-text "custom form")
       "x"
       (footer-sync-wait-for-screen-text "Discard?")
       (string #\Escape)
       (footer-sync-wait-for-screen-text "custom form")
       (let ((tries 0))
         (lambda (terminal)
           (when (> (incf tries) 100)
             (error "confirm did not settle. promise=~S~%~A"
                    confirmed
                    (goal26-dialog-stack-screen terminal)))
           (unless (and confirmed
                        (cadr-agent::extension-ui-promise-p confirmed)
                        (cadr-agent::extension-ui-promise-done-p
                         confirmed)
                        (null
                         (cadr-agent::extension-ui-promise-result
                          confirmed))
                        (search "custom form"
                                (goal26-dialog-stack-screen terminal)))
             (sleep 0.02))
           (and confirmed
                (cadr-agent::extension-ui-promise-done-p confirmed)
                (null
                 (cadr-agent::extension-ui-promise-result confirmed))
                (search "custom form"
                        (goal26-dialog-stack-screen terminal)))))
       (lambda (terminal)
         (is (search "custom form"
                     (goal26-dialog-stack-screen terminal)))
         (funcall close-custom "kept")
         t)
       (lambda (terminal)
         (declare (ignore terminal))
         (equal custom-result "kept"))
       (footer-sync-submit-input "/quit")))
     :set-extension-ui-function
     (lambda (function)
       (setf extension-ui function))
     :extension-overlay-opened-function
     (lambda ()
       (sb-thread:signal-semaphore custom-opened))
     :command-function
     (lambda (line)
       (when (string= line "/custom-then-confirm")
         (let ((context
                 (cadr-agent::%make-extension-context
                  :host
                  (cadr-agent::make-extension-host
                   :cwd #P"/tmp/"
                   :mode :repl
                   :ui-function extension-ui)
                  :source-path #P"/tmp/goal26-dialog/"
                  :bundle
                  (cadr-agent::make-extension-bundle
                   :id "goal26-dialog"
                   :path "/tmp/goal26-dialog/")
                  :kind :command)))
           (setf
            custom-worker
            (sb-thread:make-thread
             (lambda ()
               (setf custom-result
                     (funcall
                      extension-ui :custom-component
                      (list
                       :factory
                       (lambda (tui theme keybindings done)
                         (declare (ignore tui theme keybindings))
                         (setf close-custom done)
                         (make-instance
                          'goal26-input-log
                          :label "custom form"
                          :on-text
                          (lambda (event)
                            (when (string=
                                   (cadr-tui:input-event-text event)
                                   "x")
                              (setf confirmed
                                    (cadr-agent:extension-context-confirm
                                     context
                                     "Discard?"
                                     "discard changes"))))))
                       :overlay-p nil)))
               nil)
             :name "cadr-goal26-nested-custom"))
           (sb-thread:wait-on-semaphore custom-opened :timeout 2d0)))
       t))
    (when custom-worker
      (sb-thread:join-thread custom-worker :timeout 2))
    (is (equal "kept" custom-result))
    (is (cadr-agent::extension-ui-promise-p confirmed))
    (is (null (cadr-agent::extension-ui-promise-result confirmed)))))
