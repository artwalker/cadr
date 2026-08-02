(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +interactive-shell-default-commands+
  '("vim" "nvim" "vi" "nano" "emacs" "pico" "micro" "helix" "hx" "kak"
    "less" "more" "most"
    "git commit" "git rebase" "git merge" "git cherry-pick" "git revert"
    "git add -p" "git add --patch" "git add -i" "git add --interactive"
    "git stash -p" "git stash --patch" "git reset -p" "git reset --patch"
    "git checkout -p" "git checkout --patch" "git difftool" "git mergetool"
    "htop" "top" "btop" "glances" "ranger" "nnn" "lf" "mc" "vifm"
    "tig" "lazygit" "gitui" "fzf" "sk" "ssh" "telnet" "mosh"
    "psql" "mysql" "sqlite3" "mongosh" "redis-cli"
    "kubectl edit" "kubectl exec -it" "docker exec -it" "docker run -it"
    "tmux" "screen" "ncdu"))

(defun interactive-shell-env-list (name)
  (remove-if
   (lambda (value) (zerop (length value)))
   (mapcar #'example-trim
           (uiop:split-string (or (uiop:getenv name) "")
                              :separator '(#\,)))))

(defun interactive-shell-commands ()
  (let ((excluded
          (mapcar #'string-downcase
                  (interactive-shell-env-list "INTERACTIVE_EXCLUDE"))))
    (remove-if
     (lambda (command)
       (member (string-downcase command) excluded :test #'string=))
     (append +interactive-shell-default-commands+
             (interactive-shell-env-list "INTERACTIVE_COMMANDS")))))

(defun interactive-shell-command-prefix-p (command prefix)
  (or (string= command prefix)
      (uiop:string-prefix-p (concatenate 'string prefix " ") command)
      (uiop:string-prefix-p (concatenate 'string prefix (string #\Tab)) command)))

(defun interactive-shell-command-p (command)
  (let* ((trimmed (string-downcase (example-trim command)))
         (pipe (position #\| trimmed :from-end t))
         (after-pipe (and pipe (example-trim (subseq trimmed (1+ pipe))))))
    (some
     (lambda (candidate)
       (let ((lower (string-downcase candidate)))
         (or (interactive-shell-command-prefix-p trimmed lower)
             (and after-pipe
                  (interactive-shell-command-prefix-p after-pipe lower)))))
     (interactive-shell-commands))))

(defun interactive-shell-run (tui command)
  (cadr-tui:tui-stop tui)
  (unwind-protect
       (progn
         (format t "~C[2J~C[H" #\Escape #\Escape)
         (finish-output)
         (uiop:launch-program
          (list (or (uiop:getenv "SHELL") "/bin/sh") "-c" command)
          :input t :output t :error-output t
          :wait nil))
    (cadr-tui:tui-start tui)
    (cadr-tui:tui-request-render tui t)))

(cadr-agent:define-event-hook
 :user-bash
 :handler
 (lambda (event context)
   (let* ((original (or (example-event-value event :command) ""))
          (force-p
            (or (uiop:string-prefix-p "i " original)
                (uiop:string-prefix-p
                 (concatenate 'string "i" (string #\Tab)) original)))
          (command (if force-p (example-trim (subseq original 2)) original)))
     (when (or force-p (interactive-shell-command-p command))
       (if (not (cadr-agent:extension-context-has-ui-p context))
           (list :result
                 (list :output "(interactive commands require TUI)"
                       :exit-code 1 :cancelled-p nil :truncated-p nil))
           (let ((status
                   (cadr-agent:extension-context-custom-component
                    context
                    (lambda (tui theme keybindings done)
                      (declare (ignore theme keybindings))
                      (let* ((process (interactive-shell-run tui command))
                             (code (or (uiop:wait-process process) 1)))
                        (funcall done code)
                        (cadr-tui:make-component-container))))))
             (list
              :result
              (list
               :output
               (if (zerop (or status 1))
                   "(interactive command completed successfully)"
                   (format nil "(interactive command exited with code ~D)"
                           (or status 1)))
               :exit-code (or status 1)
               :cancelled-p nil :truncated-p nil))))))))
