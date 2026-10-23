(in-package #:cadr-wasm)

(defparameter *obsolete-wat-operators*
  (let ((table (make-hash-table :test #'equal)))
    (dolist (name '("current_memory" "grow_memory" "get_local" "set_local"
                    "tee_local" "anyfunc" "get_global" "set_global"
                    "i32.wrap/i64" "i32.trunc_s:sat/f32"
                    "f32x4.convert_s/i32x4"))
      (setf (gethash name table) t))
    table))

(defun wat-hex-value (char)
  (let ((code (char-code char)))
    (cond ((<= 48 code 57) (- code 48))
          ((<= 97 code 102) (- code 87))
          ((<= 65 code 70) (- code 55)))))

(defun wat-push-byte (bytes value)
  (vector-push-extend (logand value #xff) bytes))

(defun wat-decode-string (text index)
  "Decode one WAT string starting at a quote. Return the index after it.
Signal wasm-malformed when the decoded bytes are not UTF-8."
  (let ((bytes (make-array 16 :element-type '(unsigned-byte 8)
                           :fill-pointer 0 :adjustable t))
        (length (length text)))
    (incf index)
    (loop
      (when (>= index length)
        (wasm-fail 'wasm-malformed "unexpected end of string"))
      (let ((char (char text index)))
        (cond
          ((char= char #\")
           (incf index)
           (loop for cursor = 0 then (+ cursor width)
                 while (< cursor (length bytes))
                 for width = (nth-value 1 (consume-utf8 bytes cursor)))
           (return index))
          ((char= char #\\)
           (incf index)
           (when (>= index length)
             (wasm-fail 'wasm-malformed "unexpected end of string"))
           (let ((escape (char text index)))
             (incf index)
             (cond
               ((char= escape #\n) (wat-push-byte bytes 10))
               ((char= escape #\t) (wat-push-byte bytes 9))
               ((char= escape #\r) (wat-push-byte bytes 13))
               ((char= escape #\') (wat-push-byte bytes 39))
               ((char= escape #\") (wat-push-byte bytes 34))
               ((char= escape #\\) (wat-push-byte bytes 92))
               ((char= escape #\u)
                (unless (and (< index length) (char= (char text index) #\{))
                  (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                (incf index)
                (let ((code 0)
                      (digits 0))
                  (loop
                    (when (>= index length)
                      (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                    (let ((digit (wat-hex-value (char text index))))
                      (when (null digit) (return))
                      (setf code (+ (* code 16) digit))
                      (incf digits)
                      (incf index)))
                  (unless (and (plusp digits)
                               (< index length)
                               (char= (char text index) #\})
                               (<= code #x10ffff))
                    (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                  (incf index)
                  (let ((encoded (sb-ext:string-to-octets
                                  (string (code-char code))
                                  :external-format :utf-8)))
                    (loop for byte across encoded do (wat-push-byte bytes byte)))))
               (t
                (let ((high (wat-hex-value escape))
                      (low (and (< index length) (wat-hex-value (char text index)))))
                  (unless (and high low)
                    (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                  (incf index)
                  (wat-push-byte bytes (+ (* high 16) low)))))))
          (t
           (let ((code (char-code char)))
             (if (< code 128)
                 (wat-push-byte bytes code)
                 (let ((encoded (sb-ext:string-to-octets
                                 (string char) :external-format :utf-8)))
                   (loop for byte across encoded do (wat-push-byte bytes byte)))))
           (incf index)))))))

(defun wat-token (text index)
  (let ((start index)
        (length (length text)))
    (loop while (and (< index length)
                     (not (member (char text index)
                                  '(#\( #\) #\; #\" #\space #\tab #\newline #\return))))
          do (incf index))
    (values (subseq text start index) index)))

(defun parse-module-text (text)
  "Reject a WebAssembly text module the way the spec interpreter does.
Quote malformed tests use this. Binary modules stay on parse-module."
  (let ((index 0)
        (length (length text)))
    (loop while (< index length) do
      (let ((char (char text index)))
        (cond
          ((member char '(#\space #\tab #\newline #\return))
           (incf index))
          ((char= char #\;)
           (loop while (and (< index length) (char/= (char text index) #\newline))
                 do (incf index)))
          ((char= char #\")
           (setf index (wat-decode-string text index)))
          ((or (char= char #\() (char= char #\)))
           (incf index))
          (t
           (multiple-value-bind (token next) (wat-token text index)
             (when (gethash token *obsolete-wat-operators*)
               (wasm-fail 'wasm-malformed
                          (format nil "unknown operator ~A" token)))
             (setf index next)))))))
  nil)
