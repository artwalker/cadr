(in-package #:cadr-ai)

;;; Stable IDs

(defun u32-multiply (left right)
  (logand #xffffffff (* (logand #xffffffff left)
                       (logand #xffffffff right))))

(defun javascript-utf16-code-units (string)
  (loop for character across string
        for code = (char-code character)
        if (<= code #xffff)
          collect code
        else
          append (let ((adjusted (- code #x10000)))
                   (list (+ #xd800 (ash adjusted -10))
                         (+ #xdc00 (logand adjusted #x3ff))))))

(defun unsigned-base36 (value)
  (let ((alphabet "0123456789abcdefghijklmnopqrstuvwxyz")
        (value (logand #xffffffff value)))
    (if (zerop value)
        "0"
        (with-output-to-string (output)
          (labels ((write-digits (number)
                     (multiple-value-bind (quotient remainder)
                         (floor number 36)
                       (when (plusp quotient)
                         (write-digits quotient))
                       (write-char (char alphabet remainder) output))))
            (write-digits value))))))

(defun short-hash (string)
  "Return the fixed-baseline two-word hash over JavaScript UTF-16 code units."
  (let ((h1 #xdeadbeef)
        (h2 #x41c6ce57))
    (dolist (unit (javascript-utf16-code-units string))
      (setf h1 (u32-multiply (logxor h1 unit) 2654435761)
            h2 (u32-multiply (logxor h2 unit) 1597334677)))
    (setf h1
          (logxor
           (u32-multiply (logxor h1 (ash h1 -16)) 2246822507)
           (u32-multiply (logxor h2 (ash h2 -13)) 3266489909)))
    (setf h2
          (logxor
           (u32-multiply (logxor h2 (ash h2 -16)) 2246822507)
           (u32-multiply (logxor h1 (ash h1 -13)) 3266489909)))
    (concatenate 'string
                 (unsigned-base36 h2)
                 (unsigned-base36 h1))))

;;; Repairable and partial JSON

(defun valid-json-escape-character-p (character)
  (and character (find character "\"\\/bfnrtu")))

(defun write-json-control-escape (character output)
  (case character
    (#\Backspace (write-string "\\b" output))
    (#\Page (write-string "\\f" output))
    (#\Newline (write-string "\\n" output))
    (#\Return (write-string "\\r" output))
    (#\Tab (write-string "\\t" output))
    (otherwise
     (format output "\\u~4,'0x" (char-code character)))))

(defun valid-unicode-escape-at-p (json index)
  (and (<= (+ index 5) (1- (length json)))
       (loop for offset from 2 to 5
             always (digit-char-p (char json (+ index offset)) 16))))

(defun repair-json (json)
  (with-output-to-string (output)
    (let ((in-string-p nil)
          (index 0))
      (loop while (< index (length json))
            for character = (char json index)
            do
            (cond
              ((not in-string-p)
               (write-char character output)
               (when (char= character #\")
                 (setf in-string-p t)))
              ((char= character #\")
               (write-char character output)
               (setf in-string-p nil))
              ((char= character #\\)
               (let ((next (and (< (1+ index) (length json))
                                (char json (1+ index)))))
                 (cond
                   ((null next)
                    (write-string "\\\\" output))
                   ((and (char= next #\u)
                         (valid-unicode-escape-at-p json index))
                    (write-string json output :start index :end (+ index 6))
                    (incf index 5))
                   ((valid-json-escape-character-p next)
                    (write-char #\\ output)
                    (write-char next output)
                    (incf index))
                   (t
                    (write-string "\\\\" output)))))
              ((< (char-code character) #x20)
               (write-json-control-escape character output))
              (t
               (write-char character output)))
            (incf index)))))

(defun parse-json-with-repair (json)
  (handler-case
      (parse-json json)
    (json-parse-error (original)
      (let ((repaired (repair-json json)))
        (if (string= repaired json)
            (error original)
            (parse-json repaired))))))

(defun complete-json-prefix (prefix)
  (let ((stack nil)
        (in-string-p nil)
        (escaped-p nil))
    (loop for character across prefix
          do
          (cond
            (in-string-p
             (cond
               (escaped-p (setf escaped-p nil))
               ((char= character #\\) (setf escaped-p t))
               ((char= character #\") (setf in-string-p nil))))
            ((char= character #\") (setf in-string-p t))
            ((char= character #\{) (push #\} stack))
            ((char= character #\[) (push #\] stack))
            ((or (char= character #\}) (char= character #\]))
             (unless (and stack (char= character (first stack)))
               (return-from complete-json-prefix nil))
             (pop stack))))
    (with-output-to-string (output)
      (write-string prefix output)
      (when escaped-p
        (write-char #\\ output))
      (when in-string-p
        (write-char #\" output))
      (dolist (closer stack)
        (write-char closer output)))))

(defun parse-streaming-json (partial-json)
  (when (or (null partial-json)
            (zerop (length (string-trim '(#\Space #\Tab #\Return #\Newline)
                                        partial-json))))
    (return-from parse-streaming-json (make-hash-table :test #'equal)))
  (handler-case
      (parse-json-with-repair partial-json)
    (error ()
      (let ((repaired (repair-json partial-json)))
        (loop for end from (length repaired) downto 1
              for candidate = (complete-json-prefix (subseq repaired 0 end))
              when candidate
                do (handler-case
                       (return-from parse-streaming-json
                         (parse-json candidate))
                     (error () nil))))
      (make-hash-table :test #'equal))))
