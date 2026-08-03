(in-package #:cadr-agent)

(defparameter +session-skill-block-scanner+
  (cl-ppcre:create-scanner
   "^<skill name=\"([^\"]+)\" location=\"([^\"]+)\">\\n([\\s\\S]*?)\\n</skill>(?:\\n\\n([\\s\\S]+))?$"))

(defun parse-session-skill-block (text)
  (when (stringp text)
    (multiple-value-bind (match groups)
        (cl-ppcre:scan-to-strings
         +session-skill-block-scanner+
         text)
      (when match
        (values
         (aref groups 0)
         (aref groups 1)
         (aref groups 2)
         (and (> (length groups) 3)
              (aref groups 3))
         t)))))

(defvar *export-html-asset-reader*
  (lambda (relative-path)
    (uiop:read-file-string
     (asdf:system-relative-pathname
      "cadr-agent"
      (format nil
              "src/cadr-agent/export-html/~A"
              relative-path))
     :external-format :utf-8)))

(defparameter +export-html-template+
  (funcall *export-html-asset-reader* "template.html"))
(defparameter +export-html-template-css+
  (funcall *export-html-asset-reader* "template.css"))
(defparameter +export-html-template-js+
  (funcall *export-html-asset-reader* "template.js"))
(defparameter +export-html-marked-js+
  (funcall *export-html-asset-reader* "vendor/marked.min.js"))
(defparameter +export-html-highlight-js+
  (funcall *export-html-asset-reader* "vendor/highlight.min.js"))

(defparameter +export-html-base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defparameter +export-html-dark-colors+
  '(("accent" . "#8abeb7")
    ("border" . "#5f87ff")
    ("borderAccent" . "#00d7ff")
    ("borderMuted" . "#505050")
    ("success" . "#b5bd68")
    ("error" . "#cc6666")
    ("warning" . "#ffff00")
    ("muted" . "#808080")
    ("dim" . "#666666")
    ("text" . "#d4d4d4")
    ("thinkingText" . "#808080")
    ("selectedBg" . "#3a3a4a")
    ("userMessageBg" . "#343541")
    ("userMessageText" . "#d4d4d4")
    ("customMessageBg" . "#2d2838")
    ("customMessageText" . "#d4d4d4")
    ("customMessageLabel" . "#9575cd")
    ("toolPendingBg" . "#282832")
    ("toolSuccessBg" . "#283228")
    ("toolErrorBg" . "#3c2828")
    ("toolTitle" . "#d4d4d4")
    ("toolOutput" . "#808080")
    ("mdHeading" . "#f0c674")
    ("mdLink" . "#81a2be")
    ("mdLinkUrl" . "#666666")
    ("mdCode" . "#8abeb7")
    ("mdCodeBlock" . "#b5bd68")
    ("mdCodeBlockBorder" . "#808080")
    ("mdQuote" . "#808080")
    ("mdQuoteBorder" . "#808080")
    ("mdHr" . "#808080")
    ("mdListBullet" . "#8abeb7")
    ("toolDiffAdded" . "#b5bd68")
    ("toolDiffRemoved" . "#cc6666")
    ("toolDiffContext" . "#808080")
    ("syntaxComment" . "#6A9955")
    ("syntaxKeyword" . "#569CD6")
    ("syntaxFunction" . "#DCDCAA")
    ("syntaxVariable" . "#9CDCFE")
    ("syntaxString" . "#CE9178")
    ("syntaxNumber" . "#B5CEA8")
    ("syntaxType" . "#4EC9B0")
    ("syntaxOperator" . "#D4D4D4")
    ("syntaxPunctuation" . "#D4D4D4")
    ("thinkingOff" . "#505050")
    ("thinkingMinimal" . "#6e6e6e")
    ("thinkingLow" . "#5f87af")
    ("thinkingMedium" . "#81a2be")
    ("thinkingHigh" . "#b294bb")
    ("thinkingXhigh" . "#d183e8")
    ("thinkingMax" . "#ff5fff")
    ("bashMode" . "#b5bd68")))

