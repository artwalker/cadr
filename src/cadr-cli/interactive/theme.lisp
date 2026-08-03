(in-package #:cadr-cli)

(defstruct theme-detection
  theme
  source
  confidence)

(defun colorfgbg-background-index (value)
  (loop
    for part in
    (reverse
     (uiop:split-string
      value :separator '(#\;)))
    for trimmed =
    (string-trim
     '(#\Space #\Tab #\Newline #\Return)
     part)
    for index =
    (ignore-errors
      (parse-integer trimmed :junk-allowed t))
    when (and index (<= 0 index 255))
      return index))

(defun detect-background-from-environment
    (&optional environment)
  (let ((value
          (or
           (cdr (assoc "COLORFGBG"
                       environment
                       :test #'string=))
           (and (null environment)
                (uiop:getenv "COLORFGBG")))))
    (if value
        (let ((index
                (colorfgbg-background-index
                 value)))
          (if index
              (make-theme-detection
               :theme
               (apply #'rgb-background-theme
                      (xterm-color-to-rgb index))
               :source "COLORFGBG"
               :confidence :high)
              (make-theme-detection
               :theme :dark
               :source "fallback"
               :confidence :low)))
        (make-theme-detection
         :theme :dark
         :source "fallback"
         :confidence :low))))

(defun rgb-background-theme (red green blue)
  (dolist (channel (list red green blue))
    (check-type channel (integer 0 255)))
  (let* ((linear
           (lambda (value)
             (let ((channel (/ value 255d0)))
               (if (<= channel 0.03928d0)
                   (/ channel 12.92d0)
                   (expt
                    (/ (+ channel 0.055d0)
                       1.055d0)
                    2.4d0)))))
         (luminance
           (+
            (* 0.2126d0
               (funcall linear red))
            (* 0.7152d0
               (funcall linear green))
            (* 0.0722d0
               (funcall linear blue)))))
    (if (>= luminance 0.5d0)
        :light :dark)))

(defun parse-auto-theme-setting (setting)
  (when (stringp setting)
    (let ((slash (position #\/ setting)))
      (when
          (and slash
               (null
                (position #\/ setting
                          :start (1+ slash))))
        (let ((light
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (subseq setting 0 slash)))
              (dark
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (subseq setting (1+ slash)))))
          (when
              (and (plusp (length light))
                   (plusp (length dark)))
            (list :light-theme light
                  :dark-theme dark)))))))

(defun resolve-theme-setting
    (setting background)
  (let ((auto
          (parse-auto-theme-setting setting)))
    (cond
      (auto
       (ecase background
         (:light (getf auto :light-theme))
         (:dark (getf auto :dark-theme))))
      ((and (stringp setting)
            (find #\/ setting))
       nil)
      ((stringp setting) setting)
      (t nil))))

(defun xterm-color-to-rgb (index)
  (unless (typep index '(integer 0 255))
    (return-from xterm-color-to-rgb nil))
  (cond
    ((< index 16)
     (nth
      index
      '((0 0 0) (128 0 0) (0 128 0)
        (128 128 0) (0 0 128) (128 0 128)
        (0 128 128) (192 192 192)
        (128 128 128) (255 0 0) (0 255 0)
        (255 255 0) (0 0 255) (255 0 255)
        (0 255 255) (255 255 255))))
    ((< index 232)
     (let* ((value (- index 16))
            (red (floor value 36))
            (green (floor (mod value 36) 6))
            (blue (mod value 6))
            (levels #(0 95 135 175 215 255)))
       (list (aref levels red)
             (aref levels green)
             (aref levels blue))))
    ((< index 256)
     (let ((gray (+ 8 (* 10 (- index 232)))))
       (list gray gray gray)))
    (t nil)))

(defun rgb-hex (rgb)
  (and rgb
       (format nil "#~2,'0X~2,'0X~2,'0X"
               (first rgb)
               (second rgb)
               (third rgb))))

(defun resolve-theme-value
    (value variables &optional seen)
  (cond
    ((integerp value)
     (rgb-hex
      (xterm-color-to-rgb value)))
    ((not (stringp value)) nil)
    ((zerop (length value)) nil)
    ((char= (char value 0) #\#)
     (string-downcase value))
    ((member value seen :test #'string=)
     nil)
    (t
     (resolve-theme-value
      (cadr-ai::json-get variables value)
      variables
      (cons value seen)))))

(defun theme-export-colors (theme)
  (let ((variables
          (or
           (cadr-ai::json-get theme "vars")
           (empty-json-object)))
        (export
          (or
           (cadr-ai::json-get theme "export")
           (empty-json-object))))
    (list
     :page-bg
     (resolve-theme-value
      (cadr-ai::json-get export "pageBg")
      variables)
     :card-bg
     (resolve-theme-value
      (cadr-ai::json-get export "cardBg")
      variables)
     :info-bg
     (resolve-theme-value
      (cadr-ai::json-get export "infoBg")
      variables))))

(defun load-theme-summaries (directory)
  (sort
   (loop
     for path in
     (uiop:directory-files
      (uiop:ensure-directory-pathname directory)
      "*.json")
     for object =
     (handler-case
         (cadr-ai::parse-json
          (uiop:read-file-string
           path :external-format :utf-8))
       (condition () nil))
     when (hash-table-p object)
       collect
       (list
        :name
        (or
         (cadr-ai::json-get object "name")
         (pathname-name path))
        :path path
        :object object))
   #'string<
   :key (lambda (entry)
          (getf entry :name))))

