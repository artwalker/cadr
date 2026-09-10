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

(defun split-export-html-template (template placeholders)
  (let ((parts nil)
        (start 0))
    (dolist (placeholder placeholders)
      (let ((pos (search placeholder template :start2 start)))
        (unless pos
          (error "export-html template missing ~A" placeholder))
        (push (subseq template start pos) parts)
        (setf start (+ pos (length placeholder)))))
    (push (subseq template start) parts)
    (nreverse parts)))

(defparameter +export-html-css-parts+
  (split-export-html-template
   +export-html-template-css+
   '("{{THEME_VARS}}"
     "{{BODY_BG}}"
     "{{CONTAINER_BG}}"
     "{{INFO_BG}}")))

(defparameter +export-html-html-parts+
  (split-export-html-template
   +export-html-template+
   '("{{CSS}}"
     "{{SESSION_DATA}}"
     "{{MARKED_JS}}"
     "{{HIGHLIGHT_JS}}"
     "{{JS}}")))

(defun export-html-utf8-octets (text)
  (sb-ext:string-to-octets text :external-format :utf-8))

(defparameter +export-html-css-part-octets+
  (mapcar #'export-html-utf8-octets +export-html-css-parts+))
(defparameter +export-html-html-part-octets+
  (mapcar #'export-html-utf8-octets +export-html-html-parts+))
(defparameter +export-html-marked-js-octets+
  (export-html-utf8-octets +export-html-marked-js+))
(defparameter +export-html-highlight-js-octets+
  (export-html-utf8-octets +export-html-highlight-js+))
(defparameter +export-html-template-js-octets+
  (export-html-utf8-octets +export-html-template-js+))

(defparameter +export-html-base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
(defparameter +export-html-base64-alphabet-codes+
  (let ((codes (make-array 64 :element-type '(unsigned-byte 8))))
    (dotimes (index 64)
      (setf (aref codes index)
            (char-code
             (char +export-html-base64-alphabet+ index))))
    codes))

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

(defun encode-export-html-base64-octets (octets)
  (let* ((bytes
           (if (typep octets '(simple-array (unsigned-byte 8) (*)))
               octets
               (let ((copy
                       (make-array
                        (length octets)
                        :element-type '(unsigned-byte 8))))
                 (replace copy octets)
                 copy)))
         (length (length bytes))
         (encoded
           (make-array
            (* 4 (ceiling length 3))
            :element-type '(unsigned-byte 8)))
         (codes +export-html-base64-alphabet-codes+)
         (out 0))
    (declare (optimize (speed 3) (safety 1))
             (type (simple-array (unsigned-byte 8) (*)) bytes encoded)
             (type (simple-array (unsigned-byte 8) (*)) codes)
             (type fixnum length out))
    (loop for position of-type fixnum from 0 below length by 3
          for remaining of-type fixnum = (- length position)
          for first of-type fixnum = (aref bytes position)
          for second of-type fixnum = (if (> remaining 1)
                                          (aref bytes (1+ position))
                                          0)
          for third of-type fixnum = (if (> remaining 2)
                                         (aref bytes (+ position 2))
                                         0)
          for bits of-type fixnum = (logior (ash first 16)
                                            (ash second 8)
                                            third)
          do
          (setf (aref encoded out)
                (aref codes (ldb (byte 6 18) bits)))
          (setf (aref encoded (the fixnum (1+ out)))
                (aref codes (ldb (byte 6 12) bits)))
          (setf (aref encoded (the fixnum (+ out 2)))
                (if (> remaining 1)
                    (aref codes (ldb (byte 6 6) bits))
                    61))
          (setf (aref encoded (the fixnum (+ out 3)))
                (if (> remaining 2)
                    (aref codes (ldb (byte 6 0) bits))
                    61))
          (incf out 4))
    encoded))

(defun encode-export-html-base64 (octets)
  (cadr-ai::utf8-string
   (encode-export-html-base64-octets octets)))

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

(defun write-export-json-content-block (stream block)
  (cond
    ((typep block 'cadr-ai:text-content)
     (write-string "{\"type\":\"text\",\"text\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:text-content-text block) stream)
     (when (cadr-ai:text-content-signature block)
       (write-string ",\"signature\":" stream)
       (cadr-ai::write-json-string
        (cadr-ai:text-content-signature block) stream))
     (write-char #\} stream))
    ((typep block 'cadr-ai:thinking-content)
     (write-string "{\"type\":\"thinking\",\"thinking\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:thinking-content-thinking block) stream)
     (write-string ",\"redacted\":" stream)
     (cadr-ai::write-json-value
      (cadr-ai:thinking-content-redacted-p block) stream)
     (when (cadr-ai:thinking-content-signature block)
       (write-string ",\"signature\":" stream)
       (cadr-ai::write-json-string
        (cadr-ai:thinking-content-signature block) stream))
     (write-char #\} stream))
    ((typep block 'cadr-ai:image-content)
     (write-string "{\"type\":\"image\",\"mimeType\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:image-content-mime-type block) stream)
     (write-string ",\"data\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:image-content-data block) stream)
     (write-char #\} stream))
    ((typep block 'cadr-ai:tool-call)
     (write-string "{\"type\":\"toolCall\",\"id\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:tool-call-id block) stream)
     (write-string ",\"name\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:tool-call-name block) stream)
     (write-string ",\"arguments\":" stream)
     (cadr-ai::write-json-value
      (json-safe-value (cadr-ai:tool-call-arguments block))
      stream)
     (when (cadr-ai:tool-call-thought-signature block)
       (write-string ",\"thoughtSignature\":" stream)
       (cadr-ai::write-json-string
        (cadr-ai:tool-call-thought-signature block) stream))
     (write-char #\} stream))
    (t
     (cadr-ai::write-json-value
      (content-block-to-json block) stream))))

(defun write-export-json-content (stream content)
  (if (stringp content)
      (cadr-ai::write-json-string content stream)
      (progn
        (write-char #\[ stream)
        (loop for block across (coerce content 'vector)
              for first-p = t then nil
              do
              (unless first-p (write-char #\, stream))
              (write-export-json-content-block stream block))
        (write-char #\] stream))))

(defun write-export-json-usage (stream usage)
  (let ((cost (cadr-ai:usage-cost usage)))
    (write-string "{\"input\":" stream)
    (princ (cadr-ai:usage-input usage) stream)
    (write-string ",\"output\":" stream)
    (princ (cadr-ai:usage-output usage) stream)
    (write-string ",\"cacheRead\":" stream)
    (princ (cadr-ai:usage-cache-read usage) stream)
    (write-string ",\"cacheWrite\":" stream)
    (princ (cadr-ai:usage-cache-write usage) stream)
    (write-string ",\"total\":" stream)
    (princ (cadr-ai:usage-total usage) stream)
    (write-string ",\"cost\":{\"input\":" stream)
    (princ (cadr-ai:cost-input cost) stream)
    (write-string ",\"output\":" stream)
    (princ (cadr-ai:cost-output cost) stream)
    (write-string ",\"cacheRead\":" stream)
    (princ (cadr-ai:cost-cache-read cost) stream)
    (write-string ",\"cacheWrite\":" stream)
    (princ (cadr-ai:cost-cache-write cost) stream)
    (write-string ",\"total\":" stream)
    (princ (cadr-ai:cost-total cost) stream)
    (write-char #\} stream)
    (when (cadr-ai:usage-reasoning usage)
      (write-string ",\"reasoning\":" stream)
      (cadr-ai::write-json-value
       (cadr-ai:usage-reasoning usage) stream))
    (write-char #\} stream)))

(defun write-export-json-message (stream message)
  (cond
    ((typep message 'cadr-ai:user-message)
     (write-string "{\"role\":\"user\",\"content\":" stream)
     (write-export-json-content
      stream (cadr-ai:user-message-content message))
     (write-string ",\"timestamp\":" stream)
     (cadr-ai::write-json-value
      (cadr-ai:user-message-timestamp message) stream)
     (write-char #\} stream))
    ((typep message 'cadr-ai:assistant-message)
     (write-string "{\"role\":\"assistant\",\"content\":" stream)
     (write-export-json-content
      stream (cadr-ai:assistant-message-content message))
     (write-string ",\"api\":" stream)
     (cadr-ai::write-json-string
      (symbol-json-name (cadr-ai:assistant-message-api message))
      stream)
     (write-string ",\"provider\":" stream)
     (cadr-ai::write-json-string
      (symbol-json-name
       (cadr-ai:assistant-message-provider message))
      stream)
     (write-string ",\"model\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:assistant-message-model message) stream)
     (write-string ",\"usage\":" stream)
     (write-export-json-usage
      stream (cadr-ai:assistant-message-usage message))
     (write-string ",\"stopReason\":" stream)
     (cadr-ai::write-json-string
      (symbol-json-name
       (cadr-ai:assistant-message-stop-reason message))
      stream)
     (write-string ",\"timestamp\":" stream)
     (cadr-ai::write-json-value
      (cadr-ai:assistant-message-timestamp message) stream)
     (when (cadr-ai:assistant-message-response-id message)
       (write-string ",\"responseId\":" stream)
       (cadr-ai::write-json-string
        (cadr-ai:assistant-message-response-id message) stream))
     (when (cadr-ai:assistant-message-error-message message)
       (write-string ",\"errorMessage\":" stream)
       (cadr-ai::write-json-string
        (cadr-ai:assistant-message-error-message message) stream))
     (when (cadr-ai:assistant-message-raw-stop-reason message)
       (write-string ",\"rawStopReason\":" stream)
       (cadr-ai::write-json-string
        (cadr-ai:assistant-message-raw-stop-reason message)
        stream))
     (when (cadr-ai:assistant-message-diagnostics message)
       (write-string ",\"diagnostics\":" stream)
       (cadr-ai::write-json-value
        (map 'vector
             #'assistant-diagnostic-to-json
             (cadr-ai:assistant-message-diagnostics message))
        stream))
     (when (cadr-ai:assistant-message-provider-thinking-level
            message)
       (write-string ",\"providerThinkingLevel\":" stream)
       (cadr-ai::write-json-value
        (cadr-ai:assistant-message-provider-thinking-level
         message)
        stream))
     (write-char #\} stream))
    ((typep message 'cadr-ai:tool-result-message)
     (write-string "{\"role\":\"toolResult\",\"toolCallId\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:tool-result-message-tool-call-id message) stream)
     (write-string ",\"toolName\":" stream)
     (cadr-ai::write-json-string
      (cadr-ai:tool-result-message-tool-name message) stream)
     (write-string ",\"content\":" stream)
     (write-export-json-content
      stream (cadr-ai:tool-result-message-content message))
     (write-string ",\"details\":" stream)
     (cadr-ai::write-json-value
      (json-safe-value
       (cadr-ai:tool-result-message-details message))
      stream)
     (write-string ",\"isError\":" stream)
     (cadr-ai::write-json-value
      (cadr-ai:tool-result-message-is-error message) stream)
     (write-string ",\"timestamp\":" stream)
     (cadr-ai::write-json-value
      (cadr-ai:tool-result-message-timestamp message) stream)
     (write-char #\} stream))
    (t
     (cadr-ai::write-json-value
      (message-to-json message) stream))))

(defun write-export-json-entry (stream entry)
  (if (eq :message (session-entry-type entry))
      (progn
        (write-string "{\"type\":\"message\",\"id\":" stream)
        (cadr-ai::write-json-string (session-entry-id entry) stream)
        (write-string ",\"parentId\":" stream)
        (cadr-ai::write-json-value
         (or (session-entry-parent-id entry) 'null) stream)
        (write-string ",\"timestamp\":" stream)
        (cadr-ai::write-json-string
         (session-timestamp-json
          (session-entry-timestamp entry))
         stream)
        (write-string ",\"message\":" stream)
        (write-export-json-message
         stream (session-entry-message entry))
        (write-char #\} stream))
      (cadr-ai::write-json-value
       (session-entry-to-json entry) stream)))

(defun stringify-export-html-session (session)
  (let ((cadr-ai::*json-sort-object-keys* nil))
    (with-output-to-string (stream)
      (write-string "{\"header\":" stream)
      (cadr-ai::write-json-value
       (session-header-to-json session) stream)
      (write-string ",\"entries\":[" stream)
      (let ((first-p t))
        (map nil
             (lambda (entry)
               (unless first-p (write-char #\, stream))
               (setf first-p nil)
               (write-export-json-entry stream entry))
             (session-%entries session)))
      (write-string "],\"leafId\":" stream)
      (cadr-ai::write-json-value
       (or (session-leaf-id session) 'null) stream)
      (write-char #\} stream))))

(defun export-session-html
    (session path
     &key (theme-name "dark") theme-object)
  ;; Stream-splice pre-split template parts. Not nested
  ;; replace-all copies of the full HTML/CSS.
  (multiple-value-bind
        (theme-vars page-background
         card-background info-background)
      (export-html-theme-data
       theme-name theme-object)
    (let* ((session-data (stringify-export-html-session session))
           (encoded-data
             (encode-export-html-base64-octets
              (cadr-ai::utf8-octets
               session-data)))
           (css-parts +export-html-css-part-octets+)
           (html-parts +export-html-html-part-octets+))
      (ensure-directories-exist path)
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :element-type '(unsigned-byte 8))
        (write-sequence (first html-parts) stream)
        (write-sequence (first css-parts) stream)
        (write-sequence (export-html-utf8-octets theme-vars) stream)
        (write-sequence (second css-parts) stream)
        (write-sequence (export-html-utf8-octets page-background) stream)
        (write-sequence (third css-parts) stream)
        (write-sequence (export-html-utf8-octets card-background) stream)
        (write-sequence (fourth css-parts) stream)
        (write-sequence (export-html-utf8-octets info-background) stream)
        (write-sequence (fifth css-parts) stream)
        (write-sequence (second html-parts) stream)
        (write-sequence encoded-data stream)
        (write-sequence (third html-parts) stream)
        (write-sequence +export-html-marked-js-octets+ stream)
        (write-sequence (fourth html-parts) stream)
        (write-sequence +export-html-highlight-js-octets+ stream)
        (write-sequence (fifth html-parts) stream)
        (write-sequence +export-html-template-js-octets+ stream)
        (write-sequence (sixth html-parts) stream))
      (pathname path))))
