(defparameter *plan-mode-destructive-patterns*
  '("(?i)\\brm\\b" "(?i)\\brmdir\\b" "(?i)\\bmv\\b"
    "(?i)\\bcp\\b" "(?i)\\bmkdir\\b" "(?i)\\btouch\\b"
    "(?i)\\b(chmod|chown|chgrp|ln|tee|truncate|dd|shred)\\b"
    "(^|[^<])>(?!>)" ">>"
    "(?i)\\bnpm\\s+(install|uninstall|update|ci|link|publish)"
    "(?i)\\b(yarn|pnpm)\\s+(add|remove|install|publish)"
    "(?i)\\bpip\\s+(install|uninstall)"
    "(?i)\\bapt(-get)?\\s+(install|remove|purge|update|upgrade)"
    "(?i)\\bbrew\\s+(install|uninstall|upgrade)"
    "(?i)\\bgit\\s+(add|commit|push|pull|merge|rebase|reset|checkout|branch\\s+-[dD]|stash|cherry-pick|revert|tag|init|clone)"
    "(?i)\\b(sudo|su|kill|pkill|killall|reboot|shutdown)\\b"
    "(?i)\\bsystemctl\\s+(start|stop|restart|enable|disable)"
    "(?i)\\bservice\\s+\\S+\\s+(start|stop|restart)"
    "(?i)\\b(vim?|nano|emacs|code|subl)\\b"))

(defparameter *plan-mode-safe-patterns*
  '("^\\s*(cat|head|tail|less|more|grep|find|ls|pwd|echo|printf|wc|sort|uniq|diff|file|stat|du|df|tree|which|whereis|type|env|printenv|uname|whoami|id|date|cal|uptime|ps|top|htop|free)\\b"
    "(?i)^\\s*git\\s+(status|log|diff|show|branch|remote|config\\s+--get)"
    "(?i)^\\s*git\\s+ls-"
    "(?i)^\\s*npm\\s+(list|ls|view|info|search|outdated|audit)"
    "(?i)^\\s*yarn\\s+(list|info|why|audit)"
    "(?i)^\\s*(node|python)\\s+--version"
    "(?i)^\\s*curl\\s" "(?i)^\\s*wget\\s+-O\\s*-"
    "^\\s*(jq|awk|rg|fd|bat|eza)\\b" "^\\s*sed\\s+-n"))

(defun plan-mode-trim (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun plan-mode-safe-command-p (command)
  (and
   (not (find-if (lambda (pattern) (cl-ppcre:scan pattern command))
                 *plan-mode-destructive-patterns*))
   (not (null
         (find-if (lambda (pattern) (cl-ppcre:scan pattern command))
                  *plan-mode-safe-patterns*)))))

(defun plan-mode-clean-step-text (text)
  (let* ((cleaned
           (cl-ppcre:regex-replace-all
            "\\s+"
            (cl-ppcre:regex-replace
             "(?i)^(Use|Run|Execute|Create|Write|Read|Check|Verify|Update|Modify|Add|Remove|Delete|Install)\\s+(the\\s+)?"
             (cl-ppcre:regex-replace-all
              "`([^`]+)`"
              (cl-ppcre:regex-replace-all
               "\\*{1,2}([^*]+)\\*{1,2}" text "\\1")
              "\\1")
             "")
            " "))
         (trimmed (plan-mode-trim cleaned)))
    (when (plusp (length trimmed))
      (setf (char trimmed 0) (char-upcase (char trimmed 0))))
    (if (> (length trimmed) 50)
        (format nil "~A..." (subseq trimmed 0 47))
        trimmed)))

(defstruct plan-mode-todo-item
  (step 0 :type (integer 0 *))
  (text "" :type string)
  (completed-p nil :type boolean))

(defun plan-mode-extract-todo-items (message)
  (multiple-value-bind (header-start header-end)
      (cl-ppcre:scan "(?im)\\*{0,2}Plan:\\*{0,2}\\s*\\n" message)
    (declare (ignore header-start))
    (unless header-end
      (return-from plan-mode-extract-todo-items nil))
    (let ((items nil)
          (position header-end)
          (pattern "(?m)^\\s*(\\d+)[.)]\\s+\\*{0,2}([^*\\n]+)"))
      (loop
        (multiple-value-bind (start end starts ends)
            (cl-ppcre:scan pattern message :start position)
          (unless start (return))
          (let* ((raw
                   (subseq message
                           (aref starts 1)
                           (aref ends 1)))
                 (trimmed
                   (plan-mode-trim
                    (cl-ppcre:regex-replace
                     "\\*{1,2}$" (plan-mode-trim raw) ""))))
            (when
                (and (> (length trimmed) 5)
                     (not (find (char trimmed 0) '(#\` #\/ #\-))))
              (let ((cleaned (plan-mode-clean-step-text trimmed)))
                (when (> (length cleaned) 3)
                  (push
                   (make-plan-mode-todo-item
                    :step (1+ (length items))
                    :text cleaned)
                   items)))))
          (setf position end)))
      (nreverse items))))

(defun plan-mode-extract-done-steps (message)
  (let ((steps nil))
    (cl-ppcre:do-register-groups (number)
        ("(?i)\\[DONE:(\\d+)\\]" message)
      (push (parse-integer number) steps))
    (nreverse steps)))

(defun plan-mode-mark-completed-steps (text items)
  (let ((steps (plan-mode-extract-done-steps text)))
    (dolist (step steps)
      (let ((item
              (find step items :key #'plan-mode-todo-item-step)))
        (when item
          (setf (plan-mode-todo-item-completed-p item) t))))
    (length steps)))
