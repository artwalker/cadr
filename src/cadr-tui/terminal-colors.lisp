(in-package #:cadr-tui)

(defstruct rgb-color
  (red 0 :type (integer 0 255))
  (green 0 :type (integer 0 255))
  (blue 0 :type (integer 0 255)))

(defparameter *cell-width-pixels* 9)
(defparameter *cell-height-pixels* 18)

(defun set-cell-dimensions (width height)
  (when (and (integerp width) (plusp width)
             (integerp height) (plusp height))
    (setf *cell-width-pixels* width
          *cell-height-pixels* height))
  (values *cell-width-pixels* *cell-height-pixels*))

(defun get-cell-dimensions ()
  (values *cell-width-pixels* *cell-height-pixels*))

(defun strict-hex-string-p (text)
  (and (plusp (length text))
       (every (lambda (character)
                (digit-char-p character 16))
              text)))

(defun parse-osc-hex-channel (text)
  (when (strict-hex-string-p text)
    (let ((maximum (1- (expt 16 (length text)))))
      (when (plusp maximum)
        (round (* (/ (parse-integer text :radix 16)
                     maximum)
                  255))))))

(defun parse-osc-color-value (raw)
  (let ((value
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           raw)))
    (cond
      ((and (plusp (length value))
            (char= (char value 0) #\#))
       (let ((hex (subseq value 1)))
         (cond
           ((and (= (length hex) 6)
                 (strict-hex-string-p hex))
            (make-rgb-color
             :red (parse-integer hex :start 0 :end 2 :radix 16)
             :green (parse-integer hex :start 2 :end 4 :radix 16)
             :blue (parse-integer hex :start 4 :end 6 :radix 16)))
           ((and (= (length hex) 12)
                 (strict-hex-string-p hex))
            (let ((red (parse-osc-hex-channel (subseq hex 0 4)))
                  (green (parse-osc-hex-channel (subseq hex 4 8)))
                  (blue (parse-osc-hex-channel (subseq hex 8 12))))
              (when (and red green blue)
                (make-rgb-color :red red :green green :blue blue)))))))
      (t
       (let* ((colon (position #\: value))
              (prefix
                (and colon
                     (string-downcase (subseq value 0 colon))))
              (channels
                (uiop:split-string
                 (if (member prefix '("rgb" "rgba") :test #'string=)
                     (subseq value (1+ colon))
                     value)
                 :separator '(#\/))))
         (when (= (length channels) 3)
           (let ((red (parse-osc-hex-channel (first channels)))
                 (green (parse-osc-hex-channel (second channels)))
                 (blue (parse-osc-hex-channel (third channels))))
             (when (and red green blue)
               (make-rgb-color
                :red red :green green :blue blue)))))))))

(defun parse-osc-color-response (data)
  ;; pi@4a080252f parseOscColorResponse: OSC 10, 11, or 4.
  (multiple-value-bind (match registers)
      (cl-ppcre:scan-to-strings
       (format nil
               "^~C\\](?:(1[01])|4;(\\d{1,3}));([^~C~C]*)(?:~C|~C\\\\)$"
               #\Escape (code-char 7) #\Escape
               (code-char 7) #\Escape)
       data)
    (unless match
      (return-from parse-osc-color-response (values nil nil nil)))
    (let ((default (aref registers 0))
          (index (aref registers 1))
          (raw (aref registers 2)))
      (values
       (cond
         ((and default (string= default "10")) :foreground)
         ((and default (string= default "11")) :background)
         (t (parse-integer index)))
       (parse-osc-color-value raw)
       t))))

(defun osc-11-body (data)
  (let ((prefix (format nil "~C]11;" #\Escape)))
    (when (and (string-prefix-p prefix data)
               (> (length data) (length prefix)))
      (let ((end
              (cond
                ((= (codepoint
                     (char data
                           (1- (length data))))
                    7)
                 (1- (length data)))
                ((and (>= (length data) 2)
                      (char= (char data
                                   (- (length data) 2))
                             #\Escape)
                      (char= (char data
                                   (1- (length data)))
                             #\\))
                 (- (length data) 2))
                (t nil))))
        (when (and end
                   (not
                    (position-if
                     (lambda (character)
                       (or (char= character #\Escape)
                           (= (codepoint character) 7)))
                     data
                     :start (length prefix)
                     :end end)))
          (subseq data (length prefix) end))))))

(defun osc-11-background-color-response-p (data)
  (not (null (osc-11-body data))))

(defun parse-osc-11-background-color (data)
  (multiple-value-bind (target rgb matched-p)
      (parse-osc-color-response data)
    (when (and matched-p (eq target :background))
      rgb)))

(defparameter +terminal-palette-size+ 16)
(defparameter +terminal-color-reply-count+ 18)

(defun device-attributes-response-p (data)
  (and (stringp data)
       (cl-ppcre:scan
        (format nil "^~C\\[\\?[0-9;]*c$" #\Escape)
        data)))

(defun terminal-color-query-sequence ()
  (with-output-to-string (out)
    (format out "~C]10;?~C~C]11;?~C"
            #\Escape (code-char 7) #\Escape (code-char 7))
    (loop for index below +terminal-palette-size+
          do (format out "~C]4;~D;?~C"
                     #\Escape index (code-char 7)))
    (format out "~C[c" #\Escape)))

(defstruct terminal-color-query
  foreground
  background
  (palette (make-array 16 :initial-element nil))
  (replied nil)
  (open-p t))

(defun rgb-color-list (color)
  (when (rgb-color-p color)
    (list (rgb-color-red color)
          (rgb-color-green color)
          (rgb-color-blue color))))

(defun terminal-color-query-plist (query)
  (let ((palette
          (loop for index below +terminal-palette-size+
                for color = (aref (terminal-color-query-palette query)
                                  index)
                unless (rgb-color-p color)
                  return nil
                collect (rgb-color-list color))))
    (list :foreground
          (rgb-color-list (terminal-color-query-foreground query))
          :background
          (rgb-color-list (terminal-color-query-background query))
          :palette palette)))

(defun terminal-color-query-note (query data)
  (unless (terminal-color-query-open-p query)
    (return-from terminal-color-query-note nil))
  (when (device-attributes-response-p data)
    (setf (terminal-color-query-open-p query) nil)
    (return-from terminal-color-query-note :complete))
  (multiple-value-bind (target rgb matched-p)
      (parse-osc-color-response data)
    (unless matched-p
      (return-from terminal-color-query-note nil))
    (let ((key (if (keywordp target)
                   (symbol-name target)
                   (princ-to-string target))))
      (when (member key (terminal-color-query-replied query)
                    :test #'string=)
        (return-from terminal-color-query-note :duplicate))
      (push key (terminal-color-query-replied query))
      (cond
        ((eq target :foreground)
         (setf (terminal-color-query-foreground query) rgb))
        ((eq target :background)
         (setf (terminal-color-query-background query) rgb))
        ((and (integerp target)
              (<= 0 target (1- +terminal-palette-size+)))
         (setf (aref (terminal-color-query-palette query) target)
               (or rgb :missing)))))
    (if (= (length (terminal-color-query-replied query))
           +terminal-color-reply-count+)
        (progn
          (setf (terminal-color-query-open-p query) nil)
          :complete)
        :color)))

(defun parse-terminal-color-scheme-report (data)
  (cond
    ((string= data (format nil "~C[?997;1n" #\Escape))
     :dark)
    ((string= data (format nil "~C[?997;2n" #\Escape))
     :light)
    (t nil)))

(defun parse-cell-size-response (data)
  (let ((prefix (format nil "~C[6;" #\Escape)))
    (when (and (string-prefix-p prefix data)
               (plusp (length data))
               (char= (char data
                            (1- (length data)))
                      #\t))
      (let ((parts
              (uiop:split-string
               (subseq data
                       (length prefix)
                       (1- (length data)))
               :separator '(#\;))))
        (when (and (= (length parts) 2)
                   (every
                    (lambda (part)
                      (and (plusp (length part))
                           (every #'digit-char-p part)))
                    parts))
          (let ((height (parse-integer (first parts)))
                (width (parse-integer (second parts))))
            (when (and (plusp width) (plusp height))
              (values width height t))))))))

(defstruct (terminal-response-filter
            (:constructor make-terminal-response-filter ()))
  (pending-color-replies 0
                         :type (integer 0 *))
  (color-query nil)
  (color-result nil))

(defun terminal-response-expect-color (filter)
  (incf
   (terminal-response-filter-pending-color-replies
    filter))
  filter)

(defun terminal-response-consume (filter data)
  (let ((query (terminal-response-filter-color-query filter)))
    (when query
      (let ((status (terminal-color-query-note query data)))
        (when status
          (when (eq status :complete)
            (setf (terminal-response-filter-color-result filter)
                  (terminal-color-query-plist query))
            (setf (terminal-response-filter-color-query filter) nil))
          (return-from terminal-response-consume
            (values t status))))))
  (multiple-value-bind (width height cell-p)
      (parse-cell-size-response data)
    (when cell-p
      (set-cell-dimensions width height)
      (return-from terminal-response-consume
        (values t (list width height)))))
  (let ((scheme
          (parse-terminal-color-scheme-report data)))
    (when scheme
      (return-from terminal-response-consume
        (values t scheme))))
  (when (and
         (plusp
          (terminal-response-filter-pending-color-replies
           filter))
         (osc-11-background-color-response-p data))
    (decf
     (terminal-response-filter-pending-color-replies
      filter))
    (return-from terminal-response-consume
      (values t
              (parse-osc-11-background-color data))))
  (values nil data))
