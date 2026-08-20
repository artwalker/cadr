(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun parse-json-lines (path)
  (with-open-file
      (stream path :direction :input :external-format :utf-8)
    (loop for line = (read-line stream nil nil)
          while line
          collect (cadr-ai::parse-json line))))

(defun message-texts (messages)
  (loop for message in messages
        collect
        (cond
          ((typep message 'cadr-ai:user-message)
           (cadr-ai:user-message-content message))
          ((typep message 'cadr-ai:assistant-message)
           (cadr-ai:text-content-text
            (first (cadr-ai:assistant-message-content message))))
          (t :tool-result))))

(defun export-test-base64-value (character)
  (position
   character
   "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))

(defun decode-export-test-base64 (text)
  (let ((octets
          (make-array
           0 :element-type '(unsigned-byte 8)
           :adjustable t :fill-pointer 0))
        (accumulator 0)
        (bits 0))
    (loop for character across text
          unless (member character
                         '(#\Space #\Tab #\Newline #\Return #\=))
            do
            (let ((value
                    (export-test-base64-value character)))
              (unless value
                (error "Invalid export base64"))
              (setf accumulator
                    (logior (ash accumulator 6) value)
                    bits (+ bits 6))
              (when (>= bits 8)
                (decf bits 8)
                (vector-push-extend
                 (ldb (byte 8 bits) accumulator)
                 octets)
                (setf accumulator
                      (ldb (byte bits 0) accumulator)))))
    octets))

(defun exported-session-json (html)
  (let* ((marker
           "<script id=\"session-data\" type=\"application/json\">")
         (start
           (search marker html))
         (content-start
           (and start (+ start (length marker))))
         (end
           (and content-start
                (search "</script>" html
                        :start2 content-start))))
    (unless end
      (error "Exported session data element is missing"))
    (cadr-ai::utf8-string
     (decode-export-test-base64
      (subseq html content-start end)))))

(defun exported-session-data (html)
  (cadr-ai::parse-json
   (exported-session-json html)))

(defun export-test-sha256 (text)
  (string-downcase
   (format
    nil "~{~2,'0X~}"
    (coerce
     (cadr-ai::sha256-bytes
      (cadr-ai::utf8-octets text))
     'list))))

(test session-v2-branches-from-any-node-and-persists-both-paths
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "tree"))
           (root-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content "root" :timestamp 1)))
           (first-leaf-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content :text "first"))
               :api :openai-responses
               :provider :openai
               :model "mock"
               :stop-reason :stop
               :timestamp 2))))
      (cadr-agent:session-branch session root-id)
      (let ((second-leaf-id
              (cadr-agent:session-append-message
               session
               (cadr-ai:make-assistant-message
                :content
                (list (cadr-ai:make-text-content :text "second"))
                :api :openai-responses
                :provider :openai
                :model "mock"
                :stop-reason :stop
                :timestamp 3))))
        (is (equal '("root" "first")
                   (message-texts
                    (cadr-agent:session-messages
                     session first-leaf-id))))
        (is (equal '("root" "second")
                   (message-texts
                     (cadr-agent:session-messages
                      session second-leaf-id))))
        (let ((loaded
                (cadr-agent:load-session
                 (cadr-agent:session-path session))))
          (is (string= second-leaf-id
                       (cadr-agent:session-leaf-id loaded)))
          (is (equal '("root" "first")
                     (message-texts
                      (cadr-agent:session-messages
                       loaded first-leaf-id))))
          (is (equal '("root" "second")
                     (message-texts
                      (cadr-agent:session-messages
                       loaded second-leaf-id))))
          (cadr-agent:session-branch loaded first-leaf-id)
          (let ((continued-id
                  (cadr-agent:session-append-message
                   loaded
                   (cadr-ai:make-user-message
                    :content "continue first" :timestamp 4))))
            (is (equal '("root" "first" "continue first")
                       (message-texts
                        (cadr-agent:session-messages
                         (cadr-agent:load-session
                          (cadr-agent:session-path loaded))
                         continued-id))))))
        (let ((records (parse-json-lines
                        (cadr-agent:session-path session))))
          (is (= 3 (cadr-ai::json-get (first records) "version")))
          (dolist (record (rest records))
            (is (stringp (cadr-ai::json-get record "id")))
            (multiple-value-bind (value present-p)
              (gethash "parentId" record)
              (declare (ignore value))
              (is (eq t present-p)))))))))

