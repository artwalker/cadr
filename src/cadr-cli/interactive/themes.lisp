(in-package #:cadr-cli)

(defparameter +tui-theme-json-color-map+
  '(("accent" . :accent)
    ("border" . :border)
    ("borderAccent" . :border-accent)
    ("borderMuted" . :border-muted)
    ("success" . :success)
    ("error" . :error)
    ("warning" . :warning)
    ("muted" . :muted)
    ("dim" . :dim)
    ("text" . :text)
    ("thinkingText" . :thinking-text)
    ("selectedBg" . :selected-bg)
    ("scrollbarThumb" . :scrollbar-thumb)
    ("searchMatchBg" . :search-match-bg)
    ("searchMatchText" . :search-match-text)
    ("userMessageBg" . :user-message-bg)
    ("userMessageText" . :user-message-text)
    ("customMessageBg" . :custom-message-bg)
    ("customMessageText" . :custom-message-text)
    ("customMessageLabel" . :custom-message-label)
    ("toolPendingBg" . :tool-pending-bg)
    ("toolSuccessBg" . :tool-success-bg)
    ("toolErrorBg" . :tool-error-bg)
    ("toolTitle" . :tool-title)
    ("toolOutput" . :tool-output)
    ("mdHeading" . :md-heading)
    ("mdLink" . :md-link)
    ("mdLinkUrl" . :md-link-url)
    ("mdCode" . :md-code)
    ("mdCodeBlock" . :md-code-block)
    ("mdCodeBlockBorder"
     . :md-code-block-border)
    ("mdQuote" . :md-quote)
    ("mdQuoteBorder" . :md-quote-border)
    ("mdHr" . :md-hr)
    ("mdListBullet" . :md-list-bullet)
    ("toolDiffAdded" . :tool-diff-added)
    ("toolDiffRemoved" . :tool-diff-removed)
    ("toolDiffContext" . :tool-diff-context)
    ("syntaxComment" . :syntax-comment)
    ("syntaxKeyword" . :syntax-keyword)
    ("syntaxFunction" . :syntax-function)
    ("syntaxVariable" . :syntax-variable)
    ("syntaxString" . :syntax-string)
    ("syntaxNumber" . :syntax-number)
    ("syntaxType" . :syntax-type)
    ("syntaxOperator" . :syntax-operator)
    ("syntaxPunctuation" . :syntax-punctuation)
    ("thinkingOff" . :thinking-off)
    ("thinkingMinimal" . :thinking-minimal)
    ("thinkingLow" . :thinking-low)
    ("thinkingMedium" . :thinking-medium)
    ("thinkingHigh" . :thinking-high)
    ("thinkingXhigh" . :thinking-xhigh)
    ("thinkingMax" . :thinking-max)
    ("bashMode" . :bash-mode)))

(defparameter +tui-theme-json-export-map+
  '(("pageBg" . :page-bg)
    ("cardBg" . :card-bg)
    ("infoBg" . :info-bg)))

(defun valid-tui-theme-primitive-p (value)
  (or
   (stringp value)
   (and
    (integerp value)
    (<= 0 value 255))))

