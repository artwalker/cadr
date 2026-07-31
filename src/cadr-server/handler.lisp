(in-package #:cadr-server)

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
       (let* ((id
                (cadr-ai::json-get
                 request "instanceId"))
              (instance
                (supervisor-get-instance
                 supervisor id)))
         (if instance
             (cadr-ai::json-object
              "type" "status_result"
              "ok" t
              "instance"
              (instance-summary-json
               instance))
             (unknown-instance-response
              id))))
      ((string= type "stop")
       (let* ((id
                (cadr-ai::json-get
                 request "instanceId"))
              (instance
                (supervisor-stop-instance
                 supervisor id)))
         (if instance
             (cadr-ai::json-object
              "type" "stop_result"
              "ok" t
              "instanceId" id)
             (unknown-instance-response
              id))))
      ((string= type "rpc")
       (let* ((id
                (cadr-ai::json-get
                 request "instanceId"))
              (response
                (supervisor-handle-rpc
                 supervisor id
                 (cadr-ai::json-get
                  request "command"))))
         (if response
             (cadr-ai::json-object
              "type" "rpc_result"
              "ok" t
              "response" response)
             (unknown-instance-response
              id))))
      ((string= type "rpc_stream")
       (let* ((id
                (cadr-ai::json-get
                 request "instanceId"))
              (instance
                (supervisor-get-instance
                 supervisor id)))
         (if instance
             (cadr-ai::json-object
              "type" "rpc_ready"
              "ok" t
              "instance"
              (instance-summary-json
               instance))
             (unknown-instance-response
              id))))
      (t
       (error-response
        (format nil
                "Unknown request type: ~A"
                type))))))