(defparameter +export-html-light-colors+
  '(("accent" . "#5a8080")
    ("border" . "#547da7")
    ("borderAccent" . "#5a8080")
    ("borderMuted" . "#b0b0b0")
    ("success" . "#588458")
    ("error" . "#aa5555")
    ("warning" . "#9a7326")
    ("muted" . "#6c6c6c")
    ("dim" . "#767676")
    ("text" . "#1f2328")
    ("thinkingText" . "#6c6c6c")
    ("selectedBg" . "#d0d0e0")
    ("userMessageBg" . "#e8e8e8")
    ("userMessageText" . "#1f2328")
    ("customMessageBg" . "#ede7f6")
    ("customMessageText" . "#1f2328")
    ("customMessageLabel" . "#7e57c2")
    ("toolPendingBg" . "#e8e8f0")
    ("toolSuccessBg" . "#e8f0e8")
    ("toolErrorBg" . "#f0e8e8")
    ("toolTitle" . "#1f2328")
    ("toolOutput" . "#6c6c6c")
    ("mdHeading" . "#9a7326")
    ("mdLink" . "#547da7")
    ("mdLinkUrl" . "#767676")
    ("mdCode" . "#5a8080")
    ("mdCodeBlock" . "#588458")
    ("mdCodeBlockBorder" . "#6c6c6c")
    ("mdQuote" . "#6c6c6c")
    ("mdQuoteBorder" . "#6c6c6c")
    ("mdHr" . "#6c6c6c")
    ("mdListBullet" . "#588458")
    ("toolDiffAdded" . "#588458")
    ("toolDiffRemoved" . "#aa5555")
    ("toolDiffContext" . "#6c6c6c")
    ("syntaxComment" . "#008000")
    ("syntaxKeyword" . "#0000FF")
    ("syntaxFunction" . "#795E26")
    ("syntaxVariable" . "#001080")
    ("syntaxString" . "#A31515")
    ("syntaxNumber" . "#098658")
    ("syntaxType" . "#267F99")
    ("syntaxOperator" . "#000000")
    ("syntaxPunctuation" . "#000000")
    ("thinkingOff" . "#b0b0b0")
    ("thinkingMinimal" . "#767676")
    ("thinkingLow" . "#547da7")
    ("thinkingMedium" . "#5a8080")
    ("thinkingHigh" . "#875f87")
    ("thinkingXhigh" . "#8b008b")
    ("thinkingMax" . "#af005f")
    ("bashMode" . "#588458")))