(test session-v1-load-migrates-atomically-without-losing-envelope-fields
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((path (merge-pathnames "legacy.jsonl" sessions))
          (canonical (cadr-agent::canonical-session-cwd cwd)))
      (with-open-file
          (stream path
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format stream
                "{\"type\":\"session\",\"version\":1,\"id\":\"legacy\",\"timestamp\":10,\"cwd\":\"~A\",\"future_header\":\"kept\"}~%"
                canonical)
        (format stream
                "{\"type\":\"message\",\"timestamp\":11,\"future_envelope\":{\"x\":7},\"message\":{\"type\":\"user\",\"content\":\"legacy text\",\"timestamp\":11}}~%"))
      (let ((loaded (cadr-agent:load-session path)))
        (is (equal '("legacy text")
                   (message-texts
                    (cadr-agent:session-messages loaded))))
        (let ((records (parse-json-lines path)))
          (is (= 3 (cadr-ai::json-get (first records) "version")))
          (is (string= "kept"
                       (cadr-ai::json-get
                        (first records) "future_header")))
          (is (= 7
                 (cadr-ai::json-get
                  (cadr-ai::json-get
                   (second records) "future_envelope")
                  "x")))
          (is (stringp
               (cadr-ai::json-get (second records) "id")))
          (is (null
               (cadr-ai::json-get
                (second records) "parentId" :missing))))))))

(test session-v2-rejects-duplicate-ids-and-dangling-parents
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (dolist
        (records
         (list
          (list
           "{\"type\":\"message\",\"id\":\"same\",\"parentId\":null,\"timestamp\":1,\"message\":{\"type\":\"user\",\"content\":\"a\",\"timestamp\":1}}"
           "{\"type\":\"message\",\"id\":\"same\",\"parentId\":\"same\",\"timestamp\":2,\"message\":{\"type\":\"user\",\"content\":\"b\",\"timestamp\":2}}")
          (list
           "{\"type\":\"message\",\"id\":\"orphan\",\"parentId\":\"missing\",\"timestamp\":1,\"message\":{\"type\":\"user\",\"content\":\"a\",\"timestamp\":1}}")))
      (let ((path
              (merge-pathnames
               (format nil "bad-~D.jsonl" (random 1000000))
               sessions)))
        (with-open-file
            (stream path
                    :direction :output
                    :if-exists :supersede
                    :if-does-not-exist :create
                    :external-format :utf-8)
          (format stream
                  "{\"type\":\"session\",\"version\":2,\"id\":\"bad\",\"timestamp\":1,\"cwd\":\"~A\"}~%"
                  (cadr-agent::canonical-session-cwd cwd))
          (dolist (record records)
            (format stream "~A~%" record)))
        (signals cadr-agent:session-error
          (cadr-agent:load-session path))))))

(test session-v2-round-trips-image-content
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((session
            (cadr-agent:create-session
             :directory sessions :cwd cwd :id "image")))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content
        (list
         (cadr-ai:make-text-content :text "inspect")
         (cadr-ai:make-image-content
          :mime-type "image/png" :data "YWJj"))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "seen"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (let* ((loaded
               (cadr-agent:load-session
                (cadr-agent:session-path session)))
             (content
               (cadr-ai:user-message-content
                (first (cadr-agent:session-messages loaded)))))
        (is (typep (second content) 'cadr-ai:image-content))
        (is (string= "image/png"
                     (cadr-ai:image-content-mime-type
                      (second content))))
        (is (string= "YWJj"
                     (cadr-ai:image-content-data
                      (second content))))))))

