(in-package #:cadr-tui)

(defparameter +builtin-theme-color-keys+
  '(:accent
    :border
    :border-accent
    :border-muted
    :success
    :error
    :warning
    :muted
    :dim
    :text
    :thinking-text
    :selected-bg
    :scrollbar-track
    :scrollbar-thumb
    :search-match-bg
    :search-match-text
    :user-message-bg
    :user-message-text
    :custom-message-bg
    :custom-message-text
    :custom-message-label
    :tool-pending-bg
    :tool-success-bg
    :tool-error-bg
    :tool-title
    :tool-output
    :md-heading
    :md-link
    :md-link-url
    :md-code
    :md-code-block
    :md-code-block-border
    :md-quote
    :md-quote-border
    :md-hr
    :md-list-bullet
    :tool-diff-added
    :tool-diff-removed
    :tool-diff-context
    :syntax-comment
    :syntax-keyword
    :syntax-function
    :syntax-variable
    :syntax-string
    :syntax-number
    :syntax-type
    :syntax-operator
    :syntax-punctuation
    :thinking-off
    :thinking-minimal
    :thinking-low
    :thinking-medium
    :thinking-high
    :thinking-xhigh
    :thinking-max
    :bash-mode
    :page-bg
    :card-bg
    :info-bg))

(defparameter +dark-theme-colors+ nil)

(defparameter +light-theme-colors+ nil)

(defvar *install-builtin-theme-colors* nil)

(defun ensure-builtin-theme-colors ()
  (when *install-builtin-theme-colors*
    (funcall *install-builtin-theme-colors*)))

