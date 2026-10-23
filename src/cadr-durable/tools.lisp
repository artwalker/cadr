(in-package #:cadr-durable)

(defstruct (directory-env (:constructor %make-directory-env)) root)
(defstruct tool-result output diagnostics error-p details structured)

(defun make-directory-env (root)
  (%make-directory-env :root (uiop:ensure-directory-pathname root)))

(defun require-env (env)
  (unless env (error "No execution environment is configured"))
  env)

(defun resolve-tool-path (env path)
  (if (uiop:absolute-pathname-p path)
      path
      (merge-pathnames path (directory-env-root (require-env env)))))

(defun format-size (bytes)
  (if (< bytes 1024)
      (format nil "~AB" bytes)
      (format nil "~,1FKB" (/ bytes 1024d0))))

(defun text-lines (text)
  (let ((lines (uiop:split-string text :separator '(#\Newline))))
    (when (and lines (string= (car (last lines)) ""))
      (setf lines (butlast lines)))
    lines))

(defun utf8-prefix (text byte-limit)
  (let ((count 0)
        (end 0))
    (loop for character across text
          for octets = (length (sb-ext:string-to-octets (string character)
                                                        :external-format :utf-8))
          while (<= (+ count octets) byte-limit)
          do (incf count octets)
             (incf end))
    (values (subseq text 0 end) count)))

(defun line-too-long (path line-number line)
  (let* ((bytes (length (sb-ext:string-to-octets line :external-format :utf-8)))
         (shown (min bytes +default-max-bytes+)))
    (format nil "Line ~A is ~A, exceeds the ~A limit; showing its first ~A. Use bash: sed -n '~Ap' ~A | tail -c +~A"
            line-number (format-size bytes) (format-size +default-max-bytes+)
            (format-size shown) line-number (file-namestring path) (1+ shown))))

(defun tool-diagnostic (severity message &key code)
  (let ((diagnostic (cadr-chord:json-object "severity" severity "message" message)))
    (when code
      (cadr-chord:json-put diagnostic "code" code))
    diagnostic))

(defun read-text-page (path text &key (offset 1) limit)
  (let* ((lines (text-lines text))
         (total (length lines))
         (limit (or limit +default-max-lines+))
         (start (1- offset)))
    (when (> offset total)
      (error "Offset ~A is beyond end of file (~A lines total)" offset total))
    (let* ((slice (subseq lines start (min total (+ start limit))))
           (next (+ offset (length slice)))
           (diagnostics nil)
           (truncated nil)
           (output (make-array 0 :element-type 'character :fill-pointer 0 :adjustable t)))
      (loop for line in slice
            for number from offset
            for bytes = (length (sb-ext:string-to-octets line :external-format :utf-8))
            do (when (plusp (length output)) (vector-push-extend #\Newline output))
               (if (> bytes +default-max-bytes+)
                   (progn
                     (multiple-value-bind (prefix) (utf8-prefix line +default-max-bytes+)
                       (loop for character across prefix do (vector-push-extend character output)))
                     (push (tool-diagnostic
                            "warn" (line-too-long path number line)
                            :code "truncated")
                           diagnostics))
                   (loop for character across line do (vector-push-extend character output))))
      (cond
        ((< next (1+ total))
         (push (if (= offset 1)
                   (tool-diagnostic
                    "info"
                    (format nil "Showing lines 1-~A of ~A. Use offset=~A to continue."
                            (length slice) total next)
                    :code "truncated")
                   (tool-diagnostic
                    "info"
                    (format nil "~A more lines in file. Use offset=~A to continue."
                            (- total (1- next)) next)))
               diagnostics)
         (setf truncated (cadr-chord:json-object
                          "truncated" t "truncatedBy" "lines"
                          "totalLines" total "outputLines" (length slice)))))
      (values (coerce output 'string) (nreverse diagnostics) truncated total))))

(defparameter *base64-digits*
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defun base64-encode (bytes)
  (with-output-to-string (output)
    (loop for index from 0 below (length bytes) by 3
          for a = (aref bytes index)
          for b = (if (< (1+ index) (length bytes)) (aref bytes (1+ index)) nil)
          for c = (if (< (+ index 2) (length bytes)) (aref bytes (+ index 2)) nil)
          do (write-char (char *base64-digits* (ash a -2)) output)
             (write-char (char *base64-digits*
                               (logior (ash (logand a 3) 4)
                                       (if b (ash b -4) 0)))
                         output)
             (write-char (if b (char *base64-digits*
                                     (logior (ash (logand b 15) 2)
                                             (if c (ash c -6) 0)))
                             #\=)
                         output)
             (write-char (if c (char *base64-digits* (logand c 63)) #\=) output))))

(defun read-u32-be (bytes offset)
  (logior (ash (aref bytes offset) 24) (ash (aref bytes (+ offset 1)) 16)
          (ash (aref bytes (+ offset 2)) 8) (aref bytes (+ offset 3))))

(defun read-u16-le (bytes offset)
  (logior (aref bytes offset) (ash (aref bytes (1+ offset)) 8)))

(defun image-info (bytes)
  (cond
    ((and (>= (length bytes) 24)
          (= (aref bytes 0) #x89) (= (aref bytes 1) #x50) (= (aref bytes 2) #x4E)
          (= (aref bytes 3) #x47))
     (list "image/png" (read-u32-be bytes 16) (read-u32-be bytes 20)))
    ((and (>= (length bytes) 10)
          (or (and (= (aref bytes 0) (char-code #\G)) (= (aref bytes 1) (char-code #\I))
                   (= (aref bytes 2) (char-code #\F)))
              nil))
     (list "image/gif" (read-u16-le bytes 6) (read-u16-le bytes 8)))
    ((and (>= (length bytes) 12)
          (= (aref bytes 0) (char-code #\R)) (= (aref bytes 1) (char-code #\I))
          (= (aref bytes 8) (char-code #\W)) (= (aref bytes 9) (char-code #\E))
          (= (aref bytes 10) (char-code #\B)) (= (aref bytes 11) (char-code #\P)))
     (list "image/webp" 1 1))
    ((and (>= (length bytes) 3)
          (= (aref bytes 0) #xFF) (= (aref bytes 1) #xD8) (= (aref bytes 2) #xFF)
          (or (< (length bytes) 4) (/= (aref bytes 3) #xF7)))
     (list "image/jpeg" 1 1))
    ((and (>= (length bytes) 2) (= (aref bytes 0) (char-code #\B)) (= (aref bytes 1) (char-code #\M)))
     (list "image/bmp" 1 1))
    (t nil)))

(defun file-bytes (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      bytes)))

(defun execute-read (env path &key (offset 1) limit)
  (require-env env)
  (let* ((absolute (resolve-tool-path env path))
         (before (file-write-date absolute))
         (bytes (file-bytes absolute))
         (after (file-write-date absolute)))
    (unless (eql before after)
      (error "~A changed while it was read" path))
    (let ((image (image-info bytes)))
      (if image
          (let ((mime (first image))
                (width (second image))
                (height (third image))
                (encoded (base64-encode bytes)))
            (cond
              ((not (member mime '("image/png" "image/jpeg" "image/gif" "image/webp")
                            :test #'string=))
               (error "~A is an image (~A) that needs converting, and no image processor is configured"
                      path mime))
              ((or (> width 2000) (> height 2000))
               (error "~A is an image (~A) of ~Dx~D, larger than 2000x2000, and no image processor is configured to shrink it"
                      path mime width height))
              ((> (length encoded) (* 4.5 1024 1024))
               (error "~A is an image (~A) of ~A, too large to send, and no image processor is configured to shrink it"
                      path mime (format-size (length bytes))))
              (t (make-tool-result
                  :output (cadr-chord:json-array
                           (cadr-chord:json-object "type" "image" "data" encoded
                                                   "mimeType" mime))
                  :diagnostics (list (tool-diagnostic
                                      "info"
                                      (format nil "Read image file [~A]." mime)
                                      :code "image"))))))
          (let ((text (sb-ext:octets-to-string bytes :external-format :utf-8)))
            (multiple-value-bind (page diagnostics truncated) 
                (read-text-page path text :offset offset :limit limit)
              (make-tool-result :output (cadr-chord:json-array
                                         (cadr-chord:json-object "type" "text" "text" page))
                                :diagnostics diagnostics
                                :details truncated)))))))

(defun execute-write (env path text)
  (require-env env)
  (let ((absolute (resolve-tool-path env path)))
    (ensure-directories-exist absolute)
    (with-open-file (stream absolute :direction :output :if-exists :supersede
                                     :if-does-not-exist :create
                                     :external-format :utf-8)
      (write-string text stream))
    (make-tool-result :output (cadr-chord:json-array
                               (cadr-chord:json-object
                                "type" "text"
                                "text" (format nil "Successfully wrote to ~A" path))))))

(defun count-occurrences (text old)
  (let ((count 0)
        (start 0))
    (loop for found = (search old text :start2 start)
          while found
          do (incf count)
             (setf start (+ found (length old))))
    count))

(defun apply-exact-edits (text edits path)
  (when (null edits) (error "Edit tool input is invalid. edits must contain at least one replacement."))
  (let ((total (length edits))
        (matches nil))
    (loop for edit in edits
          for index from 0
          for old = (gethash "oldText" edit)
          for new = (gethash "newText" edit)
          do (when (zerop (length old))
               (if (= total 1)
                   (error "oldText must not be empty in ~A." path)
                   (error "edits[~A].oldText must not be empty in ~A." index path)))
             (let ((found (search old text))
                   (occurrences (count-occurrences text old)))
               (unless found
                 (if (= total 1)
                     (error "Could not find the exact text in ~A. The old text must match exactly including all whitespace and newlines." path)
                     (error "Could not find edits[~A] in ~A. The oldText must match exactly including all whitespace and newlines." index path)))
               (when (> occurrences 1)
                 (if (= total 1)
                     (error "Found ~A occurrences of the text in ~A. The text must be unique. Please provide more context to make it unique."
                            occurrences path)
                     (error "Found ~A occurrences of edits[~A] in ~A. Each oldText must be unique. Please provide more context to make it unique."
                            occurrences index path)))
               (push (list index found (length old) new) matches)))
    (setf matches (sort matches #'< :key #'second))
    (loop for tail on matches
          for previous = (car tail)
          for current = (cadr tail)
          when (and current (> (+ (second previous) (third previous)) (second current)))
            do (error "edits[~A] and edits[~A] overlap in ~A. Merge them into one edit or target disjoint regions."
                      (first previous) (first current) path))
    (let ((new-text text))
      (dolist (match (reverse matches))
        (setf new-text (concatenate 'string
                                    (subseq new-text 0 (second match))
                                    (fourth match)
                                    (subseq new-text (+ (second match) (third match))))))
      (when (string= new-text text)
        (error (if (= total 1)
                   "No changes made to ~A. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
                   "No changes made to ~A. The replacements produced identical content.")
               path))
      new-text)))

(defstruct diff-component count added removed previous value)

(defun diff-line-parts (value)
  (let ((parts nil)
        (start 0)
        (length (length value)))
    (loop for index from 0 below length
          do (cond
               ((and (char= (char value index) #\Return)
                     (< (1+ index) length)
                     (char= (char value (1+ index)) #\Newline))
                (push (subseq value start index) parts)
                (push (subseq value index (+ index 2)) parts)
                (setf start (+ index 2))
                (incf index))
               ((char= (char value index) #\Newline)
                (push (subseq value start index) parts)
                (push (string #\Newline) parts)
                (setf start (1+ index)))))
    (push (subseq value start) parts)
    (nreverse parts)))

(defun diff-line-tokens (value)
  (let ((parts (diff-line-parts value))
        (tokens nil))
    (when (and parts (string= (car (last parts)) ""))
      (setf parts (butlast parts)))
    (loop for part in parts
          for index from 0
          do (if (oddp index)
                 (setf (car tokens) (concatenate 'string (car tokens) part))
                 (push part tokens)))
    (nreverse (remove "" tokens :test #'string=))))

(defun diff-join (tokens start count)
  (with-output-to-string (output)
    (loop for index from start below (+ start count)
          do (write-string (aref tokens index) output))))

(defun diff-build-values (last new-tokens old-tokens)
  (let ((components nil)
        (new-pos 0)
        (old-pos 0))
    (loop for component = last then (diff-component-previous component)
          while component
          do (push component components))
    (dolist (component components)
      (cond
        ((diff-component-removed component)
         (setf (diff-component-value component)
               (diff-join old-tokens old-pos (diff-component-count component)))
         (incf old-pos (diff-component-count component)))
        (t
         (setf (diff-component-value component)
               (diff-join new-tokens new-pos (diff-component-count component)))
         (incf new-pos (diff-component-count component))
         (unless (diff-component-added component)
           (incf old-pos (diff-component-count component))))))
    components))

(defun diff-extract-common (path new-tokens old-tokens diagonal)
  (let ((old-pos (getf path :old-pos))
        (new-pos (- (getf path :old-pos) diagonal))
        (common 0))
    (loop while (and (< (1+ new-pos) (length new-tokens))
                     (< (1+ old-pos) (length old-tokens))
                     (string= (aref old-tokens (1+ old-pos))
                              (aref new-tokens (1+ new-pos))))
          do (incf new-pos)
             (incf old-pos)
             (incf common))
    (when (plusp common)
      (setf (getf path :last)
            (make-diff-component :count common
                                 :previous (getf path :last)
                                 :added nil :removed nil)))
    (setf (getf path :old-pos) old-pos)
    new-pos))

(defun diff-add-to-path (path added removed old-pos-inc)
  (let ((last (getf path :last)))
    (if (and last
             (eq (diff-component-added last) added)
             (eq (diff-component-removed last) removed))
        (list :old-pos (+ (getf path :old-pos) old-pos-inc)
              :last (make-diff-component
                     :count (1+ (diff-component-count last))
                     :added added :removed removed
                     :previous (diff-component-previous last)))
        (list :old-pos (+ (getf path :old-pos) old-pos-inc)
              :last (make-diff-component
                     :count 1 :added added :removed removed :previous last)))))

(defun diff-lines (old new)
  (let* ((old-tokens (coerce (diff-line-tokens old) 'vector))
         (new-tokens (coerce (diff-line-tokens new) 'vector))
         (old-len (length old-tokens))
         (new-len (length new-tokens))
         (best (make-hash-table :test #'eql))
         (min-diagonal most-negative-fixnum)
         (max-diagonal most-positive-fixnum))
    (setf (gethash 0 best) (list :old-pos -1 :last nil))
    (let ((new-pos (diff-extract-common (gethash 0 best) new-tokens old-tokens 0)))
      (when (and (>= (1+ (getf (gethash 0 best) :old-pos)) old-len)
                 (>= (1+ new-pos) new-len))
        (return-from diff-lines
          (diff-build-values (getf (gethash 0 best) :last) new-tokens old-tokens))))
    (loop for edit-length from 1 to (+ old-len new-len)
          do (loop for diagonal from (max min-diagonal (- edit-length))
                     to (min max-diagonal edit-length) by 2
                   for remove-path = (gethash (1- diagonal) best)
                   for add-path = (gethash (1+ diagonal) best)
                   do (when remove-path
                        (remhash (1- diagonal) best))
                      (let ((can-add nil)
                            (can-remove (and remove-path
                                             (< (1+ (getf remove-path :old-pos)) old-len))))
                        (when add-path
                          (let ((add-new (- (getf add-path :old-pos) diagonal)))
                            (setf can-add (and (<= 0 add-new) (< add-new new-len)))))
                        (cond
                          ((not (or can-add can-remove))
                           (remhash diagonal best))
                          (t
                           (let* ((base (if (or (not can-remove)
                                                (and can-add
                                                     (< (getf remove-path :old-pos)
                                                        (getf add-path :old-pos))))
                                            (diff-add-to-path add-path t nil 0)
                                            (diff-add-to-path remove-path nil t 1)))
                                  (reached (diff-extract-common base new-tokens old-tokens diagonal)))
                             (cond
                               ((and (>= (1+ (getf base :old-pos)) old-len)
                                     (>= (1+ reached) new-len))
                                (return-from diff-lines
                                  (diff-build-values (getf base :last)
                                                     new-tokens old-tokens)))
                               (t
                                (setf (gethash diagonal best) base)
                                (when (>= (1+ (getf base :old-pos)) old-len)
                                  (setf max-diagonal (min max-diagonal (1- diagonal))))
                                (when (>= (1+ reached) new-len)
                                  (setf min-diagonal (max min-diagonal (1+ diagonal))))))))))))))

(defun pad-line-number (number width)
  (format nil "~vD" width number))

(defun diff-raw-lines (value)
  (let ((raw (uiop:split-string value :separator '(#\Newline))))
    (when (and raw (string= (car (last raw)) ""))
      (setf raw (butlast raw)))
    raw))

(defun generate-diff-string (old new &key (context-lines 4))
  (let* ((parts (diff-lines old new))
         (old-lines (uiop:split-string old :separator '(#\Newline)))
         (new-lines (uiop:split-string new :separator '(#\Newline)))
         (width (length (write-to-string (max (length old-lines) (length new-lines)))))
         (output nil)
         (old-line 1)
         (new-line 1)
         (last-change nil)
         (first-changed nil))
    (loop for part in parts
          for index from 0
          for raw = (diff-raw-lines (diff-component-value part))
          do (if (or (diff-component-added part) (diff-component-removed part))
                 (progn
                   (unless first-changed
                     (setf first-changed new-line))
                   (dolist (line raw)
                     (if (diff-component-added part)
                         (progn
                           (push (format nil "+~A ~A" (pad-line-number new-line width) line)
                                 output)
                           (incf new-line))
                         (progn
                           (push (format nil "-~A ~A" (pad-line-number old-line width) line)
                                 output)
                           (incf old-line))))
                   (setf last-change t))
                 (let* ((next (nth (1+ index) parts))
                        (trailing (and next
                                       (or (diff-component-added next)
                                           (diff-component-removed next))))
                        (leading last-change))
                   (cond
                     ((and leading trailing)
                      (if (<= (length raw) (* context-lines 2))
                          (dolist (line raw)
                            (push (format nil " ~A ~A" (pad-line-number old-line width) line)
                                  output)
                            (incf old-line)
                            (incf new-line))
                          (let* ((leading-lines (subseq raw 0 context-lines))
                                 (trailing-lines (subseq raw (- (length raw) context-lines)))
                                 (skipped (- (length raw) (length leading-lines)
                                             (length trailing-lines))))
                            (dolist (line leading-lines)
                              (push (format nil " ~A ~A" (pad-line-number old-line width) line)
                                    output)
                              (incf old-line)
                              (incf new-line))
                            (push (format nil " ~A ..." (make-string width :initial-element #\Space))
                                  output)
                            (incf old-line skipped)
                            (incf new-line skipped)
                            (dolist (line trailing-lines)
                              (push (format nil " ~A ~A" (pad-line-number old-line width) line)
                                    output)
                              (incf old-line)
                              (incf new-line)))))
                     (leading
                      (let* ((shown (subseq raw 0 (min context-lines (length raw))))
                             (skipped (- (length raw) (length shown))))
                        (dolist (line shown)
                          (push (format nil " ~A ~A" (pad-line-number old-line width) line)
                                output)
                          (incf old-line)
                          (incf new-line))
                        (when (plusp skipped)
                          (push (format nil " ~A ..." (make-string width :initial-element #\Space))
                                output)
                          (incf old-line skipped)
                          (incf new-line skipped))))
                     (trailing
                      (let ((skipped (max 0 (- (length raw) context-lines))))
                        (when (plusp skipped)
                          (push (format nil " ~A ..." (make-string width :initial-element #\Space))
                                output)
                          (incf old-line skipped)
                          (incf new-line skipped))
                        (dolist (line (subseq raw skipped))
                          (push (format nil " ~A ~A" (pad-line-number old-line width) line)
                                output)
                          (incf old-line)
                          (incf new-line))))
                     (t
                      (incf old-line (length raw))
                      (incf new-line (length raw))))
                   (setf last-change nil))))
    (values (format nil "~{~A~^~%~}" (nreverse output)) first-changed)))

(defun patch-split-lines (text)
  (let* ((trailing (and (plusp (length text)) (char= (char text (1- (length text))) #\Newline)))
         (lines (mapcar (lambda (line) (concatenate 'string line (string #\Newline)))
                        (uiop:split-string text :separator '(#\Newline)))))
    (if trailing
        (butlast lines)
        (append (butlast lines)
                (list (subseq (car (last lines)) 0 (max 0 (1- (length (car (last lines)))))))))))

(defun generate-unified-patch (path old new &key (context-lines 4))
  (let* ((parts (append (diff-lines old new) (list nil)))
         (hunks nil)
         (old-range 0)
         (new-range 0)
         (current nil)
         (old-line 1)
         (new-line 1))
    (loop for part in parts
          for index from 0
          for lines = (if part
                          (patch-split-lines (or (diff-component-value part) ""))
                          nil)
          do (cond
               ((and part
                     (or (diff-component-added part) (diff-component-removed part)))
                (unless (plusp old-range)
                  (let ((previous (when (plusp index) (nth (1- index) parts))))
                    (setf old-range old-line
                          new-range new-line
                          current nil)
                    (when previous
                      (let* ((previous-lines (patch-split-lines
                                              (diff-component-value previous)))
                             (prefix (subseq previous-lines
                                             (max 0 (- (length previous-lines)
                                                       context-lines)))))
                        (dolist (line prefix)
                          (push (concatenate 'string " " line) current))
                        (decf old-range (length prefix))
                        (decf new-range (length prefix))))))
                (dolist (line lines)
                  (push (concatenate 'string
                                     (if (diff-component-added part) "+" "-")
                                     line)
                        current))
                (if (diff-component-added part)
                    (incf new-line (length lines))
                    (incf old-line (length lines))))
               (t
                (when (plusp old-range)
                  (if (and (<= (length lines) (* context-lines 2))
                           (< index (- (length parts) 2)))
                      (dolist (line lines)
                        (push (concatenate 'string " " line) current))
                      (let ((size (min (length lines) context-lines)))
                        (dolist (line (subseq lines 0 size))
                          (push (concatenate 'string " " line) current))
                        (push (list :hunk old-range
                                    (+ (- old-line old-range) size)
                                    new-range
                                    (+ (- new-line new-range) size)
                                    (nreverse current))
                              hunks)
                        (setf old-range 0 new-range 0 current nil))))
                (incf old-line (length lines))
                (incf new-line (length lines)))))
    (with-output-to-string (output)
      (format output "--- ~A~%+++ ~A~%" path path)
      (dolist (hunk (nreverse hunks))
        (destructuring-bind (old-start old-count new-start new-count lines) (rest hunk)
          (when (zerop old-count) (decf old-start))
          (when (zerop new-count) (decf new-start))
          (format output "@@ -~A,~A +~A,~A @@~%" old-start old-count new-start new-count)
          (dolist (line lines)
            (if (and (plusp (length line)) (char= (char line (1- (length line))) #\Newline))
                (write-string (subseq line 0 (1- (length line))) output)
                (progn
                  (write-string line output)
                  (terpri output)
                  (write-string "\\ No newline at end of file" output)))
            (terpri output)))))))

(defun execute-edit (env path edits)
  (require-env env)
  (let* ((absolute (resolve-tool-path env path))
         (before (uiop:read-file-string absolute))
         (after (apply-exact-edits before edits path)))
    (with-open-file (stream absolute :direction :output :if-exists :supersede
                                     :external-format :utf-8)
      (write-string after stream))
    (multiple-value-bind (diff first-changed) (generate-diff-string before after)
      (let ((details (cadr-chord:json-object
                      "diff" diff
                      "patch" (generate-unified-patch path before after))))
        (when first-changed
          (cadr-chord:json-put details "firstChangedLine" first-changed))
        (make-tool-result
         :output (cadr-chord:json-array
                  (cadr-chord:json-object
                   "type" "text"
                   "text" (format nil "Successfully replaced ~A block(s) in ~A."
                                  (length edits) path)))
         :details details)))))

(defun edit-object (old new)
  (cadr-chord:json-object "oldText" old "newText" new))

(defun prepare-edit-arguments (input)
  (let ((copy (cadr-chord:copy-json input)))
    (when (hash-table-p copy)
      (let ((edits (gethash "edits" copy)))
        (when (stringp edits)
          (handler-case
                (let ((parsed (cadr-chord::parse-json edits)))
                (cond
                  ((and (vectorp parsed) (not (stringp parsed)))
                   (setf (gethash "edits" copy) parsed))
                  ((hash-table-p parsed)
                   (setf (gethash "edits" copy) (cadr-chord:json-array parsed)))))
            (error () nil)))
        (when (hash-table-p (gethash "edits" copy))
          (setf (gethash "edits" copy) (cadr-chord:json-array (gethash "edits" copy)))))
      (when (and (stringp (gethash "oldText" copy)) (stringp (gethash "newText" copy)))
        (let ((edits (gethash "edits" copy)))
          (unless (and (vectorp edits) (not (stringp edits)))
            (setf edits (cadr-chord:json-array)))
          (vector-push-extend (edit-object (gethash "oldText" copy) (gethash "newText" copy))
                              edits)
          (remhash "oldText" copy)
          (remhash "newText" copy)
          (setf (gethash "edits" copy) edits))))
    copy))

(defparameter +max-timeout-seconds+ (/ 2147483647 1000))

(defun run-bash (directory command timeout)
  (flet ((run ()
           (multiple-value-bind (stdout stderr code)
               (uiop:run-program (list "bash" "-lc" command)
                                 :directory directory
                                 :output :string :error-output :string
                                 :ignore-error-status t)
             (values (concatenate 'string (or stdout "") (or stderr "")) code))))
    (if timeout
        (handler-case (sb-ext:with-timeout timeout (run))
          (sb-ext:timeout ()
            (error "Command timed out after ~A seconds" timeout)))
        (run))))

(defun execute-bash (env command &key timeout)
  (require-env env)
  (when (and timeout
             (or (not (realp timeout))
                 (not (plusp timeout))
                 (and (floatp timeout)
                      (or (sb-ext:float-nan-p timeout)
                          (sb-ext:float-infinity-p timeout)))))
    (error "Invalid timeout: must be a finite number of seconds"))
  (when (and timeout (> timeout +max-timeout-seconds+))
    (error "Invalid timeout: maximum is ~,3F seconds"
           (float +max-timeout-seconds+ 1.0d0)))
  (multiple-value-bind (output code) (run-bash (directory-env-root env) command timeout)
    (if (zerop code)
        (make-tool-result :output (cadr-chord:json-array
                                   (cadr-chord:json-object "type" "text" "text" output))
                          :structured (cadr-chord:json-object "output" output "exitCode" 0))
        (make-tool-result
         :error-p t
         :output (cadr-chord:json-array (cadr-chord:json-object "type" "text" "text" output))
         :diagnostics (list (cadr-chord:json-object
                             "severity" "error" "code" "exit_code"
                             "message" (format nil "Command exited with code ~A" code)))
         :structured (cadr-chord:json-object "output" output "exitCode" code)))))

(defun create-coding-tools ()
  (list (define-tool "read" #'execute-read)
        (define-tool "write" #'execute-write)
        (define-tool "edit" #'execute-edit)
        (define-tool "bash" #'execute-bash)))