(test session-list-resume-and-html-export-cover-the-entire-tree
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((older
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "older" :timestamp 10))
           (newer
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "newer" :timestamp 20))
           (root-id
             (cadr-agent:session-append-message
              newer
              (cadr-ai:make-user-message
               :content "<script>alert(1)</script>")))
           (old-leaf
             (cadr-agent:session-append-message
              newer
              (cadr-ai:make-user-message :content "left"))))
      (values older)
      (cadr-agent:session-append-message
       older
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "older"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:session-branch newer root-id)
      (cadr-agent:session-append-message
       newer (cadr-ai:make-user-message :content "right"))
      (cadr-agent:session-append-message
       newer
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "right answer"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (let ((listed
              (cadr-agent:list-sessions
               :directory sessions :cwd cwd)))
        (is (equal '("newer" "older")
                   (mapcar #'cadr-agent:session-id listed))))
      (let ((resumed
              (cadr-agent:resume-session
               "newer" :directory sessions)))
        (is (string= "newer" (cadr-agent:session-id resumed)))
        (is (equal '("<script>alert(1)</script>" "left")
                   (message-texts
                    (cadr-agent:session-messages
                     resumed old-leaf)))))
      (let ((html-path (merge-pathnames "tree.html" sessions)))
        (cadr-agent:export-session-html newer html-path)
        (let* ((html
                 (uiop:read-file-string
                  html-path :external-format :utf-8))
               (data
                 (exported-session-data html))
               (serialized
                 (cadr-ai::stringify-json data)))
          (is (search "<!DOCTYPE html>" html))
          (is (not (search "<script>alert(1)</script>" html)))
          (is (search "<script>alert(1)</script>" serialized))
          (is (search "left" serialized))
          (is (search "right" serialized))
          (is (search root-id serialized))
          (is (string=
               (cadr-agent:session-leaf-id newer)
               (cadr-ai::json-get data "leafId")))
          (is (string=
               (cadr-ai::stringify-json
                (cadr-agent::session-header-to-json newer))
               (cadr-ai::stringify-json
                (cadr-ai::json-get data "header"))))
          (is (string=
               (cadr-ai::stringify-json
                (cadr-ai::json-object
                 "header"
                 (cadr-agent::session-header-to-json newer)
                 "entries"
                 (map 'vector
                      #'cadr-agent::session-entry-to-json
                      (cadr-agent:session-entries newer))
                 "leafId"
                 (cadr-agent:session-leaf-id newer)))
               (exported-session-json html))))))))

(test session-html-export-renders-skill-wrapper-as-visible-sibling-blocks
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions
              :cwd cwd
              :id "skill-export"))
           (skill-text
             (format
              nil
              "<skill name=\"review\" location=\"/skills/review/SKILL.md\">~%# Review~%~%<script>bad()</script>~%</skill>~%~%check this diff"))
           (message
             (cadr-ai:make-user-message
              :content
              (list
               (cadr-ai:make-text-content
                :text skill-text)
               (cadr-ai:make-image-content
                :mime-type "image/png"
                :data "AA=="))))
           (path
             (merge-pathnames
              "skill.html" sessions)))
      (cadr-agent:session-append-message
       session message)
      (cadr-agent:export-session-html
       session path)
      (let* ((html
               (uiop:read-file-string
                path :external-format :utf-8))
             (data
               (exported-session-data html))
             (entry
               (aref
                (cadr-ai::json-get data "entries")
                0))
             (content
               (cadr-ai::json-get
                (cadr-ai::json-get entry "message")
                "content")))
        (is (search
             "class=\"skill-invocation\"" html))
        (is (not
             (search "<script>bad()</script>"
                     html)))
        (is (search
             "class=\"user-message\"" html))
        (is (string=
             skill-text
             (cadr-ai::json-get
              (aref content 0) "text")))
        (is (string=
             "AA=="
             (cadr-ai::json-get
              (aref content 1) "data")))
        (is (search
             "tree-role-skill" html))
        (is (search "parseSkillBlock" html))))))

