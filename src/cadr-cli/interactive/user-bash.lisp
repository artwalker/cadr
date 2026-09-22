(in-package #:cadr-cli)

(defconstant +user-bash-preview-lines+ 20)

(defun render-user-bash-entry (entry width &key now)
  ;; Fixed pi@16787ad5b BashExecutionComponent is deliberately separate from
  ;; agent tool rendering: it has a 20-line tail preview, a framed bash-mode
  ;; shell, and component-local cancelled/exit/truncation status copy.
  (let* ((options (tui-entry-custom-options entry))
         (expanded-p (tui-entry-expanded-p entry))
         (output
           (cadr-tui::normalize-tool-output
            (tui-entry-text entry)))
         (logical-lines
           ;; BashExecutionComponent keeps a real trailing stdout newline as
           ;; an empty logical line. Its status Text adds another leading
           ;; newline; together they form the baseline's two-row separation.
           ;; A genuinely empty result still has no output component.
           (and
            (plusp (length output))
            (cadr-tui::split-lines-preserving-empty output)))
         (line-count (length logical-lines))
         (hidden-count
           (max 0 (- line-count +user-bash-preview-lines+)))
         (preview-lines
           (if expanded-p
               logical-lines
               (nthcdr hidden-count logical-lines)))
         (rendered-output
           (when preview-lines
             (let ((lines
                     (component-text-lines
                      (format nil "~%~{~A~^~%~}"
                              (mapcar
                               (lambda (line)
                                 (cadr-tui:theme-foreground
                                  :muted line :enabled-p t))
                               preview-lines))
                      width :padding-x 1)))
               (if expanded-p
                   lines
                   (let ((count (length lines)))
                     (if (> count +user-bash-preview-lines+)
                         (nthcdr
                          (- count +user-bash-preview-lines+)
                          lines)
                         lines))))))
         (running-p (getf options :running-p))
         (status-lines nil)
         (color-token
           (if (getf options :exclude-from-context-p)
               :dim :bash-mode)))
    (when (and (not running-p) (plusp hidden-count))
      (push
       (if expanded-p
           (concatenate
            'string
            (cadr-tui:theme-foreground
             :muted "(" :enabled-p t)
            (key-hint "app.tools.expand" "to collapse")
            (cadr-tui:theme-foreground
             :muted ")" :enabled-p t))
           (concatenate
            'string
            (cadr-tui:theme-foreground
             :muted
             (format nil "... ~D more lines (" hidden-count)
             :enabled-p t)
            (key-hint "app.tools.expand" "to expand")
            (cadr-tui:theme-foreground
             :muted ")" :enabled-p t)))
       status-lines))
    (cond
      (running-p nil)
      ((getf options :cancelled-p)
       (push
        (cadr-tui:theme-foreground
         :warning "(cancelled)" :enabled-p t)
        status-lines))
      ((let ((exit-code (getf options :exit-code)))
         (and (numberp exit-code) (not (zerop exit-code))))
       (push
        (cadr-tui:theme-foreground
         :error
         (format nil "(exit ~D)" (getf options :exit-code))
         :enabled-p t)
        status-lines)))
    (when (and (not running-p)
               (getf options :truncated-p)
               (stringp (getf options :full-output-path))
               (plusp (length (getf options :full-output-path))))
      (push
       (cadr-tui:theme-foreground
        :warning
        (format nil "Output truncated. Full output: ~A"
                (getf options :full-output-path))
        :enabled-p t)
       status-lines))
    (setf status-lines (nreverse status-lines))
    (append
     (list
      ""
      (cadr-tui:theme-foreground
       color-token
       (make-string width :initial-element #\─)
       :enabled-p t))
     (component-text-lines
      (cadr-tui:theme-foreground
       color-token
       (cadr-tui:theme-bold
        (format nil "$ ~A" (or (tui-entry-label entry) ""))
        :enabled-p t)
       :enabled-p t)
      width :padding-x 1)
     rendered-output
     (and
      running-p
      (cons
       ""
       (component-text-lines
        (format
         nil "~A ~A"
         (cadr-tui:theme-foreground
          color-token
          (aref
           +tui-spinner-frames+
           (mod
            (floor
             (/ (or now 0d0)
                +tui-spinner-interval-seconds+))
            (length +tui-spinner-frames+)))
          :enabled-p t)
         (cadr-tui:theme-foreground
          :muted
          (format nil "Running... (~A to cancel)"
                  (key-text "tui.select.cancel"))
          :enabled-p t))
        width :padding-x 1)))
     (and status-lines
          (component-text-lines
           (format nil "~%~{~A~^~%~}" status-lines)
           width :padding-x 1))
     (list
      (cadr-tui:theme-foreground
       color-token
       (make-string width :initial-element #\─)
       :enabled-p t)))))

(defun make-tui-user-bash-entry
    (state command exclude-from-context-p &key running-p)
  (make-tui-entry
   :type :bash-execution
   :label command
   :expanded-p (tui-state-tools-expanded-p state)
   :streaming-p (not (null running-p))
   :custom-options
   (list
    :running-p (not (null running-p))
    :exclude-from-context-p
    (not (null exclude-from-context-p)))))

(defun append-tui-user-bash-running
    (state command exclude-from-context-p)
  (append-tui-entry
   state
   (make-tui-user-bash-entry
    state command exclude-from-context-p :running-p t)))

(defun append-tui-user-bash-output (entry chunk)
  (when (and entry (stringp chunk) (plusp (length chunk)))
    (setf
     (tui-entry-text entry)
     (concatenate 'string (tui-entry-text entry) chunk))
    (invalidate-tui-entry-render-cache entry))
  entry)

(defun complete-tui-user-bash-entry (entry result)
  (setf
   (tui-entry-text entry) (user-bash-result-output result)
   (tui-entry-streaming-p entry) nil
   (tui-entry-custom-options entry)
   (list
    :running-p nil
    :exit-code (user-bash-result-exit-code result)
    :cancelled-p (user-bash-result-cancelled-p result)
    :truncated-p (user-bash-result-truncated-p result)
    :full-output-path (user-bash-result-full-output-path result)
    :exclude-from-context-p
    (user-bash-result-exclude-from-context-p result)))
  (invalidate-tui-entry-render-cache entry))

(defun complete-tui-user-bash-string (entry text)
  (setf
   (tui-entry-text entry) text
   (tui-entry-streaming-p entry) nil
   (getf (tui-entry-custom-options entry) :running-p) nil
   (getf (tui-entry-custom-options entry) :exit-code) 0)
  (invalidate-tui-entry-render-cache entry))

(defun stop-tui-user-bash-entry (entry)
  (setf
   (tui-entry-streaming-p entry) nil
   (getf (tui-entry-custom-options entry) :running-p) nil)
  (invalidate-tui-entry-render-cache entry))

(defun append-tui-user-bash-result (state result)
  (let ((entry
          (make-tui-user-bash-entry
           state
           (user-bash-result-command result)
           (user-bash-result-exclude-from-context-p result))))
    (append-tui-entry state entry)
    (complete-tui-user-bash-entry entry result)))
