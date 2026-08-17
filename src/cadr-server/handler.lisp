(in-package #:cadr-server)

(defun handle-instance-request
    (supervisor request fetch succeed)
  ;; Missing-instance is one policy. Four arms copied
  ;; extract+if+unknown so a new instance-id verb was a
  ;; fourth owner of that miss.
  (let* ((id
           (cadr-ai::json-get
            request "instanceId"))
         (found (funcall fetch supervisor id)))
    (if found
        (funcall succeed id found)
        (unknown-instance-response id))))

(defun handle-server-request
    (supervisor request)
  (let ((type
          (cadr-ai::json-get
           request "type")))
    (cond
      ((string= type "spawn")
       (let ((instance
               (supervisor-spawn-instance
                supervisor
                :cwd
                (cadr-ai::json-get
                 request "cwd")
                :label
                (cadr-ai::json-get
                 request "label"))))
         (cadr-ai::json-object
          "type" "spawn_result"
          "ok" t
          "instance"
          (instance-summary-json
           instance))))
      ((string= type "list")
       (cadr-ai::json-object
        "type" "list_result"
        "ok" t
        "instances"
        (cadr-ai::list-json-array
         (mapcar
          #'instance-summary-json
          (supervisor-list-instances
           supervisor)))))
      ((string= type "status")
       (handle-instance-request
        supervisor request
        #'supervisor-get-instance
        (lambda (id instance)
          (declare (ignore id))
          (cadr-ai::json-object
           "type" "status_result"
           "ok" t
           "instance"
           (instance-summary-json
            instance)))))
      ((string= type "stop")
       (handle-instance-request
        supervisor request
        #'supervisor-stop-instance
        (lambda (id instance)
          (declare (ignore instance))
          (cadr-ai::json-object
           "type" "stop_result"
           "ok" t
           "instanceId" id))))
      ((string= type "rpc")
       (handle-instance-request
        supervisor request
        (lambda (supervisor id)
          (supervisor-handle-rpc
           supervisor id
           (cadr-ai::json-get
            request "command")))
        (lambda (id response)
          (declare (ignore id))
          (cadr-ai::json-object
           "type" "rpc_result"
           "ok" t
           "response" response))))
      ((string= type "rpc_stream")
       (handle-instance-request
        supervisor request
        #'supervisor-get-instance
        (lambda (id instance)
          (declare (ignore id))
          (cadr-ai::json-object
           "type" "rpc_ready"
           "ok" t
           "instance"
           (instance-summary-json
            instance)))))
      (t
       (error-response
        (format nil
                "Unknown request type: ~A"
                type))))))
