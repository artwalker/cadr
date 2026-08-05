(require :asdf)

(defparameter *tool-result-diff-arguments* (uiop:command-line-arguments))

(when (< (length *tool-result-diff-arguments*) 5)
  (format *error-output*
          "usage: cadr-driver.lisp PROJECT QUICKLISP MANIFEST WORKSPACE OUTPUT~%")
  (uiop:quit 2))

(let* ((project
         (uiop:ensure-directory-pathname
          (pathname (first *tool-result-diff-arguments*))))
       (quicklisp (pathname (second *tool-result-diff-arguments*)))
       (sink (make-broadcast-stream)))
  (let ((*standard-output* sink)
        (*error-output* sink)
        (*trace-output* sink))
    (load quicklisp)
    (dolist (name '("cadr-core.asd" "cadr-ai.asd" "cadr-agent.asd"
                    "cadr-tui.asd" "cadr-cli.asd"))
      (asdf:load-asd (truename (merge-pathnames name project))))
    (asdf:load-system "cadr-cli")))

(defpackage #:goal17-tool-result-diff-cadr-driver
  (:use #:cl))

(in-package #:goal17-tool-result-diff-cadr-driver)

(defparameter *tool-result-diff-arguments*
  cl-user::*tool-result-diff-arguments*)

(defun json-get (object key &optional default)
  (if (hash-table-p object)
      (gethash key object default)
      default))

(defun vector-list (value)
  (if (vectorp value) (coerce value 'list) nil))

(defun text-base64 (text)
  (cadr-ai::base64url-encode
   (sb-ext:string-to-octets text :external-format :utf-8)))

(defun file-sha256 (path)
  (with-open-file
      (stream path :direction :input
                   :element-type '(unsigned-byte 8))
    (let ((octets
            (make-array (file-length stream)
                        :element-type '(unsigned-byte 8))))
      (read-sequence octets stream)
      (string-downcase
       (format nil "~{~2,'0x~}"
               (coerce (cadr-ai::sha256-bytes octets) 'list))))))

(defun serialize-content-block (block)
  (cond
    ((typep block 'cadr-ai:text-content)
     (cadr-ai::json-object
      "type" "text"
      "utf8Base64"
      (text-base64 (cadr-ai:text-content-text block))))
    ((typep block 'cadr-ai:image-content)
     (cadr-ai::json-object
      "type" "image"
      "mimeType" (cadr-ai:image-content-mime-type block)
      "dataBase64" (cadr-ai:image-content-data block)))
    (t
     (error "Unsupported Cadr tool-result content block: ~S"
            (type-of block)))))

(defun serialize-result (scenario result)
  (let* ((details (cadr-ai:tool-result-message-details result))
         (full-output-path
           (and (listp details)
                (getf details :full-output-path)))
         (object
           (cadr-ai::json-object
            "scenarioId" (json-get scenario "id")
            "isError" (cadr-ai:tool-result-message-is-error result)
            "content"
            (cadr-ai::list-json-array
             (mapcar #'serialize-content-block
                     (cadr-ai:tool-result-message-content result))))))
    (when full-output-path
      (setf
       (gethash "typedFullOutputPath" object)
       full-output-path
       (gethash "typedFullOutputSha256" object)
       (file-sha256 full-output-path)))
    object))

(defun run-scenario (workspace scenario)
  (let* ((scenario-id (json-get scenario "id"))
         (cwd
           (uiop:ensure-directory-pathname
            (merge-pathnames
             (format nil "~A/" scenario-id)
             workspace)))
         (tools (cadr-cli::make-all-coding-tools cwd))
         (agent
           (cadr-agent:make-agent
            :provider :fixed
            :model nil
            :system-prompt "fixed tool-result differential"
            :tools tools))
         (call
           (cadr-ai:make-tool-call
            :id (format nil "call-~A" scenario-id)
            :name (json-get scenario "tool")
            :arguments (json-get scenario "arguments"))))
    (multiple-value-bind (results appended aborted-p terminate-p)
        (cadr-agent::execute-tool-batch agent (list call) :turn-index 0)
      (declare (ignore appended aborted-p terminate-p))
      (unless (= 1 (length results))
        (error "Cadr produced ~D results for ~A"
               (length results) scenario-id))
      (serialize-result scenario (first results)))))

(defun main ()
  (let* ((manifest-path
           (pathname (third *tool-result-diff-arguments*)))
         (workspace
           (uiop:ensure-directory-pathname
            (pathname (fourth *tool-result-diff-arguments*))))
         (output-path
           (pathname (fifth *tool-result-diff-arguments*)))
         (manifest
           (cadr-ai::parse-json
            (uiop:read-file-string
             manifest-path :external-format :utf-8)))
         (results
           (mapcar
            (lambda (scenario)
              (run-scenario workspace scenario))
            (vector-list (json-get manifest "scenarios"))))
         (payload
           (cadr-ai::json-object
            "implementation" "cadr"
            "sbcl" (lisp-implementation-version)
            "results" (cadr-ai::list-json-array results))))
    (with-open-file
        (stream output-path
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create
                :external-format :utf-8)
      (write-string (cadr-ai::stringify-json payload) stream)
      (terpri stream)))
  (uiop:quit 0))

(handler-case
    (main)
  (condition (condition)
    (format *error-output* "tool-result Cadr driver failed: ~A~%" condition)
    (uiop:quit 2)))