(defun encode-export-html-base64 (octets)
  (with-output-to-string (output)
    (loop for position from 0 below (length octets) by 3
          for remaining = (- (length octets) position)
          for first = (aref octets position)
          for second = (if (> remaining 1)
                           (aref octets (1+ position)) 0)
          for third = (if (> remaining 2)
                          (aref octets (+ position 2)) 0)
          for bits = (logior (ash first 16)
                             (ash second 8)
                             third)
          do
          (write-char
           (char +export-html-base64-alphabet+
                 (ldb (byte 6 18) bits))
           output)
          (write-char
           (char +export-html-base64-alphabet+
                 (ldb (byte 6 12) bits))
           output)
          (write-char
           (if (> remaining 1)
               (char +export-html-base64-alphabet+
                     (ldb (byte 6 6) bits))
               #\=)
           output)
          (write-char
           (if (> remaining 2)
               (char +export-html-base64-alphabet+
                     (ldb (byte 6 0) bits))
               #\=)
           output))))

(defun export-html-ansi-color (index)
  (when (<= 0 index 255)
    (cond
      ((< index 16)
       (aref
        #("#000000" "#800000" "#008000" "#808000"
          "#000080" "#800080" "#008080" "#c0c0c0"
          "#808080" "#ff0000" "#00ff00" "#ffff00"
          "#0000ff" "#ff00ff" "#00ffff" "#ffffff")
        index))
      ((< index 232)
       (let* ((cube-index (- index 16))
              (red (floor cube-index 36))
              (green (floor (mod cube-index 36) 6))
              (blue (mod cube-index 6)))
         (flet ((channel (value)
                  (if (zerop value)
                      0
                      (+ 55 (* value 40)))))
           (string-downcase
            (format nil "#~2,'0X~2,'0X~2,'0X"
                    (channel red)
                    (channel green)
                    (channel blue))))))
      (t
       (let ((gray (+ 8 (* (- index 232) 10))))
         (string-downcase
          (format nil "#~2,'0X~2,'0X~2,'0X"
                  gray gray gray)))))))

(defun resolve-export-html-theme-value
    (value variables default-value &optional seen)
  (cond
    ((integerp value)
     (or (export-html-ansi-color value)
         default-value))
    ((not (stringp value)) default-value)
    ((zerop (length value)) default-value)
    ((char= (char value 0) #\#) value)
    ((member value seen :test #'string=)
     default-value)
    (t
     (multiple-value-bind (referenced present-p)
         (if (hash-table-p variables)
             (gethash value variables)
             (values nil nil))
       (if present-p
           (resolve-export-html-theme-value
            referenced variables default-value
            (cons value seen))
           default-value)))))

(defun resolved-export-html-colors
    (theme-name theme-object)
  (let* ((light-p (string= (or theme-name "dark") "light"))
         (base
           (copy-tree
            (if light-p
                +export-html-light-colors+
                +export-html-dark-colors+)))
         (variables
           (and theme-object
                (cadr-ai::json-get
                 theme-object "vars")))
         (colors
           (and theme-object
                (cadr-ai::json-get
                 theme-object "colors")))
         (default-text
           (if light-p "#000000" "#e5e5e7")))
    (when (hash-table-p colors)
      (dolist (entry base)
        (multiple-value-bind (value present-p)
            (gethash (car entry) colors)
          (when present-p
            (setf
             (cdr entry)
             (resolve-export-html-theme-value
              value variables default-text))))))
    base))

(defun parse-export-html-color (value)
  (when (stringp value)
    (or
     (multiple-value-bind (match groups)
         (cl-ppcre:scan-to-strings
          "^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$"
          value)
       (and match
            (list
             (parse-integer (aref groups 0) :radix 16)
             (parse-integer (aref groups 1) :radix 16)
             (parse-integer (aref groups 2) :radix 16))))
     (multiple-value-bind (match groups)
         (cl-ppcre:scan-to-strings
          "^rgb[[:space:]]*\\([[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*\\)$"
          value)
       (and match
            (list
             (parse-integer (aref groups 0))
             (parse-integer (aref groups 1))
             (parse-integer (aref groups 2))))))))

(defun export-html-channel-luminance (channel)
  (let ((scaled (/ channel 255d0)))
    (if (<= scaled 0.03928d0)
        (/ scaled 12.92d0)
        (expt (/ (+ scaled 0.055d0) 1.055d0)
              2.4d0))))

(defun export-html-adjust-color (rgb factor)
  (format nil "rgb(~D, ~D, ~D)"
          (min 255 (max 0 (floor (+ 0.5d0 (* (first rgb) factor)))))
          (min 255 (max 0 (floor (+ 0.5d0 (* (second rgb) factor)))))
          (min 255 (max 0 (floor (+ 0.5d0 (* (third rgb) factor)))))))

(defun derive-export-html-colors (base-color)
  (let ((rgb (parse-export-html-color base-color)))
    (if (null rgb)
        (list :page "rgb(24, 24, 30)"
              :card "rgb(30, 30, 36)"
              :info "rgb(60, 55, 40)")
        (let* ((red (first rgb))
               (green (second rgb))
               (blue (third rgb))
               (luminance
                 (+ (* 0.2126d0
                       (export-html-channel-luminance red))
                    (* 0.7152d0
                       (export-html-channel-luminance green))
                    (* 0.0722d0
                       (export-html-channel-luminance blue)))))
          (if (> luminance 0.5d0)
              (list
               :page (export-html-adjust-color rgb 0.96d0)
               :card base-color
               :info
               (format nil "rgb(~D, ~D, ~D)"
                       (min 255 (+ red 10))
                       (min 255 (+ green 5))
                       (max 0 (- blue 20))))
              (list
               :page (export-html-adjust-color rgb 0.7d0)
               :card (export-html-adjust-color rgb 0.85d0)
               :info
               (format nil "rgb(~D, ~D, ~D)"
                       (min 255 (+ red 20))
                       (min 255 (+ green 15))
                       blue)))))))

(defun export-html-explicit-colors (theme-object variables)
  (let ((export
          (and theme-object
               (cadr-ai::json-get
                theme-object "export"))))
    (labels ((value (key)
               (when (hash-table-p export)
                 (multiple-value-bind (raw present-p)
                     (gethash key export)
                   (and present-p
                        (resolve-export-html-theme-value
                         raw variables nil))))))
      (list :page (value "pageBg")
            :card (value "cardBg")
            :info (value "infoBg")))))

(defun built-in-export-html-colors (theme-name theme-object)
  (when (null theme-object)
    (cond
      ((string= (or theme-name "dark") "light")
       (list :page "#f8f8f8"
             :card "#ffffff"
             :info "#fffae6"))
      ((string= (or theme-name "dark") "dark")
       (list :page "#18181e"
             :card "#1e1e24"
             :info "#3c3728")))))

(defun export-html-theme-data (theme-name theme-object)
  (let* ((colors
           (resolved-export-html-colors
            theme-name theme-object))
         (derived
           (derive-export-html-colors
            (or (cdr (assoc "userMessageBg" colors
                            :test #'string=))
                "#343541")))
         (explicit
           (or
            (built-in-export-html-colors
             theme-name theme-object)
            (export-html-explicit-colors
             theme-object
             (and theme-object
                  (cadr-ai::json-get
                   theme-object "vars")))))
         (page (or (getf explicit :page)
                   (getf derived :page)))
         (card (or (getf explicit :card)
                   (getf derived :card)))
         (info (or (getf explicit :info)
                   (getf derived :info))))
    (values
     (format nil
             "~{~A~^~%      ~}~%      --exportPageBg: ~A;~%      --exportCardBg: ~A;~%      --exportInfoBg: ~A;"
             (mapcar
              (lambda (entry)
                (format nil "--~A: ~A;"
                        (car entry) (cdr entry)))
              colors)
             page card info)
     page card info)))

(defun export-html-session-data (session)
  (cadr-ai::json-object
   "header" (session-header-to-json session)
   "entries"
   (map 'vector
        #'session-entry-to-json
        (session-%entries session))
   "leafId" (or (session-leaf-id session) 'null)))

(defun export-session-html
    (session path
     &key (theme-name "dark") theme-object)
  (multiple-value-bind
        (theme-vars page-background
         card-background info-background)
      (export-html-theme-data
       theme-name theme-object)
    (let* ((session-data
             (cadr-ai::stringify-json
              (export-html-session-data session)))
           (encoded-data
             (encode-export-html-base64
              (cadr-ai::utf8-octets
               session-data)))
           (css
             (cadr-ai::replace-all
              (cadr-ai::replace-all
               (cadr-ai::replace-all
                (cadr-ai::replace-all
                 +export-html-template-css+
                 "{{THEME_VARS}}" theme-vars)
                "{{BODY_BG}}" page-background)
               "{{CONTAINER_BG}}" card-background)
              "{{INFO_BG}}" info-background))
           (html
             (cadr-ai::replace-all
              (cadr-ai::replace-all
               (cadr-ai::replace-all
                (cadr-ai::replace-all
                 (cadr-ai::replace-all
                  +export-html-template+
                  "{{CSS}}" css)
                 "{{JS}}" +export-html-template-js+)
                "{{SESSION_DATA}}" encoded-data)
               "{{MARKED_JS}}" +export-html-marked-js+)
              "{{HIGHLIGHT_JS}}" +export-html-highlight-js+)))
      (ensure-directories-exist path)
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (write-string html stream))
      (pathname path))))
