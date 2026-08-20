(in-package #:cadr-cli)

(defparameter +default-hugging-face-url+
  "https://huggingface.co")

(defparameter +gguf-quantization-pattern+
  "(?i)((?:UD-)?(?:IQ[0-9](?:_[A-Z0-9]+)+|Q[0-9](?:_[A-Z0-9]+)+|BF16|F16|F32|MXFP[0-9](?:_[A-Z0-9]+)*))$")

(defstruct (hugging-face-client
            (:constructor %make-hugging-face-client))
  token
  (base-url +default-hugging-face-url+
            :type string))

(cadr-core:define-redacted-print-object
    (hugging-face-client value stream)
  (format stream ":base-url ~A :token [REDACTED]"
          (hugging-face-client-base-url value)))

(defun make-hugging-face-client
    (&key token
       (base-url +default-hugging-face-url+))
  (%make-hugging-face-client
   :token token
   :base-url
   (string-right-trim '(#\/) base-url)))

(defun hugging-face-headers (client)
  (and
   (hugging-face-client-token client)
   (plusp
    (length (hugging-face-client-token client)))
   (list
    (cons
     "Authorization"
     (format nil "Bearer ~A"
             (hugging-face-client-token client))))))

(defun hugging-face-request (client path)
  (cadr-ai:request-json
   (cadr-ai::make-request-spec
    :url
    (format nil "~A~A"
            (hugging-face-client-base-url client)
            path)
    :method :get
    :headers (hugging-face-headers client)
    :provider :hugging-face)
   :read-timeout 15))

(defun hugging-face-search (client query)
  (let ((payload
          (hugging-face-request
           client
           (format
            nil
            "/api/models?search=~A&filter=gguf&sort=downloads&direction=-1&limit=20"
            (cadr-ai::percent-encode query)))))
    (unless (vectorp payload)
      (error
       'cadr-ai:transport-error
       :message
       "Hugging Face returned invalid search results"))
    (loop for value across payload
          for id =
          (and
           (hash-table-p value)
           (cadr-ai::json-get value "id"))
          when (stringp id)
            collect
            (list
             id
             (let ((downloads
                     (cadr-ai::json-get
                      value "downloads")))
               (if (numberp downloads)
                   downloads
                   0))))))

(defun parse-llama-hugging-face-model (value)
  "Baseline parseHuggingFaceModel (extensions/llama/index.ts): the
quantization splits at the first colon after the first slash."
  (let* ((slash (position #\/ value))
         (colon (position #\: value :start (1+ (or slash -1)))))
    (if colon
        (values
         (subseq value 0 colon)
         (subseq value (1+ colon)))
        (values value nil))))

(defun encode-hugging-face-id (id)
  (format nil "~{~A~^/~}"
          (mapcar
           #'cadr-ai::percent-encode
           (uiop:split-string
            id :separator '(#\/)))))

(defun gguf-filename-p (filename)
  (and
   (> (length filename) 5)
   (string-equal
    ".gguf" filename
    :start2 (- (length filename) 5))))

(defun gguf-basename (path)
  (let ((slash (position #\/ path :from-end t)))
    (if slash
        (subseq path (1+ slash))
        path)))

(defun gguf-quantization (filename)
  (let* ((stem
           (subseq filename
                   0 (- (length filename) 5)))
         (without-shard
           (cl-ppcre:regex-replace
            "-[0-9]{5}-of-[0-9]{5}$"
            stem ""))
         (registers nil))
    (multiple-value-bind
          (start end register-starts register-ends)
        (cl-ppcre:scan
         +gguf-quantization-pattern+
         without-shard)
      (declare (ignore start end))
      (setf registers
            (and register-starts register-ends
                 (aref register-starts 0)
                 (subseq
                  without-shard
                  (aref register-starts 0)
                  (aref register-ends 0)))))
    (and registers
         (string-upcase registers))))

(defun hugging-face-details (client id)
  (let ((payload
          (hugging-face-request
           client
           (format nil
                   "/api/models/~A?blobs=true"
                   (encode-hugging-face-id id)))))
    (unless (hash-table-p payload)
      (error
       'cadr-ai:transport-error
       :message
       "Hugging Face returned invalid model details"))
    (let ((sizes (make-hash-table :test #'equal))
          (siblings
            (cadr-ai::json-get payload "siblings")))
      (when (vectorp siblings)
        (loop for value across siblings
              for filename =
              (and
               (hash-table-p value)
               (cadr-ai::json-get
                value "rfilename"))
              when
              (and
               (stringp filename)
               (gguf-filename-p filename)
               (not
                (uiop:string-prefix-p
                 "mmproj"
                 (string-downcase
                  (gguf-basename filename)))))
                do
                (let ((quantization
                        (gguf-quantization
                         (gguf-basename filename)))
                      (size
                        (cadr-ai::json-get value "size")))
                  (when quantization
                    (multiple-value-bind
                          (current found-p)
                        (gethash quantization sizes)
                      (setf
                       (gethash quantization sizes)
                       (list
                        (+ (or (first current) 0)
                           (if (numberp size)
                               size
                               0))
                        (and
                         (if found-p
                             (second current)
                             t)
                         (numberp size)))))))))
      (let ((quantizations
              (sort
               (loop for name being the hash-keys
                       of sizes
                     using (hash-value data)
                     collect
                     (list
                      name
                      (and (second data)
                           (first data))))
               (lambda (left right)
                 (cond
                   ((string= (first left)
                             (first right))
                    nil)
                   ((string= "Q4_K_M"
                             (first left))
                    t)
                   ((string= "Q4_K_M"
                             (first right))
                    nil)
                   ((and (second left)
                         (second right)
                         (/= (second left)
                             (second right)))
                    (< (second left)
                       (second right)))
                   ((second left) t)
                   ((second right) nil)
                   (t
                    (string<
                     (first left)
                     (first right))))))))
        (list
         :id
         (or
          (cadr-ai::json-get payload "id")
          id)
         :gated
         (let ((gated
                 (cadr-ai::json-get
                  payload "gated")))
           (cond
             ((and (stringp gated)
                   (string= gated "auto"))
              :auto)
             ((and (stringp gated)
                   (string= gated "manual"))
              :manual)
             (t nil)))
         :quantizations quantizations)))))

(defun find-hugging-face-token ()
  (or
   (let ((value (uiop:getenv "HF_TOKEN")))
     (and value
          (let ((trimmed
                  (string-trim
                   '(#\Space #\Tab #\Newline
                     #\Return)
                   value)))
            (and (plusp (length trimmed))
                 trimmed))))
   (let ((paths
           (remove
            nil
            (list
             (uiop:getenv "HF_TOKEN_PATH")
             (let ((home
                     (uiop:getenv "HF_HOME")))
               (and home
                    (namestring
                     (merge-pathnames
                      "token"
                      (uiop:ensure-directory-pathname
                       home)))))
             (let ((cache
                     (uiop:getenv
                      "XDG_CACHE_HOME")))
               (and cache
                    (namestring
                     (merge-pathnames
                      "huggingface/token"
                      (uiop:ensure-directory-pathname
                       cache)))))
             (namestring
              (merge-pathnames
               ".cache/huggingface/token"
               (user-homedir-pathname))))
            :test #'equal)))
     (loop for path in
           (remove-duplicates paths :test #'string=)
           for token =
           (ignore-errors
             (string-trim
              '(#\Space #\Tab #\Newline
                #\Return)
              (uiop:read-file-string
               path :external-format :utf-8)))
           when (and token
                     (plusp (length token)))
             return token))))
