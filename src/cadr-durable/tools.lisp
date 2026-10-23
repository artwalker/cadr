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
                     (push (line-too-long path number line) diagnostics))
                   (loop for character across line do (vector-push-extend character output))))
      (cond
        ((< next (1+ total))
         (push (if (= offset 1)
                   (format nil "Showing lines 1-~A of ~A. Use offset=~A to continue."
                           (length slice) total next)
                   (format nil "~A more lines in file. Use offset=~A to continue."
                           (- total (1- next)) next))
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
                  :diagnostics (list (format nil "Read image file [~A]." mime))))))
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

(defun unified-diff (path before after)
  (uiop:with-temporary-file (:stream old-stream :pathname old-path)
    (write-string before old-stream)
    (finish-output old-stream)
    (uiop:with-temporary-file (:stream new-stream :pathname new-path)
      (write-string after new-stream)
      (finish-output new-stream)
      (let* ((raw (uiop:run-program
                   (list "diff" "-u" "-U" "4" (namestring old-path) (namestring new-path))
                   :output :string :ignore-error-status t))
             (body (subseq raw (or (search (string #\Newline) raw) 0))))
        (when (plusp (length body))
          (setf body (subseq body (1+ (or (search (string #\Newline) body) 0)))))
        (format nil "--- ~A~%+++ ~A~%~A" path path body)))))

(defun execute-edit (env path edits)
  (require-env env)
  (let* ((absolute (resolve-tool-path env path))
         (before (uiop:read-file-string absolute))
         (after (apply-exact-edits before edits path)))
    (with-open-file (stream absolute :direction :output :if-exists :supersede
                                     :external-format :utf-8)
      (write-string after stream))
    (let ((patch (unified-diff path before after)))
      (make-tool-result
       :output (cadr-chord:json-array
                (cadr-chord:json-object
                 "type" "text"
                 "text" (format nil "Successfully replaced ~A block(s) in ~A."
                                (length edits) path)))
       :details (cadr-chord:json-object "diff" patch "patch" patch)))))

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
