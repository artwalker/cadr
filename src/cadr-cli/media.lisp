(in-package #:cadr-cli)

(defun read-binary-file (path)
  (with-open-file
      (stream path
              :direction :input
              :element-type '(unsigned-byte 8))
    (let ((bytes
            (make-array
             (file-length stream)
             :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      bytes)))

(defun bytes-prefix-p (bytes prefix)
  (and
   (>= (length bytes) (length prefix))
   (loop for expected across prefix
         for index from 0
         always (= expected (aref bytes index)))))

(defun ascii-prefix-p (bytes offset text)
  (and
   (>= (length bytes) (+ offset (length text)))
   (loop for character across text
         for index from offset
         always
         (= (char-code character)
            (aref bytes index)))))

(defun detect-image-mime-type (bytes)
  (cond
    ((bytes-prefix-p
      bytes
      #(137 80 78 71 13 10 26 10))
     "image/png")
    ((bytes-prefix-p bytes #(255 216 255))
     "image/jpeg")
    ((or (ascii-prefix-p bytes 0 "GIF87a")
         (ascii-prefix-p bytes 0 "GIF89a"))
     "image/gif")
    ((and (ascii-prefix-p bytes 0 "RIFF")
          (ascii-prefix-p bytes 8 "WEBP"))
     "image/webp")
    ((ascii-prefix-p bytes 0 "BM")
     "image/bmp")
    (t nil)))

(defparameter +base64-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defun encode-base64-bytes (bytes)
  (with-output-to-string (output)
    (loop for position from 0 below (length bytes) by 3
          for remaining = (- (length bytes) position)
          for first = (aref bytes position)
          for second =
          (if (> remaining 1)
              (aref bytes (1+ position)) 0)
          for third =
          (if (> remaining 2)
              (aref bytes (+ position 2)) 0)
          for packed =
          (logior (ash first 16)
                  (ash second 8)
                  third)
          do
          (write-char
           (char +base64-alphabet+
                 (ldb (byte 6 18) packed))
           output)
          (write-char
           (char +base64-alphabet+
                 (ldb (byte 6 12) packed))
           output)
          (write-char
           (if (> remaining 1)
               (char +base64-alphabet+
                     (ldb (byte 6 6) packed))
               #\=)
           output)
          (write-char
           (if (> remaining 2)
               (char +base64-alphabet+
                     (ldb (byte 6 0) packed))
               #\=)
           output))))

(defun u16-le (bytes offset)
  (logior
   (aref bytes offset)
   (ash (aref bytes (1+ offset)) 8)))

(defun u32-le (bytes offset)
  (logior
   (aref bytes offset)
   (ash (aref bytes (1+ offset)) 8)
   (ash (aref bytes (+ offset 2)) 16)
   (ash (aref bytes (+ offset 3)) 24)))

(defun s32-le (bytes offset)
  (let ((value (u32-le bytes offset)))
    (if (logbitp 31 value)
        (- value #x100000000)
        value)))

(defun append-u32-be (output value)
  (dotimes (index 4)
    (vector-push-extend
     (ldb (byte 8 (* 8 (- 3 index))) value)
     output)))

(defun crc32-octets (bytes)
  (let ((crc #xffffffff))
    (loop for octet across bytes
          do
          (setf crc (logxor crc octet))
          (dotimes (iteration 8)
            (declare (ignorable iteration))
            (setf crc
                  (if (logbitp 0 crc)
                      (logxor #xedb88320
                              (ash crc -1))
                      (ash crc -1)))))
    (logxor crc #xffffffff)))

(defun adler32-octets (bytes)
  (let ((first 1)
        (second 0))
    (loop for octet across bytes
          do
          (setf first (mod (+ first octet) 65521)
                second (mod (+ second first) 65521)))
    (logior (ash second 16) first)))

(defun stored-zlib-stream (bytes)
  (let ((output
          (make-array
           0 :element-type '(unsigned-byte 8)
           :adjustable t :fill-pointer 0)))
    ;; 0x7801 is a valid zlib header for a no-compression stream.
    (vector-push-extend #x78 output)
    (vector-push-extend #x01 output)
    (loop with position = 0
          while (< position (length bytes))
          for size = (min #xffff
                          (- (length bytes) position))
          for final-p = (= (+ position size)
                           (length bytes))
          do
          (vector-push-extend
           (if final-p 1 0) output)
          (vector-push-extend
           (ldb (byte 8 0) size) output)
          (vector-push-extend
           (ldb (byte 8 8) size) output)
          (let ((inverse (logxor size #xffff)))
            (vector-push-extend
             (ldb (byte 8 0) inverse) output)
            (vector-push-extend
             (ldb (byte 8 8) inverse) output))
          (loop for index from position
                  below (+ position size)
                do
                (vector-push-extend
                 (aref bytes index) output))
          (incf position size))
    (append-u32-be output (adler32-octets bytes))
    output))

(defun append-png-chunk (output type data)
  (append-u32-be output (length data))
  (let ((checksum-input
          (make-array
           (+ 4 (length data))
           :element-type '(unsigned-byte 8))))
    (loop for character across type
          for index from 0
          do
          (let ((octet (char-code character)))
            (setf (aref checksum-input index) octet)
            (vector-push-extend octet output)))
    (loop for octet across data
          for index from 4
          do
          (setf (aref checksum-input index) octet)
          (vector-push-extend octet output))
    (append-u32-be output
                   (crc32-octets checksum-input))))

(defun encode-rgba-png (rgba width height)
  (let ((raw
          (make-array
           (* height (1+ (* width 4)))
           :element-type '(unsigned-byte 8)))
        (position 0))
    (dotimes (row height)
      (setf (aref raw position) 0)
      (incf position)
      (replace raw rgba
               :start1 position
               :start2 (* row width 4)
               :end2 (* (1+ row) width 4))
      (incf position (* width 4)))
    (let ((output
            (make-array
             0 :element-type '(unsigned-byte 8)
             :adjustable t :fill-pointer 0))
          (header
            (make-array
             13 :element-type '(unsigned-byte 8)
             :initial-element 0)))
      (loop for octet across
            #(137 80 78 71 13 10 26 10)
            do (vector-push-extend octet output))
      (dotimes (index 4)
        (setf
         (aref header index)
         (ldb (byte 8 (* 8 (- 3 index))) width)
         (aref header (+ 4 index))
         (ldb (byte 8 (* 8 (- 3 index))) height)))
      (setf (aref header 8) 8
            (aref header 9) 6)
      (append-png-chunk output "IHDR" header)
      (append-png-chunk
       output "IDAT" (stored-zlib-stream raw))
      (append-png-chunk
       output "IEND"
       (make-array 0
                   :element-type '(unsigned-byte 8)))
      output)))

(defun bmp-to-png (bytes)
  (unless (and (ascii-prefix-p bytes 0 "BM")
               (>= (length bytes) 54))
    (error "Invalid BMP image"))
  (let* ((pixel-offset (u32-le bytes 10))
         (dib-size (u32-le bytes 14))
         (width (s32-le bytes 18))
         (signed-height (s32-le bytes 22))
         (height (abs signed-height))
         (planes (u16-le bytes 26))
         (bits-per-pixel (u16-le bytes 28))
         (compression (u32-le bytes 30)))
    (unless (and (>= dib-size 40)
                 (> width 0)
                 (> height 0)
                 (= planes 1)
                 (member bits-per-pixel '(24 32))
                 (zerop compression))
      (error "Unsupported BMP encoding"))
    (let* ((bytes-per-pixel (/ bits-per-pixel 8))
           (stride
             (* 4
                (ceiling
                 (* width bytes-per-pixel)
                 4)))
           (required
             (+ pixel-offset (* stride height))))
      (when (> required (length bytes))
        (error "Truncated BMP image"))
      (let ((rgba
              (make-array
               (* width height 4)
               :element-type '(unsigned-byte 8))))
        (dotimes (target-row height)
          (let* ((source-row
                   (if (minusp signed-height)
                       target-row
                       (- height target-row 1)))
                 (row-start
                   (+ pixel-offset
                      (* source-row stride))))
            (dotimes (column width)
              (let* ((source
                       (+ row-start
                          (* column bytes-per-pixel)))
                     (target
                       (* (+ (* target-row width)
                             column)
                          4)))
                (setf
                 (aref rgba target)
                 (aref bytes (+ source 2))
                 (aref rgba (+ target 1))
                 (aref bytes (+ source 1))
                 (aref rgba (+ target 2))
                 (aref bytes source)
                 (aref rgba (+ target 3))
                 (if (= bytes-per-pixel 4)
                     (aref bytes (+ source 3))
                     255))))))
        (encode-rgba-png rgba width height)))))

(defun process-image-file (path)
  (let* ((bytes (read-binary-file path))
         (mime-type (detect-image-mime-type bytes)))
    (when mime-type
      (if (string= mime-type "image/bmp")
          (values (bmp-to-png bytes) "image/png"
                  '("Converted BMP to PNG"))
          (values bytes mime-type nil)))))