(defun validate-tui-theme-object
    (object variables variables-present-p
     colors export export-present-p)
  (maphash
   (lambda (name value)
     (declare (ignore value))
     (unless
         (member name
                 '("$schema" "name" "vars"
                   "colors" "export")
                 :test #'string=)
       (error "Unknown theme property: ~A"
              name)))
   object)
  (multiple-value-bind (schema present-p)
      (gethash "$schema" object)
    (when
        (and present-p
             (not (stringp schema)))
      (error "Theme $schema must be a string")))
  (let ((name
          (cadr-ai::json-get object "name")))
    (unless (and
             (stringp name)
             (plusp (length name))
             (not (search "/" name)))
      (error "Theme requires a valid name without '/'")))
  (unless (hash-table-p colors)
    (error "Theme requires a colors object"))
  (unless
      (or
       (not variables-present-p)
       (hash-table-p variables))
    (error "Theme vars must be an object"))
  (maphash
   (lambda (name value)
     (declare (ignore name))
     (unless (valid-tui-theme-primitive-p value)
       (error "Invalid theme variable value: ~S"
              value)))
   variables)
  (let ((known
          (mapcar #'car
                  +tui-theme-json-color-map+)))
    (maphash
     (lambda (name value)
       (unless
           (member name known :test #'string=)
         (error "Unknown theme color token: ~A"
                name))
       (unless (valid-tui-theme-primitive-p value)
         (error "Invalid theme color value: ~S"
                value)))
     colors)
    (dolist (name known)
      (unless
          (or
           (string= name "thinkingMax")
           (string= name "scrollbarThumb")
           (string= name "searchMatchBg")
           (string= name "searchMatchText")
           (nth-value 1
                      (gethash name colors)))
        (error "Missing required theme color token: ~A"
               name))))
  (when export-present-p
    (unless (hash-table-p export)
      (error "Theme export must be an object"))
    (let ((known
            (mapcar #'car
                    +tui-theme-json-export-map+)))
      (maphash
       (lambda (name value)
         (unless
             (member name known :test #'string=)
           (error "Unknown theme export token: ~A"
                  name))
         (unless (valid-tui-theme-primitive-p value)
           (error "Invalid theme export value: ~S"
                  value)))
       export)))
  t)

(defun resolve-tui-theme-value
    (value variables &optional seen)
  (cond
    ((integerp value)
     (unless (<= 0 value 255)
       (error "Theme color index is outside 0..255: ~S"
              value))
     value)
    ((not (stringp value))
     (error "Theme color must be a string or integer: ~S"
            value))
    ((zerop (length value))
     "")
    ((char= (char value 0) #\#)
     (cadr-tui:parse-theme-hex-color value)
     (string-downcase value))
    ((member value seen :test #'string=)
     (error "Cyclic theme variable reference: ~A"
            value))
    (t
     (multiple-value-bind (resolved present-p)
         (gethash value variables)
       (unless present-p
         (error "Unknown theme variable: ~A"
                value))
       (resolve-tui-theme-value
        resolved variables (cons value seen))))))

(defun theme-object-overrides (object)
  (when (hash-table-p object)
    (multiple-value-bind (raw-variables variables-present-p)
        (gethash "vars" object)
      (multiple-value-bind (export export-present-p)
          (gethash "export" object)
        (let ((variables
                (if variables-present-p
                    raw-variables
                    (make-hash-table :test #'equal)))
              (colors
                (cadr-ai::json-get object "colors"))
              (overrides nil))
          (validate-tui-theme-object
           object variables variables-present-p
           colors export export-present-p)
      (labels
          ((collect-values (container mapping)
             (when (hash-table-p container)
               (dolist (entry mapping)
                 (multiple-value-bind (raw present-p)
                     (gethash (car entry) container)
                   (when present-p
                     (push
                      (cons
                       (cdr entry)
                       (resolve-tui-theme-value
                        raw variables))
                      overrides)))))))
        (collect-values
         colors
         +tui-theme-json-color-map+)
        (unless
            (nth-value 1
                       (gethash "thinkingMax"
                                colors))
          (push
           (cons
            :thinking-max
            (resolve-tui-theme-value
             (gethash "thinkingXhigh" colors)
             variables))
           overrides))
       ;; pi@53fa77ccd theme.ts:326-332 — optional scrollbarThumb
       ;; falls back to selectedBg.
       (unless
           (nth-value 1
                      (gethash "scrollbarThumb"
                               colors))
         (push
          (cons
           :scrollbar-thumb
           (resolve-tui-theme-value
            (gethash "selectedBg" colors)
            variables))
          overrides))
       ;; v0.84.2: the search-match colors fall back to selectedBg/text.
       (unless
           (nth-value 1
                      (gethash "searchMatchBg"
                               colors))
         (push
          (cons
           :search-match-bg
           (resolve-tui-theme-value
            (gethash "selectedBg" colors)
            variables))
          overrides))
       (unless
           (nth-value 1
                      (gethash "searchMatchText"
                               colors))
         (push
          (cons
           :search-match-text
           (resolve-tui-theme-value
            (gethash "text" colors)
            variables))
          overrides))
        (collect-values
         export
         +tui-theme-json-export-map+))
            (nreverse overrides))))))

(defun apply-tui-theme-summary
    (summary
     &key background
       (keep-current-on-error-p nil)
       (capabilities
         (cadr-tui:get-terminal-capabilities)))
  (let* ((name
           (cond
             ((stringp summary) summary)
             ((listp summary)
              (getf summary :name))
             (t nil)))
         (object
           (and (listp summary)
                (getf summary :object)))
         (background
           (or
            background
            (theme-detection-theme
             (detect-background-from-environment))))
         (base
           (cond
             ((and name
                   (string-equal name "light"))
              :light)
             ((and name
                   (string-equal name "dark"))
              :dark)
             ((eq background :light)
              :light)
             (t :dark))))
    (handler-case
        (cadr-tui:set-current-theme
         base
         :overrides
         (theme-object-overrides object)
         :capabilities capabilities)
      (condition ()
        (unless keep-current-on-error-p
          (cadr-tui:set-current-theme
           :dark
           :capabilities capabilities))
        nil))))

(defstruct (tui-theme-watcher
            (:constructor %make-tui-theme-watcher))
  path
  signature
  pending-signature
  pending-since
  summary
  background)

(defconstant +tui-theme-watch-poll-seconds+
  0.005d0)

(defun load-tui-theme-file (path)
  (handler-case
      (let ((object
              (cadr-ai::parse-json
               (uiop:read-file-string
                path :external-format :utf-8))))
        (when (hash-table-p object)
          (list
           :name
           (or
            (cadr-ai::json-get object "name")
            (pathname-name path))
           :path path
           :object object)))
    (condition () nil)))

(defun make-tui-theme-watcher
    (summary &key background)
  (let ((path
          (and (listp summary)
               (getf summary :path))))
    (when path
      (%make-tui-theme-watcher
       :path path
       :signature
       (binary-file-signature path)
       :summary summary
       :background background))))

(defun poll-tui-theme-watcher
    (watcher
     &key
       (clock-function #'tui-monotonic-seconds)
       (capabilities
         (cadr-tui:get-terminal-capabilities)))
  (let* ((path
           (tui-theme-watcher-path watcher))
         (signature
           (binary-file-signature path)))
    (when
        (equal
         signature
         (tui-theme-watcher-signature watcher))
      (setf
       (tui-theme-watcher-pending-signature watcher)
       nil
       (tui-theme-watcher-pending-since watcher)
       nil)
      (return-from poll-tui-theme-watcher nil))
    (let ((now
            (funcall clock-function)))
      (unless
          (equal
           signature
           (tui-theme-watcher-pending-signature
            watcher))
        (setf
         (tui-theme-watcher-pending-signature watcher)
         signature
         (tui-theme-watcher-pending-since watcher)
         now)
        (return-from poll-tui-theme-watcher nil))
      (when
          (<
           (- now
              (tui-theme-watcher-pending-since
               watcher))
           0.1d0)
        (return-from poll-tui-theme-watcher nil)))
    (setf
     (tui-theme-watcher-signature watcher)
     signature
     (tui-theme-watcher-pending-signature watcher)
     nil
     (tui-theme-watcher-pending-since watcher)
     nil)
    (let ((summary
            (and signature
                 (load-tui-theme-file path))))
      (when
          (and
           summary
           (apply-tui-theme-summary
            summary
            :background
            (tui-theme-watcher-background watcher)
            :keep-current-on-error-p t
            :capabilities capabilities))
        (setf
         (tui-theme-watcher-summary watcher)
         summary)
        t))))
