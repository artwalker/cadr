(in-package #:cadr-cli)

(defstruct image-process-result
  bytes
  mime-type
  (original-width 0 :type (integer 0 *))
  (original-height 0 :type (integer 0 *))
  (width 0 :type (integer 0 *))
  (height 0 :type (integer 0 *))
  (resized-p nil :type boolean)
  (hints nil :type list))

(defun u32-be (bytes offset)
  (logior
   (ash (aref bytes offset) 24)
   (ash (aref bytes (1+ offset)) 16)
   (ash (aref bytes (+ offset 2)) 8)
   (aref bytes (+ offset 3))))

(defun jpeg-dimensions (bytes)
  (when (bytes-prefix-p bytes #(255 216 255))
    (loop with position = 2
          while (< (+ position 3)
                   (length bytes))
          do
          (unless (= (aref bytes position) #xff)
            (incf position)
            (loop-finish))
          (loop while
                (and (< position (length bytes))
                     (= (aref bytes position)
                        #xff))
                do (incf position))
          (when (>= position (length bytes))
            (return))
          (let ((marker (aref bytes position)))
            (incf position)
            (cond
              ((or (= marker #xd8)
                   (= marker #xd9))
               nil)
              ((= marker #xda)
               (return))
              (t
               (when (> (+ position 1)
                        (1- (length bytes)))
                 (return))
               (let ((size
                       (+
                        (ash
                         (aref bytes position)
                         8)
                        (aref bytes
                              (1+ position)))))
                 (when (or (< size 2)
                           (> (+ position size)
                              (length bytes)))
                   (return))
                 (when
                     (member marker
                             '(#xc0 #xc1 #xc2 #xc3
                               #xc5 #xc6 #xc7
                               #xc9 #xca #xcb
                               #xcd #xce #xcf))
                   (return-from
                       jpeg-dimensions
                     (values
                      (+
                       (ash
                        (aref bytes
                              (+ position 5))
                        8)
                       (aref bytes
                             (+ position 6)))
                      (+
                       (ash
                        (aref bytes
                              (+ position 3))
                        8)
                       (aref bytes
                             (+ position 4)))
                      t)))
                 (incf position size))))))))

(defun image-dimensions-from-bytes
    (bytes mime-type)
  (cond
    ((and
      (string= mime-type "image/png")
      (>= (length bytes) 24)
      (bytes-prefix-p
       bytes
       #(137 80 78 71 13 10 26 10)))
     (values
      (u32-be bytes 16)
      (u32-be bytes 20)
      t))
    ((string= mime-type "image/jpeg")
     (jpeg-dimensions bytes))
    ((and
      (string= mime-type "image/bmp")
      (>= (length bytes) 26))
     (values
      (abs (s32-le bytes 18))
      (abs (s32-le bytes 22))
      t))
    (t
     (values nil nil nil))))

(defun process-image-bytes
    (bytes mime-type
     &key (auto-resize-p t)
       (max-width 2000)
       (max-height 2000)
       (max-bytes (* 9 512 1024))
       (jpeg-quality 80)
       resize-function)
  (let ((effective-bytes bytes)
        (effective-mime mime-type)
        (hints nil))
    (when (string= mime-type "image/bmp")
      (setf effective-bytes
            (bmp-to-png bytes)
            effective-mime "image/png")
      (push
       "[Image converted from image/bmp to image/png.]"
       hints))
    (multiple-value-bind (rgba width height)
        (decode-image-rgba
         effective-bytes effective-mime)
      (unless rgba
        (return-from process-image-bytes nil))
      (let ((resize-required-p
              (and
               auto-resize-p
               (or (> width max-width)
                   (> height max-height)
                   (>=
                    (base64-encoded-byte-size
                     effective-bytes)
                    max-bytes)))))
        (cond
          ((not resize-required-p)
           (make-image-process-result
            :bytes (copy-seq effective-bytes)
            :mime-type effective-mime
            :original-width width
            :original-height height
            :width width
            :height height
            :resized-p nil
            :hints (nreverse hints)))
          (resize-function
           (funcall
            resize-function
            effective-bytes effective-mime
            width height
            max-width max-height max-bytes
            (nreverse hints)))
          (t
           (multiple-value-bind
                 (resized-bytes resized-mime
                  resized-width resized-height)
               (resize-image-rgba-to-limits
                rgba width height
                max-width max-height max-bytes
                :jpeg-quality jpeg-quality)
             (when resized-bytes
               (make-image-process-result
                :bytes resized-bytes
                :mime-type resized-mime
                :original-width width
                :original-height height
                :width resized-width
                :height resized-height
                :resized-p t
                :hints
                (nreverse hints))))))))))

(defun format-image-dimension-note (result)
  (when (image-process-result-resized-p result)
    (let ((scale
            (/ (image-process-result-original-width result)
               (max 1
                    (image-process-result-width result)))))
      (format
       nil
       "[Image: original ~Dx~D, displayed at ~Dx~D. Multiply coordinates by ~,2F to map to original image.]"
       (image-process-result-original-width result)
       (image-process-result-original-height result)
       (image-process-result-width result)
       (image-process-result-height result)
       (coerce scale 'double-float)))))

(defun process-image-data (bytes)
  (let ((mime-type (detect-image-mime-type bytes)))
    (when mime-type
      (if (member mime-type
                  '("image/gif" "image/webp")
                  :test #'string=)
          (values bytes mime-type nil nil)
          (let ((processed
                  (handler-case
                      (process-image-bytes bytes mime-type)
                    (condition () nil))))
            (if processed
                (let* ((dimension-note
                         (format-image-dimension-note
                          processed))
                       (hints
                         (append
                          (copy-list
                           (image-process-result-hints
                            processed))
                          (and dimension-note
                               (list dimension-note)))))
                  (values
                   (image-process-result-bytes processed)
                   (image-process-result-mime-type processed)
                   hints nil))
                (values
                 nil mime-type nil
                 (if (string= mime-type "image/bmp")
                     "[Image omitted: could not be converted to a supported inline image format.]"
                     "[Image omitted: could not be resized below the inline image size limit.]"))))))))

(defun normalize-tool-result-images
    (content &key (auto-resize-p t))
  ;; pi@4e58f324f utils/tool-result-images.ts — normalize image blocks
  ;; once as tool results enter history.  Processing failures keep the
  ;; original block (the tool produced it; a missing backend must not
  ;; delete tool output), and untouched images return the original
  ;; content array unchanged.
  (unless (find-if
           (lambda (block)
             (typep block 'cadr-ai:image-content))
           content)
    (return-from normalize-tool-result-images content))
  (let ((normalized nil)
        (changed nil))
    (dolist (block content)
      (if (not (typep block 'cadr-ai:image-content))
          (push block normalized)
          (let* ((bytes
                   (decode-base64-bytes
                    (cadr-ai:image-content-data block)))
                 (processed
                   (and bytes
                        (handler-case
                            (process-image-bytes
                             bytes
                             (cadr-ai:image-content-mime-type
                              block)
                             :auto-resize-p auto-resize-p)
                          (condition () nil)))))
            (if (or (null bytes) (null processed))
                (push block normalized)
                (let ((new-bytes
                        (image-process-result-bytes processed))
                      (new-mime
                        (image-process-result-mime-type processed))
                      (hints
                        (image-process-result-hints processed)))
                  (if (and (null hints)
                           (string= new-mime
                                    (cadr-ai:image-content-mime-type
                                     block))
                           (equalp new-bytes bytes))
                      (push block normalized)
                      (progn
                        (push
                         (cadr-ai:make-image-content
                          :data
                          (encode-base64-bytes new-bytes)
                          :mime-type new-mime)
                         normalized)
                        (when hints
                          (push
                           (cadr-ai:make-text-content
                            :text
                            (format nil "~{~A~^~%~}" hints))
                           normalized))
                        (setf changed t))))))))
    (if changed
        (nreverse normalized)
        content)))

(defun process-image-file (path)
  (process-image-data (read-binary-file path)))

