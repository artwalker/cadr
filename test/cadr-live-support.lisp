(defpackage #:cadr-live-test-support
  (:use #:cl)
  (:export
   #:prepare-openai-codex-credential))

(in-package #:cadr-live-test-support)

(defun credential-expiring-p (credential)
  (<= (cadr-ai:oauth-credential-expires credential)
      (+ (cadr-ai::unix-milliseconds) 300000)))

(defun prepare-openai-codex-credential
    (&optional
       (path (cadr-cli:default-auth-path))
       (refresh-function
         #'cadr-ai:refresh-openai-oauth-credential))
  (unless (probe-file path)
    (return-from prepare-openai-codex-credential nil))
  (let ((credential
          (cadr-cli:auth-storage-modify
           (cadr-cli:make-file-auth-storage path)
           :openai-codex
           (lambda (current)
             (when
                 (and
                  (typep current
                         'cadr-ai:oauth-credential)
                  (credential-expiring-p current))
               (let ((refreshed
                       (funcall refresh-function
                                current)))
                 (unless
                     (typep refreshed
                            'cadr-ai:oauth-credential)
                   (error
                    "OpenAI Codex OAuth refresh returned an invalid credential"))
                 refreshed))))))
    (and
     (typep credential
            'cadr-ai:oauth-credential)
     credential)))
