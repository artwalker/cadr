(in-package #:cadr-cli)

(defclass octet-vector-input-stream
    (sb-gray:fundamental-binary-input-stream)
  ((bytes :initarg :bytes
          :reader octet-vector-input-bytes)
   (position :initform 0
             :accessor octet-vector-input-position)))

(defmethod stream-element-type
    ((stream octet-vector-input-stream))
  (declare (ignore stream))
  '(unsigned-byte 8))

(defmethod sb-gray:stream-read-byte
    ((stream octet-vector-input-stream))
  (let ((position
          (octet-vector-input-position stream))
        (bytes
          (octet-vector-input-bytes stream)))
    (if (>= position (length bytes))
        :eof
        (prog1
            (aref bytes position)
          (incf
           (octet-vector-input-position
            stream))))))

(defmethod sb-gray:stream-read-sequence
    ((stream octet-vector-input-stream)
     sequence
     &optional (start 0) end)
  (let* ((bytes
           (octet-vector-input-bytes stream))
         (position
           (octet-vector-input-position stream))
         (end
           (or end (length sequence)))
         (count
           (min (- end start)
                (- (length bytes) position))))
    (replace sequence bytes
             :start1 start
             :end1 (+ start count)
             :start2 position
             :end2 (+ position count))
    (incf
     (octet-vector-input-position stream)
     count)
    (+ start count)))

(defclass octet-vector-output-stream
    (sb-gray:fundamental-binary-output-stream)
  ((bytes
     :initform
     (make-array
      0 :element-type '(unsigned-byte 8)
      :adjustable t :fill-pointer 0)
     :reader octet-vector-output-bytes)))

(defmethod stream-element-type
    ((stream octet-vector-output-stream))
  (declare (ignore stream))
  '(unsigned-byte 8))

(defmethod sb-gray:stream-write-byte
    ((stream octet-vector-output-stream)
     byte)
  (vector-push-extend
   byte
   (octet-vector-output-bytes stream))
  byte)

(defmethod sb-gray:stream-write-sequence
    ((stream octet-vector-output-stream)
     sequence
     &optional (start 0) end)
  (loop for index from start below
        (or end (length sequence))
        do
        (vector-push-extend
         (aref sequence index)
         (octet-vector-output-bytes stream)))
  sequence)

(defun simple-octet-vector (bytes)
  (make-array
   (length bytes)
   :element-type '(unsigned-byte 8)
   :initial-contents bytes))

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

(defstruct decoded-rgba-image
  rgba
  (width 0 :type (integer 0 *))
  (height 0 :type (integer 0 *)))

(defun png-sample-to-octet (value bit-depth)
  (if (= bit-depth 8)
      value
      (round
       (* value 255)
       (1- (ash 1 bit-depth)))))

(defun png-state-to-rgba (state)
  (let* ((width (png-read:width state))
         (height (png-read:height state))
         (bit-depth (png-read:bit-depth state))
         (colour-type (png-read:colour-type state))
         (image-data (png-read:image-data state))
         (transparency
           (png-read:transparency state))
         (rgba
           (make-array
            (* width height 4)
            :element-type '(unsigned-byte 8))))
    (labels
        ((sample (x y component)
           (png-sample-to-octet
            (if component
                (aref image-data x y component)
                (aref image-data x y))
            (if (eq colour-type
                    :indexed-colour)
                8
                bit-depth)))
         (mapped-alpha (x y)
           (if (and transparency
                    (arrayp transparency)
                    (= 2
                       (array-rank transparency)))
               (png-sample-to-octet
                (aref transparency x y)
                (if (> (array-total-size
                        transparency)
                       0)
                    (if (> (aref transparency x y)
                           255)
                        16
                        8)
                    8))
               255)))
      (dotimes (y height)
        (dotimes (x width)
          (let ((target
                  (* (+ (* y width) x) 4)))
            (ecase colour-type
              (:greyscale
               (let ((grey (sample x y nil)))
                 (setf
                  (aref rgba target) grey
                  (aref rgba (+ target 1)) grey
                  (aref rgba (+ target 2)) grey
                  (aref rgba (+ target 3))
                  (mapped-alpha x y))))
              ((:truecolor :indexed-colour)
               (setf
                (aref rgba target) (sample x y 0)
                (aref rgba (+ target 1))
                (sample x y 1)
                (aref rgba (+ target 2))
                (sample x y 2)
                (aref rgba (+ target 3))
                (mapped-alpha x y)))
              (:greyscale-alpha
               (let ((grey (sample x y 0)))
                 (setf
                  (aref rgba target) grey
                  (aref rgba (+ target 1)) grey
                  (aref rgba (+ target 2)) grey
                  (aref rgba (+ target 3))
                  (sample x y 1))))
              (:truecolor-alpha
               (setf
                (aref rgba target) (sample x y 0)
                (aref rgba (+ target 1))
                (sample x y 1)
                (aref rgba (+ target 2))
                (sample x y 2)
                (aref rgba (+ target 3))
                (sample x y 3))))))))
    (make-decoded-rgba-image
     :rgba rgba
     :width width
     :height height)))

(defun decode-png-rgba (bytes)
  (let ((stream
          (make-instance
           'octet-vector-input-stream
           :bytes bytes)))
    (multiple-value-bind (state crc-ok-p)
        (png-read:read-png-datastream stream)
      (unless crc-ok-p
        (error "PNG checksum validation failed"))
      (png-state-to-rgba state))))

(defun jpeg-buffer-to-rgba
    (buffer width height components)
  (let* ((source
           (if (= components 4)
               (jpeg:convert-cmyk-to-rgb
                buffer height width)
               buffer))
         (source-components
           (if (= components 4)
               3
               components))
         (rgba
           (make-array
            (* width height 4)
            :element-type '(unsigned-byte 8))))
    (unless (member source-components '(1 3))
      (error "Unsupported JPEG component count: ~D"
             components))
    (dotimes (pixel (* width height))
      (let ((target (* pixel 4))
            (source-position
              (* pixel source-components)))
        (if (= source-components 1)
            (let ((grey
                    (aref source source-position)))
              (setf
               (aref rgba target) grey
               (aref rgba (+ target 1)) grey
               (aref rgba (+ target 2)) grey))
            ;; cl-jpeg exposes decoded three-channel pixels as BGR.
            (setf
             (aref rgba target)
             (aref source (+ source-position 2))
             (aref rgba (+ target 1))
             (aref source (+ source-position 1))
             (aref rgba (+ target 2))
             (aref source source-position)))
        (setf (aref rgba (+ target 3)) 255)))
    (make-decoded-rgba-image
     :rgba rgba
     :width width
     :height height)))

(defun plausible-jpeg-sof-marker-p
    (bytes position)
  (and
   (<= (+ position 10) (length bytes))
   (= (aref bytes position) #xff)
   (member
    (aref bytes (1+ position))
    '(#xc0 #xc1 #xc2 #xc3
      #xc5 #xc6 #xc7
      #xc9 #xca #xcb
      #xcd #xce #xcf))
   (let* ((segment-length
            (bounded-u16
             bytes (+ position 2) nil))
          (components
            (aref bytes (+ position 9))))
     (and
      segment-length
      (member (aref bytes (+ position 4))
              '(8 12))
      (<= 1 components 4)
      (= segment-length
         (+ 8 (* components 3)))
      (plusp
       (bounded-u16
        bytes (+ position 5) nil))
      (plusp
       (bounded-u16
        bytes (+ position 7) nil))
      (<= (+ position 2 segment-length)
          (length bytes))))))

(defun insert-repeated-octets
    (bytes position count octet)
  (let ((output
          (make-array
           (+ (length bytes) count)
           :element-type '(unsigned-byte 8)
           :initial-element octet)))
    (replace output bytes :end2 position)
    (replace output bytes
             :start1 (+ position count)
             :start2 position)
    output))

(defun repair-one-truncated-jpeg-quantization-table
    (bytes)
  ;; Photon accepts a few producer-generated JPEGs whose DQT length includes
  ;; missing trailing values. cl-jpeg follows the declared length literally,
  ;; so pad only when a structurally valid SOF begins inside that DQT.
  (loop with position = 2
        while (< (+ position 4)
                 (length bytes))
        do
        (unless (= (aref bytes position) #xff)
          (return bytes))
        (loop while
              (and (< position (length bytes))
                   (= (aref bytes position) #xff))
              do (incf position))
        (when (>= position (length bytes))
          (return bytes))
        (let ((marker (aref bytes position)))
          (decf position)
          (when (member marker '(#xd9 #xda))
            (return bytes))
          (when (member marker
                        '(#xd0 #xd1 #xd2 #xd3
                          #xd4 #xd5 #xd6 #xd7 #xd8))
            (incf position 2)
            (loop-finish))
          (let* ((segment-length
                   (bounded-u16
                    bytes (+ position 2) nil))
                 (declared-end
                   (and segment-length
                        (+ position 2
                           segment-length))))
            (unless (and segment-length
                         (>= segment-length 2))
              (return bytes))
            (when (= marker #xdb)
              (let ((sof-position
                      (loop for candidate
                            from (+ position 4)
                              below
                              (min
                               (or declared-end
                                   (length bytes))
                               (length bytes))
                            when
                            (plausible-jpeg-sof-marker-p
                             bytes candidate)
                              return candidate)))
                (when (and sof-position
                           (> declared-end
                              sof-position))
                  (return
                    (insert-repeated-octets
                     bytes sof-position
                     (- declared-end sof-position)
                     (if (> sof-position
                            (+ position 4))
                         (aref bytes
                               (1- sof-position))
                         1))))))
            (unless (<= declared-end
                        (length bytes))
              (return bytes))
            (setf position declared-end)))
        finally (return bytes)))

(defun repair-truncated-jpeg-quantization-tables
    (bytes)
  (loop with current = bytes
        repeat 4
        for repaired =
        (repair-one-truncated-jpeg-quantization-table
         current)
        when (= (length repaired)
                (length current))
          return repaired
        do (setf current repaired)
        finally (return current)))

(defun decode-jpeg-rgba (bytes)
  (let* ((repaired
           (repair-truncated-jpeg-quantization-tables
            bytes))
         (stream
          (make-instance
           'octet-vector-input-stream
           :bytes repaired)))
    (multiple-value-bind
          (buffer height width components)
        (jpeg:decode-stream stream)
      (jpeg-buffer-to-rgba
       buffer width height components))))

(defun bounded-u16 (bytes offset little-endian-p)
  (when (<= (+ offset 2) (length bytes))
    (if little-endian-p
        (logior
         (aref bytes offset)
         (ash (aref bytes (1+ offset)) 8))
        (logior
         (ash (aref bytes offset) 8)
         (aref bytes (1+ offset))))))

(defun bounded-u32 (bytes offset little-endian-p)
  (when (<= (+ offset 4) (length bytes))
    (if little-endian-p
        (logior
         (aref bytes offset)
         (ash (aref bytes (+ offset 1)) 8)
         (ash (aref bytes (+ offset 2)) 16)
         (ash (aref bytes (+ offset 3)) 24))
        (logior
         (ash (aref bytes offset) 24)
         (ash (aref bytes (+ offset 1)) 16)
         (ash (aref bytes (+ offset 2)) 8)
         (aref bytes (+ offset 3))))))

(defun exif-header-p (bytes offset)
  (and (<= (+ offset 6) (length bytes))
       (ascii-prefix-p bytes offset
                       (coerce
                        '(#\E #\x #\i #\f #\Null #\Null)
                        'string))))

(defun jpeg-exif-tiff-offset (bytes)
  (when (and (>= (length bytes) 4)
             (= (aref bytes 0) #xff)
             (= (aref bytes 1) #xd8))
    (loop with offset = 2
          while (< (+ offset 4)
                   (length bytes))
          do
          (unless (= (aref bytes offset) #xff)
            (return nil))
          (loop while
                (and (< offset (length bytes))
                     (= (aref bytes offset) #xff))
                do (incf offset))
          (when (>= offset (length bytes))
            (return nil))
          (let ((marker (aref bytes offset)))
            (incf offset)
            (when (member marker '(#xd9 #xda))
              (return nil))
            (when (> (+ offset 2) (length bytes))
              (return nil))
            (let ((size
                    (bounded-u16 bytes offset nil)))
              (when (or (null size)
                        (< size 2)
                        (> (+ offset size)
                           (length bytes)))
                (return nil))
              (when (= marker #xe1)
                (let ((payload (+ offset 2)))
                  (when (exif-header-p bytes payload)
                    (return (+ payload 6)))))
              (incf offset size))))))

(defun jpeg-exif-orientation (bytes)
  (handler-case
      (let ((tiff-start
              (jpeg-exif-tiff-offset bytes)))
        (unless (and tiff-start
                     (<= (+ tiff-start 8)
                         (length bytes)))
          (return-from jpeg-exif-orientation 1))
        (let* ((byte-order
                 (bounded-u16 bytes tiff-start nil))
               (little-endian-p
                 (= byte-order #x4949)))
          (unless (or little-endian-p
                      (= byte-order #x4d4d))
            (return-from jpeg-exif-orientation 1))
          (unless (= (bounded-u16
                      bytes (+ tiff-start 2)
                      little-endian-p)
                     42)
            (return-from jpeg-exif-orientation 1))
          (let* ((ifd-offset
                   (bounded-u32
                    bytes (+ tiff-start 4)
                    little-endian-p))
                 (ifd-start
                   (and ifd-offset
                        (+ tiff-start ifd-offset)))
                 (entry-count
                   (and ifd-start
                        (bounded-u16
                         bytes ifd-start
                         little-endian-p))))
            (unless entry-count
              (return-from jpeg-exif-orientation 1))
            (dotimes (index entry-count 1)
              (let ((entry
                      (+ ifd-start 2 (* index 12))))
                (unless (<= (+ entry 12)
                            (length bytes))
                  (return 1))
                (when (= (bounded-u16
                          bytes entry
                          little-endian-p)
                         #x0112)
                  (let ((orientation
                          (bounded-u16
                           bytes (+ entry 8)
                           little-endian-p)))
                    (return
                      (if (and orientation
                               (<= 1 orientation 8))
                          orientation
                          1)))))))))
    (condition () 1)))

(defun orient-rgba-image (image orientation)
  (if (= orientation 1)
      image
      (let* ((source-width
               (decoded-rgba-image-width image))
             (source-height
               (decoded-rgba-image-height image))
             (swapped-p
               (member orientation '(5 6 7 8)))
             (target-width
               (if swapped-p
                   source-height
                   source-width))
             (target-height
               (if swapped-p
                   source-width
                   source-height))
             (source
               (decoded-rgba-image-rgba image))
             (target
               (make-array
                (* target-width target-height 4)
                :element-type '(unsigned-byte 8))))
        (dotimes (source-y source-height)
          (dotimes (source-x source-width)
            (multiple-value-bind (target-x target-y)
                (case orientation
                  (2 (values
                      (- source-width source-x 1)
                      source-y))
                  (3 (values
                      (- source-width source-x 1)
                      (- source-height source-y 1)))
                  (4 (values
                      source-x
                      (- source-height source-y 1)))
                  (5 (values source-y source-x))
                  (6 (values
                      (- source-height source-y 1)
                      source-x))
                  (7 (values
                      (- source-height source-y 1)
                      (- source-width source-x 1)))
                  (8 (values
                      source-y
                      (- source-width source-x 1))))
              (let ((source-position
                      (* (+ (* source-y source-width)
                            source-x)
                         4))
                    (target-position
                      (* (+ (* target-y target-width)
                            target-x)
                         4)))
                (replace target source
                         :start1 target-position
                         :end1 (+ target-position 4)
                         :start2 source-position
                         :end2 (+ source-position 4))))))
        (make-decoded-rgba-image
         :rgba target
         :width target-width
         :height target-height))))

(defun decode-image-rgba
    (bytes mime-type
     &key (apply-orientation-p t))
  (handler-case
      (let* ((image
               (cond
                 ((string= mime-type "image/png")
                  (decode-png-rgba bytes))
                 ((string= mime-type "image/jpeg")
                  (decode-jpeg-rgba bytes))
                 (t nil)))
             (oriented
               (if (and image
                        apply-orientation-p
                        (string= mime-type
                                 "image/jpeg"))
                   (orient-rgba-image
                    image
                    (jpeg-exif-orientation bytes))
                   image)))
        (when oriented
          (values
           (decoded-rgba-image-rgba oriented)
           (decoded-rgba-image-width oriented)
           (decoded-rgba-image-height oriented))))
    (condition ()
      (values nil nil nil))))

(defparameter +jpeg-luminance-quantization+
  #2A((16 11 10 16 24 40 51 61)
      (12 12 14 19 26 58 60 55)
      (14 13 16 24 40 57 69 56)
      (14 17 22 29 51 87 80 62)
      (18 22 37 56 68 109 103 77)
      (24 35 55 64 81 104 113 92)
      (49 64 78 87 103 121 120 101)
      (72 92 95 98 112 100 103 99)))

(defparameter +jpeg-chrominance-quantization+
  #2A((17 18 24 47 99 99 99 99)
      (18 21 26 66 99 99 99 99)
      (24 26 56 99 99 99 99 99)
      (47 66 99 99 99 99 99 99)
      (99 99 99 99 99 99 99 99)
      (99 99 99 99 99 99 99 99)
      (99 99 99 99 99 99 99 99)
      (99 99 99 99 99 99 99 99)))

(defun jpeg-quantization-table (source quality)
  (let* ((quality
           (max 1 (min 100 quality)))
         (scale
           (if (< quality 50)
               (floor 5000 quality)
               (- 200 (* quality 2)))))
    (make-array
     8
     :initial-contents
     (loop for y below 8
           collect
           (make-array
            8
            :element-type '(unsigned-byte 8)
            :initial-contents
            (loop for x below 8
                  collect
                  (max 1
                       (min
                        255
                        (floor
                         (+ (* (aref source y x)
                               scale)
                            50)
                         100)))))))))

(defun jpeg-quantization-tables (quality)
  (vector
   (jpeg-quantization-table
    +jpeg-luminance-quantization+ quality)
   (jpeg-quantization-table
    +jpeg-chrominance-quantization+ quality)))

(defun encode-rgba-jpeg
    (rgba width height quality)
  (let ((bgr
          (make-array
           (* width height 3)
           :element-type '(unsigned-byte 8))))
    (dotimes (pixel (* width height))
      (let* ((source (* pixel 4))
             (target (* pixel 3))
             (alpha (aref rgba (+ source 3))))
        (labels
            ((opaque-channel (channel)
               (round
                (+ (* (aref rgba (+ source channel))
                      alpha)
                   (* 255 (- 255 alpha)))
                255)))
          (setf
           (aref bgr target)
           (opaque-channel 2)
           (aref bgr (+ target 1))
           (opaque-channel 1)
           (aref bgr (+ target 2))
           (opaque-channel 0)))))
    (let ((stream
            (make-instance
             'octet-vector-output-stream)))
      (jpeg:encode-image-stream
       stream bgr 3 height width
       :q-tabs
       (jpeg-quantization-tables quality)
       :q-factor 64)
      (simple-octet-vector
       (octet-vector-output-bytes stream)))))

(defun lanczos3-kernel (value)
  (let ((absolute (abs value)))
    (cond
      ((< absolute 1d-12) 1d0)
      ((>= absolute 3d0) 0d0)
      (t
       (* (/ (sin (* pi absolute))
             (* pi absolute))
          (/ (sin (/ (* pi absolute) 3d0))
             (/ (* pi absolute) 3d0)))))))

(defun resample-rgba-horizontal
    (source source-width source-height target-width)
  (let ((target
          (make-array
           (* target-width source-height 4)
           :element-type '(unsigned-byte 8)))
        (ratio
          (/ (coerce source-width 'double-float)
             target-width)))
    (dotimes (y source-height)
      (dotimes (target-x target-width)
        (let* ((center
                 (- (* (+ target-x 0.5d0) ratio)
                    0.5d0))
               (filter-scale (max 1d0 ratio))
               (support (* 3d0 filter-scale))
               (first-source
                 (ceiling (- center support)))
               (last-source
                 (floor (+ center support)))
               (weights (make-array 4
                                    :element-type
                                    'double-float
                                    :initial-element
                                    0d0))
               (weight-total 0d0))
          (loop for source-x from first-source
                to last-source
                for clamped-x =
                (max 0
                     (min (1- source-width)
                          source-x))
                for weight =
                (lanczos3-kernel
                 (/ (- center source-x)
                    filter-scale))
                unless (zerop weight)
                  do
                  (incf weight-total weight)
                  (dotimes (channel 4)
                    (incf
                     (aref weights channel)
                     (* weight
                        (aref
                         source
                         (+ (* (+ (* y source-width)
                                  clamped-x)
                               4)
                            channel))))))
          (let ((target-position
                  (* (+ (* y target-width)
                        target-x)
                     4)))
            (dotimes (channel 4)
              (setf
               (aref target
                     (+ target-position channel))
               (max 0
                    (min 255
                         (round
                          (aref weights channel)
                          weight-total)))))))))
    target))

(defun resample-rgba-vertical
    (source width source-height target-height)
  (let ((target
          (make-array
           (* width target-height 4)
           :element-type '(unsigned-byte 8)))
        (ratio
          (/ (coerce source-height 'double-float)
             target-height)))
    (dotimes (target-y target-height)
      (let* ((center
               (- (* (+ target-y 0.5d0) ratio)
                  0.5d0))
             (filter-scale (max 1d0 ratio))
             (support (* 3d0 filter-scale))
             (first-source
               (ceiling (- center support)))
             (last-source
               (floor (+ center support))))
        (dotimes (x width)
          (let ((weights
                  (make-array 4
                              :element-type
                              'double-float
                              :initial-element
                              0d0))
                (weight-total 0d0))
            (loop for source-y from first-source
                  to last-source
                  for clamped-y =
                  (max 0
                       (min (1- source-height)
                            source-y))
                  for weight =
                  (lanczos3-kernel
                   (/ (- center source-y)
                      filter-scale))
                  unless (zerop weight)
                    do
                    (incf weight-total weight)
                    (dotimes (channel 4)
                      (incf
                       (aref weights channel)
                       (* weight
                          (aref
                           source
                           (+ (* (+ (* clamped-y width)
                                    x)
                                 4)
                              channel))))))
            (let ((target-position
                    (* (+ (* target-y width) x)
                       4)))
              (dotimes (channel 4)
                (setf
                 (aref target
                       (+ target-position channel))
                 (max 0
                      (min 255
                           (round
                            (aref weights channel)
                            weight-total))))))))))
    target))

(defun resample-rgba-lanczos3
    (rgba source-width source-height
     target-width target-height)
  (if (and (= source-width target-width)
           (= source-height target-height))
      (copy-seq rgba)
      (let ((horizontal
              (if (= source-width target-width)
                  (copy-seq rgba)
                  (resample-rgba-horizontal
                   rgba source-width source-height
                   target-width))))
        (if (= source-height target-height)
            horizontal
            (resample-rgba-vertical
             horizontal target-width source-height
             target-height)))))

(defun base64-encoded-byte-size (bytes)
  (* 4 (ceiling (length bytes) 3)))

(defun image-encoding-candidates
    (rgba width height jpeg-quality)
  (cons
   (cons (encode-rgba-png rgba width height)
         "image/png")
   (loop with qualities =
         (remove-duplicates
          (list jpeg-quality 85 70 55 40))
         for quality in qualities
         collect
         (cons
          (encode-rgba-jpeg
           rgba width height quality)
          "image/jpeg"))))

(defun resize-image-rgba-to-limits
    (rgba original-width original-height
     max-width max-height max-bytes
     &key (jpeg-quality 80))
  (when (or (< max-width 1)
            (< max-height 1)
            (< max-bytes 1))
    (return-from
        resize-image-rgba-to-limits
      (values nil nil nil nil)))
  (let ((target-width original-width)
        (target-height original-height))
    (when (> target-width max-width)
      (setf target-height
            (max 1
                 (round
                  (* target-height max-width)
                  target-width))
            target-width max-width))
    (when (> target-height max-height)
      (setf target-width
            (max 1
                 (round
                  (* target-width max-height)
                  target-height))
            target-height max-height))
    (loop
      (let ((resized
              (resample-rgba-lanczos3
               rgba original-width original-height
               target-width target-height)))
        (dolist
            (candidate
             (image-encoding-candidates
              resized target-width target-height
              jpeg-quality))
          (when (<
                 (base64-encoded-byte-size
                  (car candidate))
                 max-bytes)
            (return-from
                resize-image-rgba-to-limits
              (values
               (car candidate)
               (cdr candidate)
               target-width
               target-height)))))
      (when (and (= target-width 1)
                 (= target-height 1))
        (return
          (values nil nil nil nil)))
      (let ((next-width
              (if (= target-width 1)
                  1
                  (max
                   1
                   (floor (* target-width
                             0.75d0)))))
            (next-height
              (if (= target-height 1)
                  1
                  (max
                   1
                   (floor (* target-height
                             0.75d0))))))
        (when (and (= next-width target-width)
                   (= next-height target-height))
          (return
            (values nil nil nil nil)))
        (setf target-width next-width
              target-height next-height)))))

(defun convert-image-bytes-to-png
    (bytes mime-type)
  (handler-case
      (cond
        ((string= mime-type "image/png")
         (copy-seq bytes))
        ((string= mime-type "image/bmp")
         (bmp-to-png bytes))
        ((string= mime-type "image/jpeg")
         (multiple-value-bind (rgba width height)
             (decode-image-rgba
              bytes mime-type)
           (and rgba
                (encode-rgba-png
                 rgba width height))))
        (t nil))
    (condition () nil)))

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
