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
  (let ((body (osc-11-body data)))
    (unless body
      (return-from parse-osc-11-background-color nil))
    (let ((value
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             body)))
      (cond
        ((and (plusp (length value))
              (char= (char value 0) #\#))
         (let ((hex (subseq value 1)))
           (cond
             ((and (= (length hex) 6)
                   (strict-hex-string-p hex))
              (make-rgb-color
               :red (parse-integer hex :start 0 :end 2
                                   :radix 16)
               :green (parse-integer hex :start 2 :end 4
                                     :radix 16)
               :blue (parse-integer hex :start 4 :end 6
                                    :radix 16)))
             ((and (= (length hex) 12)
                   (strict-hex-string-p hex))
              (make-rgb-color
               :red (parse-osc-hex-channel
                     (subseq hex 0 4))
               :green (parse-osc-hex-channel
                       (subseq hex 4 8))
               :blue (parse-osc-hex-channel
                      (subseq hex 8 12))))
             (t nil))))
        (t
         (let* ((colon (position #\: value))
                (prefix
                  (and colon
                       (string-downcase
                        (subseq value 0 colon))))
                (channels
                  (uiop:split-string
                   (if (member prefix '("rgb" "rgba")
                               :test #'string=)
                       (subseq value (1+ colon))
                       value)
                   :separator '(#\/))))
           (when (= (length channels) 3)
             (let ((red (parse-osc-hex-channel
                         (first channels)))
                   (green (parse-osc-hex-channel
                           (second channels)))
                   (blue (parse-osc-hex-channel
                          (third channels))))
               (when (and red green blue)
                 (make-rgb-color
                  :red red :green green :blue blue))))))))))

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
  (consume-color-replies-p nil :type boolean))

(defun terminal-response-expect-color (filter)
  (setf
   (terminal-response-filter-consume-color-replies-p filter)
   t)
  filter)

(defun terminal-response-consume (filter data)
  (multiple-value-bind (width height cell-p)
      (parse-cell-size-response data)
    (when cell-p
      (set-cell-dimensions width height)
      (return-from terminal-response-consume
        (values t (list width height)))))
  (when (and
         (terminal-response-filter-consume-color-replies-p filter)
         (osc-11-background-color-response-p data))
    (return-from terminal-response-consume
      (values t
              (parse-osc-11-background-color data))))
  (values nil data))