(defun theme-json-name (key)
  (let ((parts
          (uiop:split-string
           (string-downcase (symbol-name key))
           :separator '(#\-))))
    (with-output-to-string (output)
      (write-string (first parts) output)
      (dolist (part (rest parts))
        (unless (zerop (length part))
          (write-char (char-upcase (char part 0)) output)
          (write-string (subseq part 1) output))))))

(defun builtin-theme-json-text (name)
  (let ((text
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui"
            (format nil
                    "src/cadr-tui/theme/~(~A~).json"
                    name))
           :external-format :utf-8)))
    (if (and (plusp (length text))
             (char= (char text 0) #\ufeff))
        (subseq text 1)
        text)))

(defun skip-json-whitespace (text index)
  (loop while (and (< index (length text))
                   (member (char text index)
                           '(#\Space #\Tab #\Newline #\Return)))
        do (incf index))
  index)

(defun read-json-hex4 (text index)
  (unless (<= (+ index 4) (length text))
    (error "Truncated JSON unicode escape at ~D" index))
  (values
   (parse-integer text :start index :end (+ index 4) :radix 16)
   (+ index 4)))

(defun read-json-string (text index)
  (unless (char= (char text index) #\")
    (error "JSON string expected at ~D" index))
  (let ((output (make-string-output-stream)))
    (incf index)
    (loop
      (when (>= index (length text))
        (error "Unterminated JSON string"))
      (let ((character (char text index)))
        (cond
          ((char= character #\")
           (return (values (get-output-stream-string output)
                           (1+ index))))
          ((char= character #\\)
           (incf index)
           (when (>= index (length text))
             (error "Truncated JSON string escape"))
           (let ((escaped (char text index)))
             (case escaped
               (#\" (write-char #\" output))
               (#\\ (write-char #\\ output))
               (#\/ (write-char #\/ output))
               (#\b (write-char #\Backspace output))
               (#\f (write-char #\Page output))
               (#\n (write-char #\Newline output))
               (#\r (write-char #\Return output))
               (#\t (write-char #\Tab output))
               (#\u
                (multiple-value-bind (code next)
                    (read-json-hex4 text (1+ index))
                  (write-char (code-char code) output)
                  (setf index (1- next))))
               (otherwise
                (error "Invalid JSON string escape ~S" escaped))))
           (incf index))
          (t
           (write-char character output)
           (incf index)))))))

(defun read-json-number (text index)
  (let ((start index)
        (limit (length text)))
    (when (and (< index limit) (char= (char text index) #\-))
      (incf index))
    (unless (and (< index limit)
                 (digit-char-p (char text index)))
      (error "Invalid JSON number at ~D" start))
    (if (char= (char text index) #\0)
        (incf index)
        (loop while (and (< index limit)
                         (digit-char-p (char text index)))
              do (incf index)))
    (when (and (< index limit) (char= (char text index) #\.))
      (incf index)
      (unless (and (< index limit)
                   (digit-char-p (char text index)))
        (error "Invalid JSON number at ~D" start))
      (loop while (and (< index limit)
                       (digit-char-p (char text index)))
            do (incf index)))
    (when (and (< index limit)
               (member (char text index) '(#\e #\E)))
      (incf index)
      (when (and (< index limit)
                 (member (char text index) '(#\+ #\-)))
        (incf index))
      (unless (and (< index limit)
                   (digit-char-p (char text index)))
        (error "Invalid JSON number at ~D" start))
      (loop while (and (< index limit)
                       (digit-char-p (char text index)))
            do (incf index)))
    (let ((token (subseq text start index)))
      (values
       (if (every (lambda (character)
                    (or (digit-char-p character)
                        (char= character #\-)))
                  token)
           (parse-integer token)
           (let ((*read-default-float-format* 'double-float))
             (float (read-from-string token) 1d0)))
       index))))

(defun read-json-literal (text index expected value)
  (let ((end (+ index (length expected))))
    (unless (and (<= end (length text))
                 (string= text expected :start1 index :end1 end))
      (error "Invalid JSON literal at ~D" index))
    (values value end)))

(defun read-json-value (text index)
  (setf index (skip-json-whitespace text index))
  (when (>= index (length text))
    (error "Unexpected end of JSON"))
  (let ((character (char text index)))
    (cond
      ((char= character #\")
       (read-json-string text index))
      ((char= character #\{)
       (read-json-object text index))
      ((char= character #\[)
       (read-json-array text index))
      ((or (digit-char-p character) (char= character #\-))
       (read-json-number text index))
      ((char= character #\t)
       (read-json-literal text index "true" t))
      ((char= character #\f)
       (read-json-literal text index "false" nil))
      ((char= character #\n)
       (read-json-literal text index "null" nil))
      (t
       (error "Invalid JSON value at ~D" index)))))

(defun read-json-array (text index)
  (let ((values nil))
    (incf index)
    (setf index (skip-json-whitespace text index))
    (unless (and (< index (length text))
                 (char= (char text index) #\]))
      (loop
        (multiple-value-bind (value next)
            (read-json-value text index)
          (push value values)
          (setf index (skip-json-whitespace text next)))
        (when (>= index (length text))
          (error "Unterminated JSON array"))
        (cond
          ((char= (char text index) #\])
           (return))
          ((char= (char text index) #\,)
           (incf index))
          (t
           (error "JSON array expected comma or ] at ~D" index)))))
    (values (coerce (nreverse values) 'vector) (1+ index))))

(defun read-json-object (text index)
  (let ((object (make-hash-table :test #'equal)))
    (incf index)
    (setf index (skip-json-whitespace text index))
    (unless (and (< index (length text))
                 (char= (char text index) #\}))
      (loop
        (setf index (skip-json-whitespace text index))
        (multiple-value-bind (key next)
            (read-json-string text index)
          (setf index (skip-json-whitespace text next))
          (unless (and (< index (length text))
                       (char= (char text index) #\:))
            (error "JSON object expected : at ~D" index))
          (multiple-value-bind (value after)
              (read-json-value text (1+ index))
            (setf (gethash key object) value
                  index (skip-json-whitespace text after))))
        (when (>= index (length text))
          (error "Unterminated JSON object"))
        (cond
          ((char= (char text index) #\})
           (return))
          ((char= (char text index) #\,)
           (incf index))
          (t
           (error "JSON object expected comma or } at ~D" index)))))
    (values object (1+ index))))

(defun read-theme-json (text)
  (multiple-value-bind (value index)
      (read-json-value text 0)
    (setf index (skip-json-whitespace text index))
    (unless (= index (length text))
      (error "Trailing JSON at ~D" index))
    (unless (hash-table-p value)
      (error "Theme JSON must be an object"))
    value))

(defparameter +background-theme-color-keys+
  '(:selected-bg
    :scrollbar-track
    :scrollbar-thumb
    :search-match-bg
    :user-message-bg
    :custom-message-bg
    :tool-pending-bg
    :tool-success-bg
    :tool-error-bg
    :page-bg
    :card-bg
    :info-bg))

(defparameter +ansi-cube-values+
  #(0 95 135 175 215 255))

(defparameter +ansi-gray-values+
  (coerce
   (loop for index below 24
         collect (+ 8 (* index 10)))
   'vector))

(defstruct (terminal-theme
            (:constructor %make-terminal-theme))
  (name :dark :type keyword)
  (colors (make-hash-table :test #'eq)
          :type hash-table)
  (color-mode :256color
              :type (member :truecolor :256color))
  (enabled-p t :type boolean)
  (dim-keys nil :type list))

(defparameter *current-theme* nil)

(defun terminal-theme-color-keys (theme)
  (declare (ignore theme))
  (ensure-builtin-theme-colors)
  (mapcar #'car +dark-theme-colors+))

(defun parse-theme-hex-color (text)
  (unless
      (and (stringp text)
           (= (length text) 7)
           (char= (char text 0) #\#)
           (every
            (lambda (character)
              (digit-char-p character 16))
            (subseq text 1)))
    (error "Invalid hex color: ~S" text))
  (make-rgb-color
   :red (parse-integer text
                       :start 1 :end 3 :radix 16)
   :green (parse-integer text
                         :start 3 :end 5 :radix 16)
   :blue (parse-integer text
                        :start 5 :end 7 :radix 16)))

(defun closest-vector-index (value candidates)
  (loop with closest-index = 0
        with closest-distance = most-positive-fixnum
        for candidate across candidates
        for index from 0
        for distance = (abs (- value candidate))
        when (< distance closest-distance)
          do (setf closest-index index
                   closest-distance distance)
        finally (return closest-index)))

(defun weighted-color-distance
    (red green blue candidate-red candidate-green
     candidate-blue)
  (+ (* 0.299d0
        (expt (- red candidate-red) 2))
     (* 0.587d0
        (expt (- green candidate-green) 2))
     (* 0.114d0
        (expt (- blue candidate-blue) 2))))

(defun valid-rgb-channel-p (value)
  (and (integerp value) (<= 0 value 255)))

(defun rgb-to-ansi-256 (red green blue)
  (unless (and (valid-rgb-channel-p red)
               (valid-rgb-channel-p green)
               (valid-rgb-channel-p blue))
    (error "RGB channels must be integers from 0 through 255"))
  (let* ((red-index
           (closest-vector-index red +ansi-cube-values+))
         (green-index
           (closest-vector-index green +ansi-cube-values+))
         (blue-index
           (closest-vector-index blue +ansi-cube-values+))
         (cube-red (aref +ansi-cube-values+ red-index))
         (cube-green (aref +ansi-cube-values+ green-index))
         (cube-blue (aref +ansi-cube-values+ blue-index))
         (cube-index
           (+ 16 (* 36 red-index)
              (* 6 green-index) blue-index))
         (cube-distance
           (weighted-color-distance
            red green blue cube-red cube-green cube-blue))
         (gray
           ;; JavaScript's Math.round, used by the baseline, rounds
           ;; non-negative half values upward rather than to even.
           (floor
            (+ (* 0.299d0 red)
               (* 0.587d0 green)
               (* 0.114d0 blue)
               0.5d0)))
         (gray-ramp-index
           (closest-vector-index gray +ansi-gray-values+))
         (gray-value
           (aref +ansi-gray-values+ gray-ramp-index))
         (gray-index (+ 232 gray-ramp-index))
         (gray-distance
           (weighted-color-distance
            red green blue
            gray-value gray-value gray-value))
         (spread
           (- (max red green blue)
              (min red green blue))))
    (if (and (< spread 10)
             (< gray-distance cube-distance))
        gray-index
        cube-index)))

(defun ensure-theme-keyword (value)
  (etypecase value
    (keyword value)
    (symbol
     (intern (string-upcase (symbol-name value)) :keyword))
    (string
     (intern (string-upcase value) :keyword))))

(defun canonical-theme-name (name)
  (let ((canonical (ensure-theme-keyword name)))
    (unless (member canonical '(:dark :light))
      (error "Unknown built-in theme: ~S" name))
    canonical))

(defun canonical-theme-color-key (key)
  (let* ((source
           (etypecase key
             (symbol (symbol-name key))
             (string key)))
         (canonical
           (with-output-to-string (output)
             (loop for character across source
                   for index from 0
                   for previous =
                     (and (plusp index)
                          (char source (1- index)))
                   do
                   (cond
                     ((member character
                              '(#\_ #\Space #\Tab))
                      (unless
                          (or (zerop index)
                              (char= previous #\-))
                        (write-char #\- output)))
                     ((and (upper-case-p character)
                           (plusp index)
                           previous
                           (or (lower-case-p previous)
                               (digit-char-p previous)))
                      (write-char #\- output)
                      (write-char character output))
                     (t
                      (write-char character output)))))))
    (intern (string-upcase canonical) :keyword)))

(defun valid-theme-color-value-p (value)
  (or (and (integerp value) (<= 0 value 255))
      (and (stringp value)
           (or (string= value "")
               (handler-case
                   (progn
                     (parse-theme-hex-color value)
                     t)
                 (error () nil))))))

(defun override-entry-value (entry)
  (if (and (consp (cdr entry))
           (null (cddr entry)))
      (cadr entry)
      (cdr entry)))

(defun map-theme-overrides (function overrides)
  (cond
    ((null overrides) nil)
    ((hash-table-p overrides)
     (maphash function overrides))
    ((and (listp overrides)
          (every #'consp overrides))
     (dolist (entry overrides)
       (funcall function
                (car entry)
                (override-entry-value entry))))
    ((listp overrides)
     (unless (evenp (length overrides))
       (error "Theme override plist has odd length"))
     (loop for (key value) on overrides by #'cddr
           do (funcall function key value)))
    (t
     (error "Theme overrides must be an alist, plist, or hash table"))))

(defun make-terminal-theme
    (name &key overrides
               (capabilities (get-terminal-capabilities))
               (enabled-p t)
               dim-keys)
  (ensure-builtin-theme-colors)
  (let* ((canonical-name (canonical-theme-name name))
         (base
           (ecase canonical-name
             (:dark +dark-theme-colors+)
             (:light +light-theme-colors+)))
         (colors (make-hash-table :test #'eq)))
    (dolist (entry base)
      (setf (gethash (car entry) colors)
            (cdr entry)))
    (map-theme-overrides
     (lambda (key value)
       (let ((canonical-key
               (canonical-theme-color-key key)))
         (unless (nth-value 1
                           (gethash canonical-key colors))
           (error "Unknown semantic theme color: ~S" key))
         (unless (valid-theme-color-value-p value)
           (error "Invalid theme color value for ~S: ~S"
                  key value))
         (setf (gethash canonical-key colors) value)))
     overrides)
    (%make-terminal-theme
     :name canonical-name
     :colors colors
     :color-mode
     (if (terminal-capabilities-true-color-p capabilities)
         :truecolor
         :256color)
     :enabled-p (not (null enabled-p))
     :dim-keys
     (mapcar #'canonical-theme-color-key dim-keys))))

(defun theme-stored-color (key theme)
  (let ((canonical-key
          (canonical-theme-color-key key)))
    (multiple-value-bind (value present-p)
        (gethash canonical-key
                 (terminal-theme-colors theme))
      (unless present-p
        (error "Unknown semantic theme color: ~S" key))
      (values value canonical-key))))

(defun guessed-default-color (appearance slot)
  ;; v1.4.0 theme.ts GUESSED_DEFAULT_COLORS (567469096). Empty tokens
  ;; still render as SGR 39/49; this table is only the concrete color.
  (ecase appearance
    (:dark
     (ecase slot
       (:foreground "#e5e5e7")
       (:background "#000000")))
    (:light
     (ecase slot
       (:foreground "#000000")
       (:background "#ffffff")))))

(defvar *terminal-default-colors*
  '(:foreground nil :background nil))

(defun copy-terminal-default-channel (channels)
  (when channels
    (unless (and (listp channels)
                 (= (length channels) 3)
                 (every (lambda (channel)
                          (and (integerp channel)
                               (<= 0 channel 255)))
                        channels))
      (error "Terminal default color must be three integers from 0 through 255: ~S"
             channels))
    (copy-list channels)))

(defun set-terminal-default-colors (&key foreground background)
  (setf *terminal-default-colors*
        (list :foreground
              (copy-terminal-default-channel foreground)
              :background
              (copy-terminal-default-channel background))))

(defun reported-terminal-default-hex (slot)
  (let ((channels (getf *terminal-default-colors* slot)))
    (when channels
      (format nil "#~(~2,'0x~2,'0x~2,'0x~)"
              (first channels)
              (second channels)
              (third channels)))))

(defun resolved-empty-theme-color (theme canonical-key)
  (let ((slot
          (if (member canonical-key
                      +background-theme-color-keys+)
              :background
              :foreground)))
    (or (reported-terminal-default-hex slot)
        (guessed-default-color
         (terminal-theme-name theme)
         slot))))

(defun theme-color-value
    (key &key (theme (current-theme)))
  (multiple-value-bind (value canonical-key)
      (theme-stored-color key theme)
    (if (and (stringp value) (string= value ""))
        (resolved-empty-theme-color theme canonical-key)
        value)))

(defun effective-theme-enabled-p
    (theme enabled-p enabled-p-supplied-p)
  (if enabled-p-supplied-p
      (not (null enabled-p))
      (terminal-theme-enabled-p theme)))

(defun theme-color-ansi
    (key background-p theme enabled-p)
  (let* ((canonical-key
           (canonical-theme-color-key key))
         (background-key-p
           (member canonical-key
                   +background-theme-color-keys+))
         (value
           (theme-stored-color canonical-key theme)))
    (unless (eq (not (null background-p))
                (not (null background-key-p)))
      (error "Semantic theme color ~S is not a ~A token"
             key
             (if background-p
                 "background"
                 "foreground")))
    (unless enabled-p
      (return-from theme-color-ansi ""))
    (let ((base (if background-p 48 38)))
      (cond
        ((and (stringp value) (string= value ""))
         (format nil "~C[~Dm" #\Escape
                 (if background-p 49 39)))
        ((integerp value)
         (format nil "~C[~D;5;~Dm"
                 #\Escape base value))
        (t
         (let ((color (parse-theme-hex-color value)))
           (if (eq :truecolor
                   (terminal-theme-color-mode theme))
               (format nil "~C[~D;2;~D;~D;~Dm"
                       #\Escape base
                       (rgb-color-red color)
                       (rgb-color-green color)
                       (rgb-color-blue color))
               (format nil "~C[~D;5;~Dm"
                       #\Escape base
                       (rgb-to-ansi-256
                        (rgb-color-red color)
                        (rgb-color-green color)
                        (rgb-color-blue color))))))))))

(defun theme-foreground-ansi
    (key &key (theme (current-theme))
              (enabled-p nil enabled-p-supplied-p))
  (theme-color-ansi
   key nil theme
   (effective-theme-enabled-p
    theme enabled-p enabled-p-supplied-p)))

(defun theme-background-ansi
    (key &key (theme (current-theme))
              (enabled-p nil enabled-p-supplied-p))
  (theme-color-ansi
   key t theme
   (effective-theme-enabled-p
    theme enabled-p enabled-p-supplied-p)))

(defun theme-foreground
    (key text &key (theme (current-theme))
                    (enabled-p nil enabled-p-supplied-p))
  (let ((enabled-p
          (effective-theme-enabled-p
           theme enabled-p enabled-p-supplied-p)))
    (if enabled-p
        (concatenate
         'string
         (theme-foreground-ansi
          key :theme theme :enabled-p t)
         (if (member (canonical-theme-color-key key)
                     (terminal-theme-dim-keys theme))
             (format nil "~C[2m~A~C[22;39m" #\Escape text #\Escape)
             (concatenate 'string text
                          (format nil "~C[39m" #\Escape))))
        (progn
          (theme-foreground-ansi
           key :theme theme :enabled-p nil)
          text))))

(defun theme-background
    (key text &key (theme (current-theme))
                    (enabled-p nil enabled-p-supplied-p))
  (let ((enabled-p
          (effective-theme-enabled-p
           theme enabled-p enabled-p-supplied-p)))
    (if enabled-p
        (concatenate
         'string
         (theme-background-ansi
          key :theme theme :enabled-p t)
         text
         (format nil "~C[49m" #\Escape))
        (progn
          (theme-background-ansi
           key :theme theme :enabled-p nil)
          text))))

(defun theme-style
    (text start-code end-code theme
     enabled-p enabled-p-supplied-p)
  (if (effective-theme-enabled-p
       theme enabled-p enabled-p-supplied-p)
      (format nil "~C[~Am~A~C[~Am"
              #\Escape start-code text
              #\Escape end-code)
      text))

(defun theme-bold
    (text &key (theme (current-theme))
               (enabled-p nil enabled-p-supplied-p))
  (theme-style text 1 22 theme
               enabled-p enabled-p-supplied-p))

(defun theme-italic
    (text &key (theme (current-theme))
               (enabled-p nil enabled-p-supplied-p))
  (theme-style text 3 23 theme
               enabled-p enabled-p-supplied-p))

(defun theme-underline
    (text &key (theme (current-theme))
               (enabled-p nil enabled-p-supplied-p))
  (theme-style text 4 24 theme
               enabled-p enabled-p-supplied-p))

(defun theme-inverse
    (text &key (theme (current-theme))
               (enabled-p nil enabled-p-supplied-p))
  (theme-style text 7 27 theme
               enabled-p enabled-p-supplied-p))

(defun theme-thinking-color-key (level)
  (case (ensure-theme-keyword level)
    (:off :thinking-off)
    (:minimal :thinking-minimal)
    (:low :thinking-low)
    (:medium :thinking-medium)
    (:high :thinking-high)
    (:xhigh :thinking-xhigh)
    (:max :thinking-max)
    (otherwise :thinking-off)))

(defun theme-thinking-foreground
    (level text &key (theme (current-theme))
                     (enabled-p nil enabled-p-supplied-p))
  (theme-foreground
   (theme-thinking-color-key level) text
   :theme theme
   :enabled-p
   (effective-theme-enabled-p
    theme enabled-p enabled-p-supplied-p)))

(defun theme-bash-mode-foreground
    (text &key (theme (current-theme))
               (enabled-p nil enabled-p-supplied-p))
  (theme-foreground
   :bash-mode text
   :theme theme
   :enabled-p
   (effective-theme-enabled-p
    theme enabled-p enabled-p-supplied-p)))

(defun set-current-theme
    (theme-or-name &key overrides capabilities
                        (enabled-p t)
                        dim-keys)
  (setf *current-theme*
        (if (terminal-theme-p theme-or-name)
            (progn
              (when (or overrides capabilities
                        (not enabled-p))
                (error "A terminal theme instance cannot be combined with construction options"))
              theme-or-name)
            (make-terminal-theme
             theme-or-name
             :overrides overrides
             :capabilities
             (or capabilities
                 (get-terminal-capabilities))
             :enabled-p enabled-p
             :dim-keys dim-keys))))

(defun reset-current-theme ()
  (setf *current-theme*
        (make-terminal-theme :dark)))

(defun current-theme ()
  (or *current-theme*
      (reset-current-theme)))
