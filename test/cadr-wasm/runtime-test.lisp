(in-package #:cadr-wasm/tests)

(in-suite cadr-wasm-suite)

(defun bytes (&rest values)
  (coerce values '(simple-array (unsigned-byte 8) (*))))

(test sha256-of-empty-and-abc-matches-the-published-digests
  (is (string= "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
               (cadr-wasm::sha256-hex (bytes))))
  (is (string= "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
               (cadr-wasm::sha256-hex (bytes 97 98 99)))))

(test quickjs-wasi-bytes-match-the-pinned-digest
  (let ((octets (quickjs-wasm-bytes)))
    (is (= 637405 (length octets)))
    (is (string= (quickjs-wasm-sha256) (cadr-wasm::sha256-hex octets)))))

(test quickjs-imports-are-the-wasi-and-host-functions-from-3-6-2
  (let* ((module (parse-module (quickjs-wasm-bytes)))
         (imports (module-import-list module)))
    (is (equal '(("env" "host_get_timezone_offset" :func)
                 ("env" "host_interrupt" :func)
                 ("env" "host_promise_rejection" :func)
                 ("env" "host_module_normalize" :func)
                 ("env" "host_module_load" :func)
                 ("env" "host_call" :func)
                 ("wasi_snapshot_preview1" "clock_time_get" :func)
                 ("wasi_snapshot_preview1" "fd_close" :func)
                 ("wasi_snapshot_preview1" "fd_fdstat_get" :func)
                 ("wasi_snapshot_preview1" "fd_seek" :func)
                 ("wasi_snapshot_preview1" "fd_write" :func)
                 ("wasi_snapshot_preview1" "random_get" :func))
               imports))))

(test add-function-compiles-to-sbcl-and-the-second-compile-is-cached
  (clear-compile-cache)
  (let* ((wat (bytes
               #x00 #x61 #x73 #x6d #x01 #x00 #x00 #x00
               #x01 #x07 #x01 #x60 #x02 #x7f #x7f #x01 #x7f
               #x03 #x02 #x01 #x00
               #x07 #x07 #x01 #x03 #x61 #x64 #x64 #x00 #x00
               #x0a #x09 #x01 #x07 #x00 #x20 #x00 #x20 #x01 #x6a #x0b))
         (first (ensure-compiled wat))
         (first-cached (last-compile-cached-p))
         (first-time (last-compile-seconds))
         (second (ensure-compiled wat)))
    (is (null first-cached))
    (is (plusp first-time))
    (is (eq first second))
    (is (last-compile-cached-p))
    (is (= 0d0 (last-compile-seconds)))
    (let ((instance (instantiate first nil)))
      (is (equal '(3) (invoke instance "add" 1 2))))))

(test cadr-cli-does-not-load-the-wasm-system
  (let ((text (uiop:read-file-string
               (merge-pathnames "cadr-cli.asd"
                                (asdf:system-source-directory "cadr-wasm")))))
    (is (null (search "cadr-wasm" text)))))

(test quickjs-wasi-import-types-match-preview1
  (let ((module (parse-module (quickjs-wasm-bytes))))
    (flet ((sig (name)
             (let ((item (find name (wasm-module-imports module)
                               :key #'cadr-wasm::wasm-import-name :test #'equal)))
               (list (coerce (sig-params (type-at module (wasm-import-type item))) 'list)
                     (coerce (sig-results (type-at module (wasm-import-type item))) 'list)))))
      (is (equal '((:i32 :i64 :i32) (:i32)) (sig "clock_time_get")))
      (is (equal '((:i32) (:i32)) (sig "fd_close")))
      (is (equal '((:i32 :i32) (:i32)) (sig "fd_fdstat_get")))
      (is (equal '((:i32 :i64 :i32 :i32) (:i32)) (sig "fd_seek")))
      (is (equal '((:i32 :i32 :i32 :i32) (:i32)) (sig "fd_write")))
      (is (equal '((:i32 :i32) (:i32)) (sig "random_get"))))))

(test wasi-shim-matches-quickjs-wasi-3-6-2
  (let* ((module (parse-module
                  (decode-base64
                   "AGFzbQEAAAABJgZgA39+fwF/YAR/f39/AX9gAX8Bf2ACf38Bf2AEf35/fwF/YAAAAtkBBhZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxDmNsb2NrX3RpbWVfZ2V0AAAWd2FzaV9zbmFwc2hvdF9wcmV2aWV3MQhmZF93cml0ZQABFndhc2lfc25hcHNob3RfcHJldmlldzEIZmRfY2xvc2UAAhZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxDWZkX2Zkc3RhdF9nZXQAAxZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxB2ZkX3NlZWsABBZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxCnJhbmRvbV9nZXQAAwMIBwABAgMEAwUFAwEAAQdGCAZtZW1vcnkCAAVjbG9jawAGBXdyaXRlAAcFY2xvc2UACAZmZHN0YXQACQRzZWVrAAoGcmFuZG9tAAsIcHJlcC1pb3YADApQBwoAIAAgASACEAALDAAgACABIAIgAxABCwYAIAAQAgsIACAAIAEQAwsMACAAIAEgAiADEAQLCAAgACABEAULEABBEEEANgIAQRRBAjYCAAsLCAEAQQALAmhp")))
         (imports (make-wasi-imports
                   :clock (lambda () 42)
                   :random-bytes (lambda (count)
                                   (make-array count :element-type '(unsigned-byte 8)
                                               :initial-element 7))
                   :discard-output t))
         (instance (instantiate (compile-module module) imports))
         (memory (aref (wasm-instance-memories instance) 0)))
    (invoke instance "prep-iov")
    (is (equal '(0) (invoke instance "clock" 0 0 100)))
    (is (= 42 (load-le memory 100 0 8)))
    (is (equal '(0) (invoke instance "clock" 1 0 100)))
    (is (equal '(52) (invoke instance "clock" 2 0 100)))
    (is (equal '(0) (invoke instance "write" 1 16 1 200)))
    (is (= 2 (load-le memory 200 0 4)))
    (is (equal '(8) (invoke instance "write" 0 16 1 200)))
    (is (equal '(52) (invoke instance "close" 1)))
    (is (equal '(52) (invoke instance "seek" 1 0 0 200)))
    (is (equal '(0) (invoke instance "fdstat" 1 300)))
    (is (= 2 (aref (wasm-memory-bytes memory) 300)))
    (is (equal '(8) (invoke instance "fdstat" 0 300)))
    (is (equal '(0) (invoke instance "random" 400 4)))
    (is (equalp #(7 7 7 7) (subseq (wasm-memory-bytes memory) 400 404)))))

(defun wasi-nanoseconds ()
  (multiple-value-bind (seconds microseconds) (sb-ext:get-time-of-day)
    (* (+ (* seconds 1000) (floor microseconds 1000)) 1000000)))

(test wasi-defaults-match-quickjs-wasi-3-6-2
  (let* ((module (parse-module
                  (decode-base64
                   "AGFzbQEAAAABJgZgA39+fwF/YAR/f39/AX9gAX8Bf2ACf38Bf2AEf35/fwF/YAAAAtkBBhZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxDmNsb2NrX3RpbWVfZ2V0AAAWd2FzaV9zbmFwc2hvdF9wcmV2aWV3MQhmZF93cml0ZQABFndhc2lfc25hcHNob3RfcHJldmlldzEIZmRfY2xvc2UAAhZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxDWZkX2Zkc3RhdF9nZXQAAxZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxB2ZkX3NlZWsABBZ3YXNpX3NuYXBzaG90X3ByZXZpZXcxCnJhbmRvbV9nZXQAAwMIBwABAgMEAwUFAwEAAQdGCAZtZW1vcnkCAAVjbG9jawAGBXdyaXRlAAcFY2xvc2UACAZmZHN0YXQACQRzZWVrAAoGcmFuZG9tAAsIcHJlcC1pb3YADApQBwoAIAAgASACEAALDAAgACABIAIgAxABCwYAIAAQAgsIACAAIAEQAwsMACAAIAEgAiADEAQLCAAgACABEAULEABBEEEANgIAQRRBAjYCAAsLCAEAQQALAmhp")))
         (before (wasi-nanoseconds))
         (instance (instantiate (compile-module module) (make-wasi-imports)))
         (memory (aref (wasm-instance-memories instance) 0))
         (bytes (wasm-memory-bytes memory)))
    (invoke instance "prep-iov")
    (is (equal '(0) (invoke instance "clock" 0 0 100)))
    (let ((realtime (load-le memory 100 0 8))
          (after (wasi-nanoseconds)))
      (is (<= before realtime after))
      (is (zerop (mod realtime 1000000))))
    (is (equal '(0) (invoke instance "clock" 1 0 100)))
    (let ((monotonic (load-le memory 100 0 8))
          (after (wasi-nanoseconds)))
      (is (<= before monotonic after))
      (is (zerop (mod monotonic 1000000))))
    (let* ((pointer (load-le memory 16 0 4))
           (text (with-output-to-string (*standard-output*)
                   (setf (aref bytes pointer) #xc3
                         (aref bytes (1+ pointer)) #xa9)
                   (invoke instance "write" 1 16 1 200))))
      (is (= 1 (length text)))
      (is (= 233 (char-code (char text 0))))
      (is (= 2 (load-le memory 200 0 4))))
    (let* ((seed (make-array 8 :element-type '(unsigned-byte 8) :initial-element 1))
           (predicted (let ((*random-state* (sb-ext:seed-random-state seed)))
                        (let ((out (make-array 8 :element-type '(unsigned-byte 8))))
                          (dotimes (index 8 out)
                            (setf (aref out index) (random 256)))))))
      (let ((*random-state* (sb-ext:seed-random-state seed)))
        (is (equal '(0) (invoke instance "random" 400 8)))
        (is (not (equalp predicted (subseq bytes 400 408))))))))

(test translated-add-round-trips-into-the-file-compiler
  (let* ((wat (bytes
               #x00 #x61 #x73 #x6d #x01 #x00 #x00 #x00
               #x01 #x07 #x01 #x60 #x02 #x7f #x7f #x01 #x7f
               #x03 #x02 #x01 #x00
               #x07 #x07 #x01 #x03 #x61 #x64 #x64 #x00 #x00
               #x0a #x09 #x01 #x07 #x00 #x20 #x00 #x20 #x01 #x6a #x0b))
         (module (parse-module wat))
         (code (aref (cadr-wasm::wasm-module-codes module) 0))
         (form (cadr-wasm::translate-function
                module
                (aref (cadr-wasm::collect-sigs module) 0)
                (cadr-wasm::wasm-code-locals code)
                (cadr-wasm::wasm-code-body code)))
         (text (with-output-to-string (stream)
                 (let ((*print-circle* t)
                       (*print-gensym* t)
                       (*print-length* nil)
                       (*print-level* nil)
                       (*package* (find-package "CADR-WASM")))
                   (prin1 form stream))))
         (restored (let ((*package* (find-package "CADR-WASM"))
                         (*read-eval* nil))
                     (read-from-string text)))
         (function (handler-bind ((style-warning #'muffle-warning))
                     (compile nil restored))))
    (is (equal '(3) (multiple-value-list (funcall function 1 2))))))