(test session-html-export-vendors-licensed-offline-assets-and-preserves-two-argument-call
  (is (string=
       "d5487edc7258b404bfa74c393d74a6393155f02517bd5e7e77cd64f8187f39a0"
       (export-test-sha256
        cadr-agent::+export-html-marked-js+)))
  (is (string=
       "837a6fa5b0c736b52bbde2b2b6190f305da3fc9ed41681db5321507057b5c846"
       (export-test-sha256
        cadr-agent::+export-html-highlight-js+)))
  (is (string=
       "916782b1184a9597527605ad751e2b3af30fcea23ba2194002969cd217a06881"
       (export-test-sha256
        cadr-agent::+export-html-template+)))
  (is (string=
       "28c16e3827c23a62eef8283cac316b478f946e023093adad25ff9c9b891d41af"
       (export-test-sha256
        cadr-agent::+export-html-template-css+)))
  (is (string=
       "822c3fbcbc907edebf200f52ff06a7f15b126bab5810f989a2acf6352bfe20b8"
       (export-test-sha256
        cadr-agent::+export-html-template-js+)))
  (is (search
       "cadr-share:v1:sidebar-width"
       cadr-agent::+export-html-template-js+))
  (is (not (search
            "pi-share:v1:sidebar-width"
            cadr-agent::+export-html-template-js+)))
  (is (search
       "marked v18.0.5 - a markdown parser"
       cadr-agent::+export-html-marked-js+))
  (is (search
       "Copyright (c) 2018-2026, MarkedJS. (MIT License)"
       cadr-agent::+export-html-marked-js+))
  (is (search
       "Highlight.js v11.9.0 (git: f47103d4f1)"
       cadr-agent::+export-html-highlight-js+))
  (is (search
       "License: BSD-3-Clause"
       cadr-agent::+export-html-highlight-js+))
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "offline-export"))
           (path
             (merge-pathnames "offline.html" sessions)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "offline"))
      (cadr-agent:export-session-html session path)
      (let ((html
              (uiop:read-file-string
               path :external-format :utf-8)))
        (is (search
             "marked v18.0.5 - a markdown parser"
             html))
        (is (search
             "Highlight.js v11.9.0 (git: f47103d4f1)"
             html))
        (is (null
             (cl-ppcre:scan
              "(?i)<script[^>]+src[[:space:]]*=|<link[^>]+href[[:space:]]*=|url[[:space:]]*\\([[:space:]]*['\"]?https?://|(?:fetch|XMLHttpRequest|WebSocket|EventSource|importScripts)[[:space:]]*\\("
              html)))
        (is (search
             "--body-bg: #18181e;"
             html))))))

(test session-html-export-resolves-custom-theme-and-never-rereads-assets
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "custom-theme-export"))
           (path
             (merge-pathnames "custom.html" sessions))
           (theme
             (let ((object
                     (cadr-ai::json-object)))
               (cadr-ai::json-put
                object "vars"
                (cadr-ai::json-object
                 "message" "#204060"
                 "page" "#112233"
                 "card" "#223344"
                 "info" "#334455"))
               (cadr-ai::json-put
                object "colors"
                (cadr-ai::json-object
                 "accent" 24
                 "userMessageBg" "message"))
               (cadr-ai::json-put
                object "export"
                (cadr-ai::json-object
                 "pageBg" "page"
                 "cardBg" "card"
                 "infoBg" "info"))
               object)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "themed"))
      (let ((cadr-agent::*export-html-asset-reader*
              (lambda (relative-path)
                (declare (ignore relative-path))
                (error "runtime asset read"))))
        (cadr-agent:export-session-html
         session path
         :theme-name "custom"
         :theme-object theme))
      (let ((html
              (uiop:read-file-string
               path :external-format :utf-8)))
        (is (search "--accent: #005f87;" html))
        (is (search "--userMessageBg: #204060;" html))
        (is (search "--exportPageBg: #112233;" html))
        (is (search "--exportCardBg: #223344;" html))
        (is (search "--exportInfoBg: #334455;" html))
        (is (search "--body-bg: #112233;" html))
        (is (search "--container-bg: #223344;" html))
        (is (search "--info-bg: #334455;" html))
        (is (null
             (search "var(--info-bg)"
                     cadr-agent::+export-html-template-css+)))))))
