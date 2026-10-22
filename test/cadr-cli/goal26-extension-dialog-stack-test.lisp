(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Goal 26: editor-slot extension dialogs stack (pi #11166 #9909).
;;; Locked to packages/coding-agent/test/interactive-mode-extension-dialogs.test.ts
;;; at v1.4.0 (4a080252).

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

(test goal26-confirm-from-inline-custom-restores-component
  ;; pi #9909: confirm opened from an inline custom restores the custom.
  (let ((extension-ui nil)
        (custom-worker nil)
        (confirm-worker nil)
        (custom-result :pending)
        (confirm-result :pending)
        (close-custom nil)
        (custom-opened (sb-thread:make-semaphore :count 0))
        (confirm-opened (sb-thread:make-semaphore :count 0)))
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
       (lambda (terminal)
         (declare (ignore terminal))
         (setf
          confirm-worker
          (sb-thread:make-thread
           (lambda ()
             (setf confirm-result
                   (funcall
                    extension-ui :confirm
                    '(:title "Discard?"
                      :message "discard changes")))
             nil)
           :name "cadr-goal26-nested-confirm"))
         t)
       (footer-sync-wait-for-screen-text "Discard?")
       (string #\Escape)
       (footer-sync-wait-for-screen-text "custom form")
       (lambda (terminal)
         (is (eq confirm-result nil))
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
     (let ((opens 0))
       (lambda ()
         (incf opens)
         (sb-thread:signal-semaphore
          (if (= opens 1) custom-opened confirm-opened))))
     :command-function
     (lambda (line)
       (when (string= line "/custom-then-confirm")
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
                       (cadr-tui:make-text-component
                        "custom form"
                        :padding-x 0 :padding-y 0))
                     :overlay-p nil)))
             nil)
           :name "cadr-goal26-nested-custom"))
         (sb-thread:wait-on-semaphore custom-opened :timeout 2d0))
       t))
    (when custom-worker
      (sb-thread:join-thread custom-worker :timeout 2))
    (when confirm-worker
      (sb-thread:join-thread confirm-worker :timeout 2))
    (is (equal "kept" custom-result))
    (is (eq nil confirm-result))))
