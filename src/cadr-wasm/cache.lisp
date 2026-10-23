(in-package #:cadr-wasm)

(defvar *compile-cache* (make-hash-table :test #'equal))
(defvar *last-compile-seconds* nil)
(defvar *last-compile-cached-p* nil)

(defun last-compile-seconds () *last-compile-seconds*)
(defun last-compile-cached-p () *last-compile-cached-p*)
(defun clear-compile-cache ()
  (clrhash *compile-cache*)
  nil)

;; quickjs-wasi@3.6.2 quickjs.wasm. MIT license, Fabrice Bellard and contributors.
(defparameter +quickjs-wasm-sha256+
  "d4c9375f2b1ca4dc95f72c8aa2982a7a9951ac8011490d79c6582df732b4bbd9")

(defun quickjs-wasm-sha256 () +quickjs-wasm-sha256+)

(defun vendor-file (name)
  (asdf:system-relative-pathname "cadr-wasm" (merge-pathnames name #p"src/cadr-wasm/vendor/")))

(defun decode-base64 (text)
  (let* ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
         (clean (remove-if (lambda (char) (member char '(#\newline #\return #\space))) text))
         (out (make-array (length clean) :element-type '(unsigned-byte 8) :fill-pointer 0)))
    (loop for i from 0 below (length clean) by 4
          for a = (position (char clean i) alphabet)
          for b = (position (char clean (+ i 1)) alphabet)
          for c = (and (< (+ i 2) (length clean)) (position (char clean (+ i 2)) alphabet))
          for d = (and (< (+ i 3) (length clean)) (position (char clean (+ i 3)) alphabet))
          do (vector-push (logior (ash a 2) (ash b -4)) out)
             (when c (vector-push (logand (logior (ash b 4) (ash c -2)) #xff) out))
             (when d (vector-push (logand (logior (ash c 6) d) #xff) out)))
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun quickjs-wasm-bytes ()
  (decode-base64 (uiop:read-file-string (vendor-file "quickjs.wasm.b64"))))

(defun sha256-hex (octets)
  (let* ((k (vector
             #x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
             #xd807aa98 #x12835b01 #x243185be #x550c7dc3 #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
             #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
             #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
             #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13 #x650a7354 #x766a0abb #x81c2c92e #x92722c85
             #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
             #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
             #x748f82ee #x78a5636f #x84c87814 #x8cc70208 #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))
         (h (vector #x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
                    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))
         (bit-length (* (length octets) 8))
         (padded (make-array (+ (length octets) 1 8
                                (mod (- 64 (mod (+ (length octets) 9) 64)) 64))
                             :element-type '(unsigned-byte 8)
                             :initial-element 0)))
    (replace padded octets)
    (setf (aref padded (length octets)) #x80)
    (loop for i from 0 below 8 do
      (setf (aref padded (- (length padded) 1 i)) (ldb (byte 8 (* i 8)) bit-length)))
    (loop for start from 0 below (length padded) by 64 do
      (let ((w (make-array 64)))
        (dotimes (i 16)
          (setf (aref w i)
                (logior (ash (aref padded (+ start (* i 4))) 24)
                        (ash (aref padded (+ start (* i 4) 1)) 16)
                        (ash (aref padded (+ start (* i 4) 2)) 8)
                        (aref padded (+ start (* i 4) 3)))))
        (loop for i from 16 below 64 do
          (let* ((s0 (logxor (logior (ash (aref w (- i 15)) -7) (ash (aref w (- i 15)) 25))
                             (logior (ash (aref w (- i 15)) -18) (ash (aref w (- i 15)) 14))
                             (ash (aref w (- i 15)) -3)))
                 (s1 (logxor (logior (ash (aref w (- i 2)) -17) (ash (aref w (- i 2)) 15))
                             (logior (ash (aref w (- i 2)) -19) (ash (aref w (- i 2)) 13))
                             (ash (aref w (- i 2)) -10))))
            (setf (aref w i) (logand (+ (aref w (- i 16)) s0 (aref w (- i 7)) s1) #xffffffff))))
        (let ((a (aref h 0)) (b (aref h 1)) (c (aref h 2)) (d (aref h 3))
              (e (aref h 4)) (f (aref h 5)) (g (aref h 6)) (hh (aref h 7)))
          (dotimes (i 64)
            (let* ((s1 (logxor (logior (ash e -6) (ash e 26))
                               (logior (ash e -11) (ash e 21))
                               (logior (ash e -25) (ash e 7))))
                   (ch (logxor (logand e f) (logand (lognot e) g)))
                   (temp1 (logand (+ hh s1 ch (aref k i) (aref w i)) #xffffffff))
                   (s0 (logxor (logior (ash a -2) (ash a 30))
                               (logior (ash a -13) (ash a 19))
                               (logior (ash a -22) (ash a 10))))
                   (maj (logxor (logand a b) (logand a c) (logand b c)))
                   (temp2 (logand (+ s0 maj) #xffffffff)))
              (setf hh g g f f e e (logand (+ d temp1) #xffffffff)
                    d c c b b a a (logand (+ temp1 temp2) #xffffffff))))
          (setf (aref h 0) (logand (+ (aref h 0) a) #xffffffff)
                (aref h 1) (logand (+ (aref h 1) b) #xffffffff)
                (aref h 2) (logand (+ (aref h 2) c) #xffffffff)
                (aref h 3) (logand (+ (aref h 3) d) #xffffffff)
                (aref h 4) (logand (+ (aref h 4) e) #xffffffff)
                (aref h 5) (logand (+ (aref h 5) f) #xffffffff)
                (aref h 6) (logand (+ (aref h 6) g) #xffffffff)
                (aref h 7) (logand (+ (aref h 7) hh) #xffffffff)))))
    (string-downcase (format nil "~{~8,'0x~}" (coerce h 'list)))))

(defun ensure-compiled (octets)
  (let* ((key (sha256-hex octets))
         (cached (gethash key *compile-cache*)))
    (if cached
        (progn
          (setf *last-compile-cached-p* t
                *last-compile-seconds* 0d0)
          cached)
        (let* ((start (get-internal-real-time))
               (compiled (compile-module octets))
               (elapsed (/ (- (get-internal-real-time) start)
                           internal-time-units-per-second)))
          (setf *last-compile-cached-p* nil
                *last-compile-seconds* (float elapsed 1.0d0)
                (gethash key *compile-cache*) compiled)
          compiled))))
