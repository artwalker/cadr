(in-package #:cadr-ai)

(defconstant +model-data-schema-version+ 3)
(defparameter +model-data-manifest-file+ ".manifest.json")

(defparameter +models-dev-thinking-levels+
  '(:minimal :low :medium :high :xhigh :max))

(defun model-data-json-path-p (path)
  (and (string-equal "json" (pathname-type path))
       (not (string= +model-data-manifest-file+
                     (file-namestring path)))))

(defun model-data-sorted-keys (object)
  (sort
   (loop for key being the hash-keys of object collect key)
   #'string<))

(defun walk-model-data-groups (groups on-invalid-group on-model)
  (dolist (api (model-data-sorted-keys groups))
    (let ((group (json-get groups api)))
      (if (not (hash-table-p group))
          (funcall on-invalid-group api)
          (dolist (model-id (model-data-sorted-keys group))
            (funcall on-model api group model-id))))))

(defun read-model-data-provider-ids (directory)
  (let ((ids
          (loop for path in (uiop:directory-files directory)
                when (model-data-json-path-p path)
                  collect (pathname-name path))))
    (unless ids
      (error "No generated provider data found in ~A" directory))
    (sort ids #'string<)))

(defun read-model-data-provider-structure (path provider-id)
  (let ((groups
          (parse-json
           (uiop:read-file-string path :external-format :utf-8)))
        (models (make-hash-table :test #'equal)))
    (unless (hash-table-p groups)
      (error "~A.json must contain a JSON object" provider-id))
    (walk-model-data-groups
     groups
     (lambda (api)
       (error "~A API group ~S must be an object" path api))
     (lambda (api group model-id)
       (declare (ignore group))
       (when (nth-value 1 (gethash model-id models))
         (error "~A contains model ~A in more than one API group"
                path model-id))
       (setf (gethash model-id models) api)))
    (when (zerop (hash-table-count models))
      (error "~A contains no generated model data" path))
    models))

(defun read-model-data-structure (directory)
  (let ((structure (make-hash-table :test #'equal)))
    (dolist (provider-id (read-model-data-provider-ids directory))
      (setf
       (gethash provider-id structure)
       (read-model-data-provider-structure
        (merge-pathnames (format nil "~A.json" provider-id) directory)
        provider-id)))
    structure))

(defun model-data-structure-hash (structure)
  (octets-hex
   (sha256-bytes
    (utf8-octets (stringify-json structure)))))

(defun model-data-file-hash (path)
  (octets-hex
   (sha256-bytes
    (utf8-octets
     (uiop:read-file-string path :external-format :utf-8)))))

(defun create-model-data-manifest (structure file-contents generated-at)
  (let ((files (make-hash-table :test #'equal)))
    (maphash
     (lambda (filename content)
       (setf (gethash filename files)
             (octets-hex (sha256-bytes (utf8-octets content)))))
     file-contents)
    (json-object
     "schemaVersion" +model-data-schema-version+
     "generatedAt" generated-at
     "structureHash" (model-data-structure-hash structure)
     "files" files)))

(defun model-data-string-set-difference (expected actual)
  (let ((missing (set-difference expected actual :test #'string=))
        (extra (set-difference actual expected :test #'string=)))
    (format nil "~@[missing: ~{~A~^, ~}~]~:[~;~:*; ~]~@[extra: ~{~A~^, ~}~]"
            missing (and missing extra) extra)))

(defun model-data-positive-number-p (value)
  (and (realp value) (plusp value)))

(defun validate-model-data-value
    (value provider-id model-id expected-api errors)
  (labels ((problem (format-control &rest arguments)
             (push (apply #'format nil format-control arguments) errors))
           (field (key)
             (and (hash-table-p value) (json-get value key))))
    (unless (hash-table-p value)
      (problem "~A/~A must be an object" provider-id model-id)
      (return-from validate-model-data-value errors))
    (unless (equal model-id (field "id"))
      (problem "~A/~A has id ~S, expected ~S"
               provider-id model-id (field "id") model-id))
    (unless (equal provider-id (field "provider"))
      (problem "~A/~A has provider ~S, expected ~S"
               provider-id model-id (field "provider") provider-id))
    (unless (equal expected-api (field "api"))
      (problem "~A/~A has api ~S, expected ~S"
               provider-id model-id (field "api") expected-api))
    (unless (non-empty-string-p (field "name"))
      (problem "~A/~A has no model name" provider-id model-id))
    (unless (stringp (field "baseUrl"))
      (problem "~A/~A has no baseUrl string" provider-id model-id))
    (unless (typep (field "reasoning") 'boolean)
      (problem "~A/~A has no reasoning boolean" provider-id model-id))
    (let ((input (field "input")))
      (unless
          (and (vectorp input)
               (plusp (length input))
               (every (lambda (entry)
                        (member entry '("text" "image") :test #'string=))
                      input))
        (problem "~A/~A has invalid input modalities" provider-id model-id)))
    (unless (model-data-positive-number-p (field "contextWindow"))
      (problem "~A/~A has invalid contextWindow" provider-id model-id))
    (unless (model-data-positive-number-p (field "maxTokens"))
      (problem "~A/~A has invalid maxTokens" provider-id model-id))
    (let ((cost (field "cost")))
      (if (not (hash-table-p cost))
          (problem "~A/~A has invalid cost metadata" provider-id model-id)
          (dolist (cost-field '("input" "output" "cacheRead" "cacheWrite"))
            (unless (realp (json-get cost cost-field))
              (problem "~A/~A has invalid cost.~A"
                       provider-id model-id cost-field)))))
    errors))

(defun signal-model-data-validation-errors (errors)
  (let* ((ordered (nreverse errors))
         (visible (subseq ordered 0 (min 30 (length ordered))))
         (remaining (- (length ordered) (length visible))))
    (error "Invalid generated model data:~%~{  - ~A~%~}~@[  ... and ~D more~]"
           visible (and (plusp remaining) remaining))))

(defun valid-model-data-timestamp-p (value)
  (and (non-empty-string-p value)
       (position #\T value)
       (char= #\Z (char value (1- (length value))))))

(defun validate-model-data-directory (structure directory)
  (unless (uiop:directory-exists-p directory)
    (error "Generated model data directory does not exist: ~A" directory))
  (let* ((errors nil)
         (expected-files
           (sort
            (loop for provider-id being the hash-keys of structure
                  collect (format nil "~A.json" provider-id))
            #'string<))
         (actual-files
           (sort
            (loop for path in (uiop:directory-files directory)
                  when (model-data-json-path-p path)
                    collect (file-namestring path))
            #'string<))
         (manifest-path (merge-pathnames +model-data-manifest-file+ directory))
         (manifest
           (handler-case
               (parse-json
                (uiop:read-file-string manifest-path :external-format :utf-8))
             (error (cause)
               (push (format nil "model data manifest is not valid JSON: ~A" cause)
                     errors)
               nil)))
         (manifest-files
           (and (hash-table-p manifest) (json-get manifest "files"))))
    (unless (equal expected-files actual-files)
      (push
       (format nil
               "provider data files do not match the generated catalog (~A)"
               (model-data-string-set-difference expected-files actual-files))
       errors))
    (unless (= +model-data-schema-version+
               (if (hash-table-p manifest)
                   (or (json-get manifest "schemaVersion") -1)
                   -1))
      (push
       (format nil "model data schema is ~S, expected ~D"
               (and (hash-table-p manifest)
                    (json-get manifest "schemaVersion"))
               +model-data-schema-version+)
       errors))
    (unless (and (hash-table-p manifest)
                 (valid-model-data-timestamp-p
                  (json-get manifest "generatedAt")))
      (push "model data manifest has an invalid generation timestamp" errors))
    (unless (and (hash-table-p manifest)
                 (string= (or (json-get manifest "structureHash") "")
                          (model-data-structure-hash structure)))
      (push "model data generation stamp does not match the generated catalog"
            errors))
    (if (not (hash-table-p manifest-files))
        (push "model data manifest has no file hashes" errors)
        (let ((manifest-file-names (model-data-sorted-keys manifest-files)))
          (unless (equal expected-files manifest-file-names)
            (push
             (format nil
                     "manifest file hashes do not match provider data files (~A)"
                     (model-data-string-set-difference
                      expected-files manifest-file-names))
             errors))))
    (maphash
     (lambda (provider-id expected-models)
       (let* ((filename (format nil "~A.json" provider-id))
              (path (merge-pathnames filename directory)))
         (when (probe-file path)
           (when (and (hash-table-p manifest-files)
                      (not
                       (string=
                        (or (json-get manifest-files filename) "")
                        (model-data-file-hash path))))
             (push (format nil "~A does not match its manifest hash" filename)
                   errors))
           (let ((groups
                   (handler-case
                       (parse-json
                        (uiop:read-file-string path :external-format :utf-8))
                     (error (cause)
                       (push (format nil "~A is not valid JSON: ~A" filename cause)
                             errors)
                       nil)))
                 (actual-models (make-hash-table :test #'equal)))
             (when (hash-table-p groups)
               (walk-model-data-groups
                groups
                (lambda (api)
                  (push (format nil "~A API group ~S must be an object"
                                filename api)
                        errors))
                (lambda (api group model-id)
                  (if (nth-value 1 (gethash model-id actual-models))
                      (push
                       (format nil "~A/~A appears in more than one API group"
                               provider-id model-id)
                       errors)
                      (setf (gethash model-id actual-models) api))
                  (setf errors
                        (validate-model-data-value
                         (json-get group model-id)
                         provider-id model-id api errors))))
               (let ((expected-ids (model-data-sorted-keys expected-models))
                     (actual-ids (model-data-sorted-keys actual-models)))
                 (unless (equal expected-ids actual-ids)
                   (push
                    (format nil
                            "~A model IDs do not match the generated catalog (~A)"
                            filename
                            (model-data-string-set-difference expected-ids actual-ids))
                    errors)))
               (maphash
                (lambda (model-id expected-api)
                  (multiple-value-bind (actual-api present-p)
                      (gethash model-id actual-models)
                    (when (and present-p
                               (not (string= actual-api expected-api)))
                      (push
                       (format nil
                               "~A/~A is grouped under API ~S, expected ~S"
                               provider-id model-id actual-api expected-api)
                       errors))))
                expected-models))))))
     structure)
    (when errors
      (signal-model-data-validation-errors errors))
    t))

(defun models-dev-effort-thinking-level-map (options)
  (let ((effort-values
          (loop for option in options
                when (eq :effort (getf option :type))
                  append (copy-list (or (getf option :values) nil)))))
    (when
        (and effort-values
             (or (member "none" effort-values :test #'string=)
                 (some
                  (lambda (level)
                    (member (string-downcase (symbol-name level))
                            effort-values :test #'string=))
                  +models-dev-thinking-levels+)))
      (cons
       (cons :off
             (and (member "none" effort-values :test #'string=) "none"))
       (loop for level in +models-dev-thinking-levels+
             for text = (string-downcase (symbol-name level))
             collect
             (cons level
                   (and (member text effort-values :test #'string=) text)))))))

(defun openrouter-thinking-level-map (reasoning)
  ;; Baseline packages/ai/scripts/openrouter-reasoning-options.ts
  ;; getOpenRouterThinkingLevelMap (v0.84.4).
  (unless reasoning
    (return-from openrouter-thinking-level-map nil))
  (let ((mandatory-p (eq t (getf reasoning :mandatory)))
        (efforts (getf reasoning :supported-efforts))
        (fallback (and (eq t (getf reasoning :mandatory))
                       (list (cons :off nil)))))
    (unless (and (listp efforts) (plusp (length efforts)))
      (return-from openrouter-thinking-level-map fallback))
    (let ((map
            (models-dev-effort-thinking-level-map
             (list (list :type :effort :values efforts)))))
      (unless map
        (return-from openrouter-thinking-level-map fallback))
      (let ((copy (copy-tree map))
            (off (assoc :off map)))
        (if off
            (setf (cdr (assoc :off copy))
                  (if mandatory-p nil "none"))
            (push (cons :off (if mandatory-p nil "none")) copy))
        copy))))

(defun get-builtin-model-data-generated-at ()
  *generated-model-data-generated-at*)

(defun model-data-u8-vector (&optional (capacity 1024))
  (make-array capacity :element-type '(unsigned-byte 8)
              :adjustable t :fill-pointer 0))

(defun model-data-append-u32 (output value)
  (loop for shift in '(24 16 8 0)
        do (vector-push-extend (ldb (byte 8 shift) value) output))
  output)

(defun model-data-crc32 (octets)
  (let ((crc #xffffffff))
    (loop for octet across octets
          do (setf crc (logxor crc octet))
             (dotimes (index 8)
               (declare (ignorable index))
               (setf crc
                     (if (oddp crc)
                         (logxor #xedb88320 (ash crc -1))
                         (ash crc -1)))))
    (logxor crc #xffffffff)))

(defun model-data-adler32 (octets)
  (let ((a 1) (b 0))
    (loop for octet across octets
          do (setf a (mod (+ a octet) 65521)
                   b (mod (+ b a) 65521)))
    (logior (ash b 16) a)))

(defun model-data-zlib-store (octets)
  (let ((output (model-data-u8-vector (+ (length octets) 16))))
    (vector-push-extend #x78 output)
    (vector-push-extend #x01 output)
    (loop with offset = 0
          while (< offset (length octets))
          for size = (min 65535 (- (length octets) offset))
          for final-p = (= (+ offset size) (length octets))
          do (vector-push-extend (if final-p 1 0) output)
             (vector-push-extend (ldb (byte 8 0) size) output)
             (vector-push-extend (ldb (byte 8 8) size) output)
             (let ((complement (logand #xffff (lognot size))))
               (vector-push-extend (ldb (byte 8 0) complement) output)
               (vector-push-extend (ldb (byte 8 8) complement) output))
             (loop for index from offset below (+ offset size)
                   do (vector-push-extend (aref octets index) output))
             (incf offset size))
    (model-data-append-u32 output (model-data-adler32 octets))
    output))

(defun model-data-write-png-chunk (stream type data)
  (let* ((type-octets (utf8-octets type))
         (payload
           (concatenate '(vector (unsigned-byte 8)) type-octets data)))
    (let ((length-bytes (model-data-u8-vector 4)))
      (model-data-append-u32 length-bytes (length data))
      (write-sequence length-bytes stream))
    (write-sequence payload stream)
    (let ((crc-bytes (model-data-u8-vector 4)))
      (model-data-append-u32 crc-bytes (model-data-crc32 payload))
      (write-sequence crc-bytes stream))))

(defun write-red-circle-test-png (path &key (width 200) (height 200))
  (unless (and (plusp width) (plusp height))
    (error "PNG dimensions must be positive"))
  (let* ((rows
           (make-array (* height (1+ (* width 4)))
                       :element-type '(unsigned-byte 8)))
         (center-x (/ width 2d0))
         (center-y (/ height 2d0))
         (radius (/ (min width height) 4d0))
         (radius-squared (* radius radius)))
    (dotimes (y height)
      (let ((row-start (* y (1+ (* width 4)))))
        (setf (aref rows row-start) 0)
        (dotimes (x width)
          (let* ((inside-p
                   (<= (+ (expt (- (+ x 0.5d0) center-x) 2)
                          (expt (- (+ y 0.5d0) center-y) 2))
                       radius-squared))
                 (offset (+ row-start 1 (* x 4))))
            (setf (aref rows offset) 255
                  (aref rows (+ offset 1)) (if inside-p 0 255)
                  (aref rows (+ offset 2)) (if inside-p 0 255)
                  (aref rows (+ offset 3)) 255)))))
    (ensure-directories-exist path)
    (with-open-file
        (stream path :direction :output :if-exists :supersede
                :if-does-not-exist :create
                :element-type '(unsigned-byte 8))
      (write-sequence #(137 80 78 71 13 10 26 10) stream)
      (let ((ihdr (model-data-u8-vector 13)))
        (model-data-append-u32 ihdr width)
        (model-data-append-u32 ihdr height)
        (dolist (value '(8 6 0 0 0))
          (vector-push-extend value ihdr))
        (model-data-write-png-chunk stream "IHDR" ihdr))
      (model-data-write-png-chunk stream "IDAT"
                                  (model-data-zlib-store rows))
      (model-data-write-png-chunk
       stream "IEND" (make-array 0 :element-type '(unsigned-byte 8))))
    path))
