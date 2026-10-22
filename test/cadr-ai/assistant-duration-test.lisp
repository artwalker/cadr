(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun assistant-duration-message (&key (timestamp 0) duration-ms)
  (cadr-ai:make-assistant-message
   :api :faux
   :provider :faux
   :model "faux-1"
   :stop-reason :stop
   :timestamp timestamp
   :duration-ms duration-ms))

(test assistant-stream-times-only-a-message-from-this-stream
  ;; pi@4a080252f event-stream.ts AssistantMessageEventStream.#time
  (let ((cadr-ai::*assistant-stream-started-wall* 1000)
        (cadr-ai::*assistant-stream-started-mono*
          (get-internal-real-time))
        (cadr-ai::*assistant-stream-closed-p* nil)
        (fresh (assistant-duration-message :timestamp 1000))
        (later (assistant-duration-message :timestamp 5000)))
    (cadr-ai::emit-event (lambda (event) (declare (ignore event)))
                         :done fresh)
    (is (integerp (cadr-ai:assistant-message-duration-ms fresh)))
    (is (>= (cadr-ai:assistant-message-duration-ms fresh) 0))
    (cadr-ai::emit-event (lambda (event) (declare (ignore event)))
                         :error later)
    (is (null (cadr-ai:assistant-message-duration-ms later))))
  (let ((cadr-ai::*assistant-stream-started-wall* 1000)
        (cadr-ai::*assistant-stream-started-mono*
          (get-internal-real-time))
        (cadr-ai::*assistant-stream-closed-p* nil)
        (older (assistant-duration-message :timestamp 999)))
    (cadr-ai::emit-event (lambda (event) (declare (ignore event)))
                         :error older)
    (is (null (cadr-ai:assistant-message-duration-ms older))))
  (let ((cadr-ai::*assistant-stream-started-wall* 1000)
        (cadr-ai::*assistant-stream-started-mono*
          (get-internal-real-time))
        (cadr-ai::*assistant-stream-closed-p* nil)
        (kept (assistant-duration-message
               :timestamp 1000 :duration-ms 42)))
    (cadr-ai::emit-event (lambda (event) (declare (ignore event)))
                         :done kept)
    (is (= 42 (cadr-ai:assistant-message-duration-ms kept)))))

(test faux-stream-leaves-an-earlier-message-untimed
  (let ((handle (cadr-ai:make-faux-provider)))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message
       "ok" :timestamp 1)))
    (let ((message
            (cadr-ai:faux-stream
             handle
             (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context)
             (lambda (event) (declare (ignore event))))))
      (is (null (cadr-ai:assistant-message-duration-ms message)))))
  (let ((handle (cadr-ai:make-faux-provider)))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message
       "ok"
       :timestamp most-positive-fixnum
       :stop-reason :error
       :error-message "nope")))
    (let ((message
            (cadr-ai:faux-stream
             handle
             (cadr-ai:faux-get-model handle)
             (cadr-ai:make-context)
             (lambda (event) (declare (ignore event))))))
      (is (eq :error (cadr-ai:assistant-message-stop-reason message)))
      (is (integerp (cadr-ai:assistant-message-duration-ms message)))
      (is (>= (cadr-ai:assistant-message-duration-ms message) 0)))))
