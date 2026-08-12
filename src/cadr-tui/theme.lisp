(in-package #:cadr-tui)

(defparameter +dark-theme-colors+
  '((:accent . "#8abeb7")
    (:border . "#5f87ff")
    (:border-accent . "#00d7ff")
    (:border-muted . "#505050")
    (:success . "#b5bd68")
    (:error . "#cc6666")
    (:warning . "#ffff00")
    (:muted . "#808080")
    (:dim . "#666666")
    (:text . "#d4d4d4")
    (:thinking-text . "#808080")
    (:selected-bg . "#3a3a4a")
    (:scrollbar-thumb . "#3a3a4a")
    (:user-message-bg . "#343541")
    (:user-message-text . "#d4d4d4")
    (:custom-message-bg . "#2d2838")
    (:custom-message-text . "#d4d4d4")
    (:custom-message-label . "#9575cd")
    (:tool-pending-bg . "#282832")
    (:tool-success-bg . "#283228")
    (:tool-error-bg . "#3c2828")
    (:tool-title . "#d4d4d4")
    (:tool-output . "#808080")
    (:md-heading . "#f0c674")
    (:md-link . "#81a2be")
    (:md-link-url . "#666666")
    (:md-code . "#8abeb7")
    (:md-code-block . "#b5bd68")
    (:md-code-block-border . "#808080")
    (:md-quote . "#808080")
    (:md-quote-border . "#808080")
    (:md-hr . "#808080")
    (:md-list-bullet . "#8abeb7")
    (:tool-diff-added . "#b5bd68")
    (:tool-diff-removed . "#cc6666")
    (:tool-diff-context . "#808080")
    (:syntax-comment . "#6A9955")
    (:syntax-keyword . "#569CD6")
    (:syntax-function . "#DCDCAA")
    (:syntax-variable . "#9CDCFE")
    (:syntax-string . "#CE9178")
    (:syntax-number . "#B5CEA8")
    (:syntax-type . "#4EC9B0")
    (:syntax-operator . "#D4D4D4")
    (:syntax-punctuation . "#D4D4D4")
    (:thinking-off . "#505050")
    (:thinking-minimal . "#6e6e6e")
    (:thinking-low . "#5f87af")
    (:thinking-medium . "#81a2be")
    (:thinking-high . "#b294bb")
    (:thinking-xhigh . "#d183e8")
    (:thinking-max . "#ff5fff")
    (:bash-mode . "#b5bd68")
    (:page-bg . "#18181e")
    (:card-bg . "#1e1e24")
    (:info-bg . "#3c3728")))

(defparameter +light-theme-colors+
  '((:accent . "#5a8080")
    (:border . "#547da7")
    (:border-accent . "#5a8080")
    (:border-muted . "#b0b0b0")
    (:success . "#588458")
    (:error . "#aa5555")
    (:warning . "#9a7326")
    (:muted . "#6c6c6c")
    (:dim . "#767676")
    (:text . "#1f2328")
    (:thinking-text . "#6c6c6c")
    (:selected-bg . "#d0d0e0")
    (:scrollbar-thumb . "#d0d0e0")
    (:user-message-bg . "#e8e8e8")
    (:user-message-text . "#1f2328")
    (:custom-message-bg . "#ede7f6")
    (:custom-message-text . "#1f2328")
    (:custom-message-label . "#7e57c2")
    (:tool-pending-bg . "#e8e8f0")
    (:tool-success-bg . "#e8f0e8")
    (:tool-error-bg . "#f0e8e8")
    (:tool-title . "#1f2328")
    (:tool-output . "#6c6c6c")
    (:md-heading . "#9a7326")
    (:md-link . "#547da7")
    (:md-link-url . "#767676")
    (:md-code . "#5a8080")
    (:md-code-block . "#588458")
    (:md-code-block-border . "#6c6c6c")
    (:md-quote . "#6c6c6c")
    (:md-quote-border . "#6c6c6c")
    (:md-hr . "#6c6c6c")
    (:md-list-bullet . "#588458")
    (:tool-diff-added . "#588458")
    (:tool-diff-removed . "#aa5555")
    (:tool-diff-context . "#6c6c6c")
    (:syntax-comment . "#008000")
    (:syntax-keyword . "#0000FF")
    (:syntax-function . "#795E26")
    (:syntax-variable . "#001080")
    (:syntax-string . "#A31515")
    (:syntax-number . "#098658")
    (:syntax-type . "#267F99")
    (:syntax-operator . "#000000")
    (:syntax-punctuation . "#000000")
    (:thinking-off . "#b0b0b0")
    (:thinking-minimal . "#767676")
    (:thinking-low . "#547da7")
    (:thinking-medium . "#5a8080")
    (:thinking-high . "#875f87")
    (:thinking-xhigh . "#8b008b")
    (:thinking-max . "#af005f")
    (:bash-mode . "#588458")
    (:page-bg . "#f8f8f8")
    (:card-bg . "#ffffff")
    (:info-bg . "#fffae6")))

(defparameter +background-theme-color-keys+
  '(:selected-bg
    :scrollbar-thumb
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
  (enabled-p t :type boolean))

(defparameter *current-theme* nil)

(defun terminal-theme-color-keys (theme)
  (declare (ignore theme))
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

(defun canonical-theme-name (name)
  (let ((canonical
          (etypecase name
            (keyword name)
            (symbol
             (intern (string-upcase (symbol-name name))
                     :keyword))
            (string
             (intern (string-upcase name) :keyword)))))
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
               (enabled-p t))
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
     :enabled-p (not (null enabled-p)))))

(defun theme-color-value
    (key &key (theme (current-theme)))
  (let ((canonical-key
          (canonical-theme-color-key key)))
    (multiple-value-bind (value present-p)
        (gethash canonical-key
                 (terminal-theme-colors theme))
      (unless present-p
        (error "Unknown semantic theme color: ~S" key))
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
           (theme-color-value canonical-key
                              :theme theme)))
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
         text
         (format nil "~C[39m" #\Escape))
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
  (case
      (etypecase level
        (keyword level)
        (symbol
         (intern (string-upcase (symbol-name level))
                 :keyword))
        (string
         (intern (string-upcase level) :keyword)))
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
                        (enabled-p t))
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
             :enabled-p enabled-p))))

(defun reset-current-theme ()
  (setf *current-theme*
        (make-terminal-theme :dark)))

(defun current-theme ()
  (or *current-theme*
      (reset-current-theme)))
