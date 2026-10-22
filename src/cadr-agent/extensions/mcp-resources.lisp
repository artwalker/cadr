(in-package #:cadr-agent)

;;; pi@4a080252f extensions/mcp/resources.ts and the resource half of
;;; tools.ts. One pager feeds both resource tools. Wire values stay
;;; :json-object, the same values the server sent.

(defparameter +list-mcp-resources-tool+ "list_mcp_resources")
(defparameter +list-mcp-resource-templates-tool+ "list_mcp_resource_templates")
(defparameter +read-mcp-resource-tool+ "read_mcp_resource")
(defparameter +mcp-output-max-bytes+ (* 20 1024))

(defstruct mcp-resource-server
  (name "" :type string)
  (timeout-ms 60000 :type real)
  resources-page
  templates-page
  all-resources
  all-templates
  read-resource)

(defstruct mcp-resource-tool
  (name "" :type string)
  (label "" :type string)
  (description "" :type string)
  parameters
  output-schema
  (exposure "direct" :type string)
  annotations
  executor)

(defstruct mcp-resource-call-result
  content
  details
  structured-content)

(defun mcp-tool-exposure-name (exposure)
  ;; codemode and deferred both stay out of the model tool list. They
  ;; differ only in which discovery tool reaches them.
  (if (and (stringp exposure) (string= exposure "codemode"))
      "deferred"
      (or exposure "hidden")))

(defun mcp-widest-resource-exposure (exposures)
  ;; direct, then codemode, then deferred. Hidden when none of those.
  (or (find-if (lambda (candidate)
                 (member candidate exposures :test #'string=))
               '("direct" "codemode" "deferred"))
      "hidden"))

(defun mcp-server-name< (left right)
  ;; Node localeCompare under en_US.UTF-8: case-insensitive, and a
  ;; lowercase letter before its uppercase twin.
  (let ((folded-left (string-downcase left))
        (folded-right (string-downcase right)))
    (cond
      ((string< folded-left folded-right) t)
      ((string< folded-right folded-left) nil)
      (t
       (loop for left-char across left
             for right-char across right
             unless (char= left-char right-char)
               return (cond
                        ((and (lower-case-p left-char)
                              (upper-case-p right-char)
                              (char= (char-downcase left-char)
                                     (char-downcase right-char)))
                         t)
                        ((and (upper-case-p left-char)
                              (lower-case-p right-char)
                              (char= (char-downcase left-char)
                                     (char-downcase right-char)))
                         nil)
                        (t (char< left-char right-char)))
             finally (return nil))))))

(defun mcp-lookup-argument (params key)
  (cond
    ((hash-table-p params) (gethash key params))
    ((mcp-object-p params) (mcp-get params key))
    (t (values nil nil))))

(defun mcp-string-argument (params key)
  (multiple-value-bind (value present) (mcp-lookup-argument params key)
    (when (or (not present) (null value) (eq value 'null))
      (return-from mcp-string-argument nil))
    (unless (stringp value)
      (error "~A must be a string" key))
    (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
      (when (plusp (length trimmed))
        trimmed))))

(defun mcp-find-resource-server (servers name)
  (let ((server (find name servers
                      :key #'mcp-resource-server-name
                      :test #'string=)))
    (unless server
      (error "MCP server ~S has no resources~@[. Servers with resources: ~{~A~^, ~}~]"
             name
             (mapcar #'mcp-resource-server-name servers)))
    server))

(defun mcp-skip-space (text index)
  (loop while (and (< index (length text))
                   (member (char text index)
                           '(#\Space #\Tab #\Newline #\Return #\Page)))
        do (incf index))
  index)

(defun mcp-app-profile-piece-p (text index)
  (setf index (mcp-skip-space text index))
  (unless (and (<= (+ index 7) (length text))
               (string= text "profile" :start1 index :end1 (+ index 7)))
    (return-from mcp-app-profile-piece-p nil))
  (setf index (mcp-skip-space text (+ index 7)))
  (unless (and (< index (length text)) (char= (char text index) #\=))
    (return-from mcp-app-profile-piece-p nil))
  (setf index (mcp-skip-space text (1+ index)))
  (when (and (< index (length text)) (char= (char text index) #\"))
    (incf index))
  (and (<= (+ index 7) (length text))
       (string= text "mcp-app" :start1 index :end1 (+ index 7))))

(defun mcp-app-mime-p (mime)
  (when (stringp mime)
    (let ((text (string-downcase mime))
          (start 0))
      (loop for semi = (position #\; text :start start)
            while semi
            thereis (mcp-app-profile-piece-p text (1+ semi))
            do (setf start (1+ semi))))))

(defun mcp-app-resource-p (item)
  ;; MCP App user interfaces are for hosts that render them.
  (let ((uri (or (mcp-get item "uri") (mcp-get item "uriTemplate") "")))
    (or (and (stringp uri)
             (>= (length uri) 5)
             (string= (subseq uri 0 5) "ui://"))
        (mcp-app-mime-p (mcp-get item "mimeType")))))

(defun mcp-listed (server-name item)
  (list* :json-object
         (list* "server" server-name
                (loop for (key value) on (cdr item) by #'cddr
                      unless (or (string= key "_meta") (string= key "icons"))
                        nconc (list key value)))))

(defun mcp-page-values (page key)
  (values (coerce (or (mcp-get page key) #()) 'list)
          (let ((next (mcp-get page "nextCursor")))
            (when (and (stringp next) (plusp (length next)))
              next))))

(defun mcp-client-resource-server (name client &key (timeout-ms 60000))
  (make-mcp-resource-server
   :name name
   :timeout-ms timeout-ms
   :resources-page
   (lambda (cursor abort)
     (mcp-page-values
      (mcp-list-resources-page client cursor
                               :abort abort :timeout-ms timeout-ms)
      "resources"))
   :templates-page
   (lambda (cursor abort)
     (mcp-page-values
      (mcp-list-resource-templates-page client cursor
                                        :abort abort :timeout-ms timeout-ms)
      "resourceTemplates"))
   :all-resources
   (lambda (abort)
     (mcp-list-resources client :abort abort :timeout-ms timeout-ms))
   :all-templates
   (lambda (abort)
     (mcp-list-resource-templates client :abort abort :timeout-ms timeout-ms))
   :read-resource
   (lambda (uri abort)
     (mcp-read-resource client uri :abort abort :timeout-ms timeout-ms))))

(defun mcp-connection-resource-server (connection)
  (let ((timeout (mcp-connection-timeout-ms connection)))
    (make-mcp-resource-server
     :name (mcp-server-connection-name connection)
     :timeout-ms timeout
     :resources-page
     (lambda (cursor abort)
       (mcp-page-values
        (mcp-server-resources-page connection cursor :abort abort
                                   :timeout-ms timeout)
        "resources"))
     :templates-page
     (lambda (cursor abort)
       (mcp-page-values
        (mcp-server-resource-templates-page connection cursor :abort abort
                                            :timeout-ms timeout)
        "resourceTemplates"))
     :all-resources
     (lambda (abort)
       (mcp-server-all-resources connection :abort abort :timeout-ms timeout))
     :all-templates
     (lambda (abort)
       (mcp-server-all-resource-templates connection :abort abort
                                          :timeout-ms timeout))
     :read-resource
     (lambda (uri abort)
       (mcp-server-read-resource connection uri :abort abort
                                 :timeout-ms timeout)))))

(defun mcp-resource-payload (servers params key page-fn all-fn abort)
  (let ((server-name (mcp-string-argument params "server"))
        (cursor (mcp-string-argument params "cursor"))
        (visible (lambda (item) (not (mcp-app-resource-p item)))))
    (if server-name
        (let* ((server (mcp-find-resource-server (funcall servers) server-name)))
          (multiple-value-bind (items next)
              (funcall page-fn server cursor abort)
            (let ((object
                    (mcp-obj "server" (mcp-resource-server-name server)
                             key (coerce
                                  (mapcar (lambda (item)
                                            (mcp-listed
                                             (mcp-resource-server-name server)
                                             item))
                                          (remove-if-not visible items))
                                  'vector))))
              (if next
                  (mcp-put object "nextCursor" next)
                  object))))
        (progn
          (when cursor
            (error "cursor can only be used when a server is specified"))
          (let ((ordered
                  (sort (copy-list (funcall servers))
                        #'mcp-server-name<
                        :key #'mcp-resource-server-name))
                (items nil)
                (errors nil))
            (dolist (server ordered)
              (handler-case
                  (setf items
                        (nconc items
                               (mapcar (lambda (item)
                                         (mcp-listed
                                          (mcp-resource-server-name server)
                                          item))
                                       (remove-if-not
                                        visible
                                        (funcall all-fn server abort)))))
                (error (condition)
                  (setf errors
                        (nconc errors
                               (list (mcp-obj
                                      "server" (mcp-resource-server-name server)
                                      "error" (princ-to-string condition))))))))
            (let ((object (mcp-obj key (coerce items 'vector))))
              (if errors
                  (mcp-put object "errors" (coerce errors 'vector))
                  object)))))))

(defun mcp-base64-value (character)
  (cond
    ((char<= #\A character #\Z) (- (char-code character) (char-code #\A)))
    ((char<= #\a character #\z) (+ 26 (- (char-code character) (char-code #\a))))
    ((char<= #\0 character #\9) (+ 52 (- (char-code character) (char-code #\0))))
    ((char= character #\+) 62)
    ((char= character #\/) 63)
    (t nil)))

(defun mcp-decode-base64 (text)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8)
                         :adjustable t :fill-pointer 0))
        (value 0)
        (bits 0))
    (loop for character across text
          for digit = (mcp-base64-value character)
          do (cond
               ((eql digit nil)
                (when (char= character #\=)
                  (return)))
               (t
                (setf value (logior (ash value 6) digit)
                      bits (+ bits 6))
                (when (>= bits 8)
                  (decf bits 8)
                  (vector-push-extend (ldb (byte 8 bits) value) out)
                  (setf value (logand value (1- (ash 1 bits))))))))
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun mcp-text-mime-p (mime)
  (when (stringp mime)
    (let* ((semi (position #\; mime))
           (type (string-downcase
                  (string-trim '(#\Space #\Tab #\Newline #\Return)
                               (if semi (subseq mime 0 semi) mime)))))
      (or (uiop:string-prefix-p "text/" type)
          (string= type "application/json")
          (and (>= (length type) 5)
               (string= (subseq type (- (length type) 5)) "+json"))
          (and (>= (length type) 4)
               (string= (subseq type (- (length type) 4)) "+xml"))))))

(defun mcp-short-extension-p (suffix)
  (and (<= 2 (length suffix) 9)
       (char= (char suffix 0) #\.)
       (every (lambda (character)
                (or (char<= #\A character #\Z)
                    (char<= #\a character #\z)
                    (char<= #\0 character #\9)))
              (subseq suffix 1))))

(defun mcp-resource-extension (uri)
  (let* ((parsed (and (stringp uri) (parse-mcp-url uri)))
         (path (if parsed (mcp-url-part parsed :pathname) (or uri "")))
         (dot (position #\. path :from-end t)))
    (if (and dot (mcp-short-extension-p (subseq path dot)))
        (subseq path dot)
        ".bin")))

(defun mcp-save-output-file (data extension)
  ;; Output can carry private data. O_EXCL does not follow a symlink
  ;; planted at the path, and the mode is 0600.
  (let ((binary-p (not (stringp data))))
    (loop repeat 8
          for name = (format nil "cadr-mcp-~A~A"
                             (cadr-ai:octets-hex
                              (cadr-ai::secure-random-bytes 8))
                             extension)
          for path = (merge-pathnames name (uiop:temporary-directory))
          do (handler-case
                 (return
                   (let ((descriptor
                           (sb-posix:open
                            (namestring path)
                            (logior sb-posix:o-wronly
                                    sb-posix:o-creat
                                    sb-posix:o-excl)
                            #o600)))
                     (unwind-protect
                          (let ((stream
                                  (sb-sys:make-fd-stream
                                   descriptor
                                   :output t
                                   :element-type (if binary-p
                                                     '(unsigned-byte 8)
                                                     'character)
                                   :buffering :full
                                   :auto-close t
                                   :name (pathname path)
                                   :external-format
                                   (if binary-p :default :utf-8))))
                            (setf descriptor nil)
                            (unwind-protect
                                 (progn
                                   (if binary-p
                                       (write-sequence data stream)
                                       (write-string data stream))
                                   (finish-output stream))
                              (when (open-stream-p stream)
                                (close stream))))
                       (when descriptor
                         (sb-posix:close descriptor)))
                     (namestring path)))
               (sb-posix:syscall-error (condition)
                 (unless (= (sb-posix:syscall-errno condition)
                            sb-posix:eexist)
                   (error condition))))
          finally (error "Unable to allocate an output file"))))

(defun mcp-blob-block (resource blob mime save-output)
  (unless (stringp blob)
    (error "MCP resource blob is not base64 text"))
  (let* ((data (mcp-decode-base64 blob))
         (uri (or (mcp-get resource "uri") "")))
    (if (mcp-text-mime-p mime)
        (mcp-obj "type" "text"
                 "text" (sb-ext:octets-to-string data :external-format :utf-8))
        (let ((kind (format nil "~A, ~A"
                            (or (and (stringp mime) mime) "unknown type")
                            (format-size (length data)))))
          (handler-case
              (let ((path (funcall (or save-output #'mcp-save-output-file)
                                   data
                                   (mcp-resource-extension uri))))
                (mcp-obj "type" "text"
                         "text"
                         (format nil
                                 "[Binary resource ~A (~A) saved to ~A]"
                                 uri kind path)))
            (error (condition)
              (mcp-obj "type" "text"
                       "text"
                       (format nil
                               "[Binary resource ~A (~A) could not be saved: ~A]"
                               uri kind condition))))))))

(defun mcp-one-resource-content (resource save-output)
  (multiple-value-bind (blob present) (mcp-get resource "blob")
    (let ((mime (mcp-get resource "mimeType")))
      (if (and present
               (not (and (stringp mime)
                         (uiop:string-prefix-p "image/" mime))))
          (list (mcp-blob-block resource blob mime save-output))
          (list (mcp-block-to-llm
                 (mcp-obj "type" "resource" "resource" resource)))))))

(defun mcp-read-model-blocks (contents save-output)
  (let ((many (> (length contents) 1)))
    (loop for item in contents
          nconc (append
                 (when many
                   (list (mcp-obj "type" "text"
                                  "text" (format nil "~A:"
                                                 (or (mcp-get item "uri") "")))))
                 (mcp-one-resource-content item save-output)))))

(defun mcp-without-meta (item)
  (if (mcp-object-p item)
      (list* :json-object
             (loop for (key value) on (cdr item) by #'cddr
                   unless (string= key "_meta")
                     nconc (list key value)))
      item))

(defun mcp-block-text (block)
  (when (and (stringp (mcp-get block "type"))
             (string= (mcp-get block "type") "text"))
    (or (mcp-get block "text") "")))

(defun mcp-joined-text (blocks)
  (with-output-to-string (out)
    (loop with first-p = t
          for block in blocks
          for text = (mcp-block-text block)
          when text
            do (unless first-p
                 (write-char #\Newline out))
               (setf first-p nil)
               (write-string text out))))

(defun mcp-output-line-count (content)
  (if (zerop (length content))
      0
      (let ((newlines (count #\Newline content)))
        (if (char= (char content (1- (length content))) #\Newline)
            newlines
            (1+ newlines)))))

(defun mcp-utf8-boundary-p (octets index)
  (or (>= index (length octets))
      (/= (logand (aref octets index) #xc0) #x80)))

(defun mcp-octets-string (octets start end)
  (sb-ext:octets-to-string (subseq octets start end) :external-format :utf-8))

(defun mcp-truncate-text-middle (content max-bytes)
  ;; pi@4a080252f truncateMiddle, byte budget split to each end.
  (let* ((octets (cadr-ai::utf8-octets content))
         (total (length octets))
         (lines (mcp-output-line-count content)))
    (when (<= total max-bytes)
      (return-from mcp-truncate-text-middle
        (values content nil total lines)))
    (let ((head-end (floor max-bytes 2))
          (tail-start (- total (- max-bytes (floor max-bytes 2)))))
      (loop while (and (> head-end 0)
                       (not (mcp-utf8-boundary-p octets head-end)))
            do (decf head-end))
      (loop while (and (< tail-start total)
                       (not (mcp-utf8-boundary-p octets tail-start)))
            do (incf tail-start))
      (let ((removed (length (mcp-octets-string octets head-end tail-start))))
        (values
         (concatenate 'string
                      (mcp-octets-string octets 0 head-end)
                      (format nil "…~D chars truncated…" removed)
                      (mcp-octets-string octets tail-start total))
         t
         total
         lines)))))

(defun mcp-limit-content (blocks &key (max-bytes +mcp-output-max-bytes+)
                                   save-output)
  (let ((combined (mcp-joined-text blocks)))
    (multiple-value-bind (text truncated total lines)
        (mcp-truncate-text-middle combined max-bytes)
      (unless truncated
        (return-from mcp-limit-content (values blocks nil)))
      (let ((path nil)
            (where nil))
        (handler-case
            (progn
              (setf path (funcall (or save-output #'mcp-save-output-file)
                                  combined ".txt"))
              (setf where
                    (format nil "[Full output: ~A (read it with offset/limit)]"
                            path)))
          (error (condition)
            (setf path nil
                  where (format nil "[Could not save the full output: ~A]"
                                condition))))
        (values
         (cons (mcp-obj "type" "text"
                        "text"
                        (format nil
                                "Warning: truncated output (original token count: ~D)~%Total output lines: ~D~%~%~A~%~%~A"
                                (ceiling total 4)
                                lines
                                text
                                where))
               (loop for block in blocks
                     when (and (stringp (mcp-get block "type"))
                               (string= (mcp-get block "type") "image"))
                       collect block))
         path)))))

(defun mcp-call-details (server tool path)
  (let ((object (mcp-obj "server" (or server "") "tool" tool)))
    (if path
        (mcp-put object "fullOutputPath" path)
        object)))

(defun mcp-finish-call (content details structured)
  (make-mcp-resource-call-result
   :content content
   :details details
   :structured-content structured))

(defun mcp-json-call (tool server payload save-output)
  (multiple-value-bind (content path)
      (mcp-limit-content
       (list (mcp-obj "type" "text" "text" (mcp-write-json payload)))
       :save-output save-output)
    (mcp-finish-call content (mcp-call-details server tool path) payload)))

(defun mcp-string-schema (description)
  (mcp-obj "type" "string" "description" description))

(defun mcp-list-parameters ()
  (mcp-obj "type" "object"
           "properties"
           (mcp-obj "server"
                    (mcp-string-schema
                     "MCP server name. Omit to list every server with resources.")
                    "cursor"
                    (mcp-string-schema
                     "Opaque cursor from a previous call with the same server; omit for the first page."))
           "additionalProperties" nil))

(defun mcp-listing-errors-schema ()
  (mcp-obj "type" "array"
           "description" "Servers that could not be listed"
           "items"
           (mcp-obj "type" "object"
                    "properties"
                    (mcp-obj "server" (mcp-obj "type" "string")
                             "error" (mcp-obj "type" "string"))
                    "required" #("server" "error"))))

(defun mcp-list-output-schema ()
  (mcp-obj "type" "object"
           "properties"
           (mcp-obj "server" (mcp-obj "type" "string")
                    "resources"
                    (mcp-obj "type" "array"
                             "items"
                             (mcp-obj "type" "object"
                                      "properties"
                                      (mcp-obj "server" (mcp-obj "type" "string")
                                               "uri" (mcp-obj "type" "string")
                                               "name" (mcp-obj "type" "string")
                                               "title" (mcp-obj "type" "string")
                                               "description" (mcp-obj "type" "string")
                                               "mimeType" (mcp-obj "type" "string")
                                               "size" (mcp-obj "type" "number"))
                                      "required" #("server" "uri" "name")))
                    "nextCursor" (mcp-obj "type" "string")
                    "errors" (mcp-listing-errors-schema))
           "required" #("resources")))

(defun mcp-list-templates-output-schema ()
  (mcp-obj "type" "object"
           "properties"
           (mcp-obj "server" (mcp-obj "type" "string")
                    "resourceTemplates"
                    (mcp-obj "type" "array"
                             "items"
                             (mcp-obj "type" "object"
                                      "properties"
                                      (mcp-obj "server" (mcp-obj "type" "string")
                                               "uriTemplate"
                                               (mcp-obj "type" "string"
                                                        "description"
                                                        "RFC 6570 URI template")
                                               "name" (mcp-obj "type" "string")
                                               "title" (mcp-obj "type" "string")
                                               "description" (mcp-obj "type" "string")
                                               "mimeType" (mcp-obj "type" "string"))
                                      "required"
                                      #("server" "uriTemplate" "name")))
                    "nextCursor" (mcp-obj "type" "string")
                    "errors" (mcp-listing-errors-schema))
           "required" #("resourceTemplates")))

(defun mcp-read-parameters ()
  (mcp-obj "type" "object"
           "properties"
           (mcp-obj "server"
                    (mcp-string-schema
                     "MCP server name exactly as configured. Must match the 'server' field returned by list_mcp_resources.")
                    "uri"
                    (mcp-string-schema
                     "Resource URI to read. Must be one of the URIs returned by list_mcp_resources."))
           "required" #("server" "uri")
           "additionalProperties" nil))

(defun mcp-read-output-schema ()
  (mcp-obj "type" "object"
           "properties"
           (mcp-obj "server" (mcp-obj "type" "string")
                    "uri" (mcp-obj "type" "string")
                    "contents" (mcp-obj "type" "array"))
           "required" #("server" "uri" "contents")))

(defun mcp-execute-list (tool-name servers params key page-fn all-fn
                         abort save-output)
  (mcp-json-call tool-name
                 (mcp-string-argument params "server")
                 (mcp-resource-payload servers params key page-fn all-fn abort)
                 save-output))

(defun mcp-execute-read (servers params abort save-output)
  (let ((server-name (mcp-string-argument params "server"))
        (uri (mcp-string-argument params "uri")))
    (unless server-name
      (error "server must be provided"))
    (unless uri
      (error "uri must be provided"))
    (let* ((server (mcp-find-resource-server (funcall servers) server-name))
           (result (funcall (mcp-resource-server-read-resource server)
                            uri abort))
           (contents (coerce (or (mcp-get result "contents") #()) 'list))
           (blocks (mcp-read-model-blocks contents save-output))
           (converted
             (if blocks
                 blocks
                 (list (mcp-obj "type" "text"
                                "text" (format nil "Resource ~A is empty." uri))))))
      (multiple-value-bind (content path)
          (mcp-limit-content converted :save-output save-output)
        (mcp-finish-call
         content
         (mcp-call-details (mcp-resource-server-name server)
                           +read-mcp-resource-tool+
                           path)
         (mcp-obj "server" (mcp-resource-server-name server)
                  "uri" uri
                  "contents"
                  (coerce (mapcar #'mcp-without-meta contents) 'vector)))))))

(defun create-mcp-resource-tools (&key (exposure "direct") servers save-output)
  "The three Codex resource tools. SERVERS returns the servers they reach."
  (let ((tool-exposure (mcp-tool-exposure-name exposure))
        (annotations (mcp-obj "readOnlyHint" t))
        (servers (or servers (constantly nil)))
        (list-parameters (mcp-list-parameters)))
    (list
     (make-mcp-resource-tool
      :name +list-mcp-resources-tool+
      :label +list-mcp-resources-tool+
      :description
      "Lists resources provided by MCP servers. Resources allow servers to share data that provides context to language models, such as files, database schemas, or application-specific information. Prefer resources over web search when possible."
      :parameters list-parameters
      :output-schema (mcp-list-output-schema)
      :exposure tool-exposure
      :annotations annotations
      :executor
      (lambda (params &key abort)
        (mcp-execute-list
         +list-mcp-resources-tool+ servers params "resources"
         (lambda (server cursor abort)
           (funcall (mcp-resource-server-resources-page server) cursor abort))
         (lambda (server abort)
           (funcall (mcp-resource-server-all-resources server) abort))
         abort save-output)))
     (make-mcp-resource-tool
      :name +list-mcp-resource-templates-tool+
      :label +list-mcp-resource-templates-tool+
      :description
      "Lists resource templates provided by MCP servers. Parameterized resource templates allow servers to share data that takes parameters and provides context to language models, such as files, database schemas, or application-specific information. Prefer resource templates over web search when possible."
      :parameters list-parameters
      :output-schema (mcp-list-templates-output-schema)
      :exposure tool-exposure
      :annotations annotations
      :executor
      (lambda (params &key abort)
        (mcp-execute-list
         +list-mcp-resource-templates-tool+ servers params "resourceTemplates"
         (lambda (server cursor abort)
           (funcall (mcp-resource-server-templates-page server) cursor abort))
         (lambda (server abort)
           (funcall (mcp-resource-server-all-templates server) abort))
         abort save-output)))
     (make-mcp-resource-tool
      :name +read-mcp-resource-tool+
      :label +read-mcp-resource-tool+
      :description
      "Read a specific resource from an MCP server given the server name and resource URI."
      :parameters (mcp-read-parameters)
      :output-schema (mcp-read-output-schema)
      :exposure tool-exposure
      :annotations annotations
      :executor
      (lambda (params &key abort)
        (mcp-execute-read servers params abort save-output))))))
