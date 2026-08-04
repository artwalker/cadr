(in-package #:cadr-cli)

(defun set-tui-keyed-lines
    (entries key lines)
  (if lines
      (acons
       key (copy-list lines)
       (remove key entries
               :key #'car
               :test #'string=))
      (remove key entries
              :key #'car
              :test #'string=)))

(defun set-tui-widget
    (state key lines placement)
  (ecase placement
    (:above-editor
     (setf
      (tui-state-widgets-above state)
      (set-tui-keyed-lines
       (tui-state-widgets-above state)
       key lines)))
    (:below-editor
     (setf
      (tui-state-widgets-below state)
      (set-tui-keyed-lines
       (tui-state-widgets-below state)
       key lines))))
  state)

(defun render-tui-widgets
    (entries width &key spacer-when-empty-p leading-spacer-p)
  (if
      (null entries)
      (and spacer-when-empty-p (list ""))
      (nconc
       (and leading-spacer-p (list ""))
       (loop for entry in
             (sort (copy-list entries)
                   #'string< :key #'car)
             append
             (loop for line in (cdr entry)
                   append
                   (cadr-tui:wrap-text line width))))))

(defun replace-tui-entries (state entries)
  (dolist (entry (tui-state-entries state))
    (when (tui-entry-custom-component entry)
      (ignore-errors
        (cadr-tui:component-dispose
         (tui-entry-custom-component entry)))))
  (let ((tail (last entries)))
    (setf
     (tui-state-entries state) entries
     (tui-state-entries-tail state) tail
     (tui-state-entries-tail-head state) entries))
  state)

(defun append-tui-entry (state entry)
  (let* ((entries (tui-state-entries state))
         (tail (tui-state-entries-tail state))
         (cell (list entry)))
    (cond
      ((null entries)
       (setf
        (tui-state-entries state) cell
        (tui-state-entries-tail state) cell
        (tui-state-entries-tail-head state) cell))
      ((and tail
            (eq entries
                (tui-state-entries-tail-head state))
            (null (cdr tail)))
       (setf
        (cdr tail) cell
        (tui-state-entries-tail state) cell))
      (t
       ;; Internal fixtures historically SETF ENTRIES directly. Repair that
       ;; boundary once; production replacements use REPLACE-TUI-ENTRIES.
       (let ((recovered-tail (last entries)))
         (setf
          (cdr recovered-tail) cell
          (tui-state-entries-tail state) cell
          (tui-state-entries-tail-head state)
          entries)))))
  entry)

(defun invalidate-tui-entry-render-cache (entry)
  (setf
   (tui-entry-render-cache-valid-p entry) nil
   (tui-entry-render-cache-width entry) nil
   (tui-entry-render-cache-theme entry) nil
   (tui-entry-render-cache-extension-snapshot entry)
   nil
   (tui-entry-render-cache-lines entry) nil)
  entry)

(defun add-tui-message-entry (state type text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (append-tui-entry
       state
       (make-tui-entry
        :type type
        :text trimmed))))
  state)

(defun add-tui-status (state text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (let ((last-entry
              (and (tui-state-entries state)
                   (car (tui-state-entries-tail state)))))
        (if (and last-entry
                 (eq (tui-entry-type last-entry) :status))
            (progn
              (setf (tui-entry-text last-entry) trimmed)
              (invalidate-tui-entry-render-cache last-entry))
            (append-tui-entry
             state
             (make-tui-entry
              :type :status
              :text trimmed))))))
  state)

(defun add-tui-notice (state text)
  ;; NOTICE carries arbitrary frontend output.  It uses the same visual shape
  ;; as baseline status text, but must not coalesce adjacent lines.
  (add-tui-message-entry state :notice text))

(defun add-tui-error (state text)
  (add-tui-message-entry state :error text))

(defun add-tui-warning (state text)
  (add-tui-message-entry state :warning text))

(defun add-tui-success (state text)
  (add-tui-message-entry state :success text))

(defun terminal-hyperlink (url label)
  (format nil "~C]8;;~A~C~A~C]8;;~C"
          #\Escape url (code-char 7) label
          #\Escape (code-char 7)))

(defun render-auth-url-lines (url width)
  (let* ((linked
           (cadr-tui:theme-foreground
            :accent
            (terminal-hyperlink url url)
            :enabled-p t))
         (hint
           (cadr-tui:theme-foreground
            :dim
            (terminal-hyperlink
             url "Ctrl+click to open")
            :enabled-p t)))
    (append
     (cadr-tui:wrap-text linked width)
     (list hint))))

(defun add-tui-auth-url (state url)
  (append-tui-entry
   state
   (make-tui-entry
    :type :auth-url
    :text url))
  state)

(defun startup-resource-names (resources accessor)
  (mapcar accessor resources))

(defun make-tui-startup-lines
    (resources
     &key (version (cadr-ai::cadr-version)))
  (labels
      ((section (title names)
         (when names
           (list
            (format nil "[~A]" title)
            (format nil "  ~{~A~^, ~}"
                    (sort
                     (remove-duplicates
                      (copy-list names)
                      :test #'string=)
                     #'string<)))))
       (sections ()
         (append
          (section
           "Skills"
           (startup-resource-names
            (resource-snapshot-skills resources)
            #'cadr-agent:skill-name))
          (section
           "Prompt Templates"
           (startup-resource-names
            (resource-snapshot-prompts resources)
            #'cadr-agent:prompt-template-name))
          (section
           "Themes"
           (startup-resource-names
            (resource-snapshot-themes resources)
            (lambda (theme)
              (or (getf theme :name) "unnamed"))))
          (section
           "Context"
           (mapcar
            #'namestring
            (resource-snapshot-context-files
             resources))))))
    (let* ((logo (format nil "cadr v~A" version))
           (compact
             (list
              logo
              "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more"
              "Press ctrl+o to show full startup help and loaded resources."
              ""
              "Cadr can explain its own features and look up its docs. Ask it how to use or extend Cadr."))
           (expanded
             (append
              (list
               logo
               "escape to interrupt"
               "ctrl+c to clear"
               "ctrl+c twice to exit"
               "ctrl+d to exit (empty)"
               "ctrl+z to suspend"
               "ctrl+k to delete to end"
               "ctrl+p/ctrl+n to cycle models"
               "ctrl+o to expand tools"
               "/ for commands"
               "! to run bash"
               ""
               "Cadr can explain its own features and look up its docs. Ask it how to use or extend Cadr.")
              (when (sections)
                (cons "" (sections))))))
      (values
       (append compact
               (when (sections)
                 (cons "" (sections))))
       expanded))))

(defun render-tui-startup-lines (lines width)
  (labels
      ((key-hint (key description)
         (concatenate
          'string
          (cadr-tui:theme-foreground
           :dim key :enabled-p t)
          (cadr-tui:theme-foreground
           :muted
           (format nil " ~A" description)
           :enabled-p t)))
       (compact-help ()
         (format
          nil "~{~A~^~A~}"
          (list
           (key-hint "escape" "interrupt")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "ctrl+c/ctrl+d" "clear/exit")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "/" "commands")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "!" "bash")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "ctrl+o" "more"))))
       (expanded-help (line)
         (let ((parts
                 (assoc
                  line
                  '(("escape to interrupt" "escape" "to interrupt")
                    ("ctrl+c to clear" "ctrl+c" "to clear")
                    ("ctrl+c twice to exit" "ctrl+c twice" "to exit")
                    ("ctrl+d to exit (empty)" "ctrl+d" "to exit (empty)")
                    ("ctrl+z to suspend" "ctrl+z" "to suspend")
                    ("ctrl+k to delete to end" "ctrl+k" "to delete to end")
                    ("ctrl+p/ctrl+n to cycle models" "ctrl+p/ctrl+n" "to cycle models")
                    ("ctrl+o to expand tools" "ctrl+o" "to expand tools")
                    ("/ for commands" "/" "for commands")
                    ("! to run bash" "!" "to run bash"))
                  :test #'string=)))
           (and parts
                (key-hint (second parts) (third parts)))))
       (style-line (line index)
         (cond
           ((zerop index)
            (let ((split (position #\Space line)))
              (if split
                  (concatenate
                   'string
                   (cadr-tui:theme-bold
                    (cadr-tui:theme-foreground
                     :accent (subseq line 0 split)
                     :enabled-p t))
                   (cadr-tui:theme-foreground
                    :dim (subseq line split)
                    :enabled-p t))
                  (cadr-tui:theme-bold
                   (cadr-tui:theme-foreground
                    :accent line :enabled-p t)))))
           ((string=
             line
             "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more")
            (compact-help))
           ((expanded-help line))
           ((and
             (plusp (length line))
             (char= (char line 0) #\[))
            (cadr-tui:theme-foreground
             :md-heading line :enabled-p t))
           (t
            (cadr-tui:theme-foreground
             :dim line :enabled-p t)))))
    (when lines
      (cadr-tui:component-render
       (cadr-tui:make-text-component
        (format
         nil "~{~A~^~%~}"
         (loop for line in lines
               for index from 0
               collect (style-line line index)))
        :padding-x 1 :padding-y 0)
       width))))
