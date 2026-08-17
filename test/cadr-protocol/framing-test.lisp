(in-package #:cadr-protocol/tests)
(in-suite cadr-protocol-suite)

(defun concatenate-octets (&rest chunks)
  (apply #'concatenate '(vector (unsigned-byte 8)) chunks))

(test frame-prefixes-payload-with-big-endian-length
  (is (bytes= (octets 0 0 0 3 #xaa #xbb #xcc)
              (cadr-protocol:encode-frame
               (octets #xaa #xbb #xcc))))
  (is (bytes= (octets 0 0 0 0)
              (cadr-protocol:encode-frame (octets)))))

(test frame-validates-one-complete-bounded-frame
  (finishes
    (cadr-protocol:assert-complete-frame
     (octets 0 0 0 2 1 2) :max-frame-length 2))
  (signals-message cadr-protocol:frame-error "complete"
    (cadr-protocol:assert-complete-frame
     (octets 0 0 0 2 1)))
  (signals-message cadr-protocol:frame-error "exactly"
    (cadr-protocol:assert-complete-frame
     (octets 0 0 0 1 1 2)))
  (signals-message cadr-protocol:frame-error "limit"
    (cadr-protocol:assert-complete-frame
     (octets 0 0 0 3 1 2 3) :max-frame-length 2)))

(test frame-decodes-fragmented-coalesced-and-empty-in-order
  (let* ((wire
           (concatenate-octets
            (cadr-protocol:encode-frame (octets 1 2 3))
            (cadr-protocol:encode-frame (octets))
            (cadr-protocol:encode-frame (octets 4))))
         (decoder (cadr-protocol:make-frame-decoder))
         (frames nil))
    (loop for byte across wire
          do (setf frames
                   (nconc frames
                          (cadr-protocol:frame-decoder-push
                           decoder (octets byte)))))
    (cadr-protocol:frame-decoder-end decoder)
    (is (= 3 (length frames)))
    (is (bytes= (octets 1 2 3) (first frames)))
    (is (bytes= (octets) (second frames)))
    (is (bytes= (octets 4) (third frames)))
    (let ((coalesced (cadr-protocol:make-frame-decoder)))
      (let ((coalesced-frames
              (cadr-protocol:frame-decoder-push
               coalesced wire)))
        (is (= 3 (length coalesced-frames)))
        (is (every #'bytes= frames coalesced-frames)))
      (cadr-protocol:frame-decoder-end coalesced))))

(test frame-assembles-payload-spanning-internal-blocks
  (let* ((payload
           (make-array 70000
                       :element-type '(unsigned-byte 8)))
         (wire nil)
         (decoder (cadr-protocol:make-frame-decoder))
         (frames nil))
    (loop for index below (length payload)
          do (setf (aref payload index) (mod index 251)))
    (setf wire (cadr-protocol:encode-frame payload)
          frames
          (nconc
           (cadr-protocol:frame-decoder-push
            decoder (subseq wire 0 101))
           (cadr-protocol:frame-decoder-push
            decoder (subseq wire 101 65541))
           (cadr-protocol:frame-decoder-push
            decoder (subseq wire 65541))))
    (cadr-protocol:frame-decoder-end decoder)
    (is (= 1 (length frames)))
    (is (bytes= payload (first frames)))))

(test frame-handles-every-split-point
  (let ((wire
          (cadr-protocol:encode-frame
           (octets 10 20 30 40))))
    (loop for split from 0 to (length wire)
          do (let* ((decoder
                      (cadr-protocol:make-frame-decoder))
                    (frames
                      (nconc
                       (cadr-protocol:frame-decoder-push
                        decoder (subseq wire 0 split))
                       (cadr-protocol:frame-decoder-push
                        decoder (subseq wire split)))))
               (cadr-protocol:frame-decoder-end decoder)
               (is (= 1 (length frames)))
               (is (bytes= (octets 10 20 30 40)
                           (first frames)))))))

(test frame-copies-payload-instead-of-aliasing-input
  (let* ((chunk
           (cadr-protocol:encode-frame (octets 1 2 3)))
         (decoder (cadr-protocol:make-frame-decoder))
         (frames
           (cadr-protocol:frame-decoder-push decoder chunk)))
    (fill chunk 9)
    (is (bytes= (octets 1 2 3) (first frames)))))

(test frame-accepts-empty-chunks-and-clean-empty-stream
  (let ((decoder (cadr-protocol:make-frame-decoder)))
    (is (null
         (cadr-protocol:frame-decoder-push
          decoder (octets))))
    (finishes
      (cadr-protocol:frame-decoder-end decoder))))

(test frame-rejects-truncated-stream-at-end
  (dolist (wire
           (list (octets 0 0 0)
                 (octets 0 0 0 2 1)))
    (let ((decoder (cadr-protocol:make-frame-decoder)))
      (is (null
           (cadr-protocol:frame-decoder-push decoder wire)))
      (signals cadr-protocol:frame-error
        (cadr-protocol:frame-decoder-end decoder)))))

(test frame-rejects-oversized-length-as-soon-as-header-completes
  (let ((decoder
          (cadr-protocol:make-frame-decoder
           :max-frame-length 3)))
    (signals-message cadr-protocol:frame-error "limit"
      (cadr-protocol:frame-decoder-push
       decoder (octets 0 0 0 4)))
    (signals-message cadr-protocol:frame-error "failed"
      (cadr-protocol:frame-decoder-push
       decoder (octets 1)))))

(test frame-accepts-configured-maximum
  (let ((decoder
          (cadr-protocol:make-frame-decoder
           :max-frame-length 3)))
    (let ((frames
            (cadr-protocol:frame-decoder-push
             decoder
             (cadr-protocol:encode-frame (octets 1 2 3)))))
      (is (= 1 (length frames)))
      (is (bytes= (octets 1 2 3) (first frames))))
    (cadr-protocol:frame-decoder-end decoder)))

(test frame-cannot-be-pushed-or-ended-after-end
  (let ((decoder (cadr-protocol:make-frame-decoder)))
    (cadr-protocol:frame-decoder-end decoder)
    (signals-message cadr-protocol:frame-error "ended"
      (cadr-protocol:frame-decoder-push decoder (octets)))
    (signals-message cadr-protocol:frame-error "ended"
      (cadr-protocol:frame-decoder-end decoder))))

(test frame-decoder-consume-advances-offset-not-splice
  ;; Red on the old replace/fill-pointer splice.
  (let* ((wire
           (cadr-protocol:encode-frame (octets 1 2 3)))
         (decoder (cadr-protocol:make-frame-decoder)))
    (cadr-protocol:frame-decoder-push decoder wire)
    (is (plusp (cadr-protocol::frame-decoder-offset decoder)))
    (is (>= (length
             (cadr-protocol::frame-decoder-pending decoder))
            (length wire)))))

(test frame-rejects-invalid-maximum-lengths
  (dolist (maximum
           (list -1
                 1.5d0
                 (quiet-double-nan)
                 (* cadr-protocol:+default-max-frame-length+ 1000)))
    (signals error
      (cadr-protocol:make-frame-decoder
       :max-frame-length maximum))))
