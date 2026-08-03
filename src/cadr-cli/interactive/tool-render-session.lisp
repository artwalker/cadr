(in-package #:cadr-cli)

(defstruct (tool-render-session
            (:constructor make-tool-render-session
                (&key name arguments
                      call-renderer
                      result-renderer)))
  name
  arguments
  call-renderer
  result-renderer
  (state (make-hash-table :test #'equal))
  result
  (pending-p t :type boolean))

(defun update-tool-render-session
    (session result &key pending-p)
  (setf
   (tool-render-session-result session)
   result
   (tool-render-session-pending-p session)
   (not (null pending-p)))
  session)

(defun render-tool-session (session)
  (let ((call
          (if
              (tool-render-session-call-renderer
               session)
              (funcall
               (tool-render-session-call-renderer
                session)
               (tool-render-session-arguments session)
               (tool-render-session-state session))
              (format nil "~A ~S"
                      (tool-render-session-name session)
                      (tool-render-session-arguments
                       session))))
        (result
          (and
           (not
            (tool-render-session-pending-p
             session))
           (tool-render-session-result session)
           (if
               (tool-render-session-result-renderer
                session)
               (funcall
                (tool-render-session-result-renderer
                 session)
                (tool-render-session-result session)
                (tool-render-session-arguments
                 session)
                (tool-render-session-state session))
               (princ-to-string
                (tool-render-session-result
                 session))))))
    (remove
     ""
     (remove nil (list call result))
     :test #'string=)))
