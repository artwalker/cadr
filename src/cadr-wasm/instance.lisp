(in-package #:cadr-wasm)

(defun extern-key (module name) (cons module name))

(defun find-import (imports module name)
  (and imports (gethash (extern-key module name) imports)))

(defun sig-equal (left right)
  (and (equalp (sig-params left) (sig-params right))
       (equalp (sig-results left) (sig-results right))))

(defun limits-compatible (actual-min actual-max declared-min declared-max)
  (and (>= actual-min declared-min)
       (or (null declared-max)
           (and actual-max (<= actual-max declared-max)))))

(defun unlinkable (message)
  (wasm-fail 'wasm-unlinkable message))

(defun match-import (module expected provided)
  (unless provided
    (unlinkable (format nil "unknown import \"~A\" \"~A\""
                        (wasm-import-module expected)
                        (wasm-import-name expected))))
  (unless (eq (wasm-extern-kind provided) (wasm-import-kind expected))
    (unlinkable (format nil "incompatible import type for \"~A\" \"~A\""
                        (wasm-import-module expected)
                        (wasm-import-name expected))))
  (case (wasm-import-kind expected)
    (:func
     (unless (sig-equal (wasm-extern-type provided)
                        (type-at module (wasm-import-type expected)))
       (unlinkable "incompatible import type")))
    (:global
     (unless (equalp (wasm-extern-type provided) (wasm-import-type expected))
       (unlinkable "incompatible import type")))
    (:memory
     (let ((actual (memory-type-of (wasm-extern-value provided)))
           (declared (wasm-import-type expected)))
       (unless (limits-compatible (wasm-memory-type-min actual)
                                  (wasm-memory-type-max actual)
                                  (wasm-memory-type-min declared)
                                  (wasm-memory-type-max declared))
         (unlinkable "incompatible import type"))))
    (:table
     (let ((actual (table-type-of (wasm-extern-value provided)))
           (declared (wasm-import-type expected)))
       (unless (and (eq (wasm-table-type-element actual)
                        (wasm-table-type-element declared))
                    (limits-compatible (wasm-table-type-min actual)
                                       (wasm-table-type-max actual)
                                       (wasm-table-type-min declared)
                                       (wasm-table-type-max declared)))
         (unlinkable "incompatible import type"))))))

(defun make-memory (type)
  (make-wasm-memory
   :bytes (make-array (* (wasm-memory-type-min type) +page-size+)
                      :element-type '(unsigned-byte 8)
                      :initial-element 0)
   :min (wasm-memory-type-min type)
   :max (wasm-memory-type-max type)))

(defun make-table (type)
  (make-wasm-table
   :elements (make-array (wasm-table-type-min type)
                         :initial-element (default-for (wasm-table-type-element type)))
   :type (wasm-table-type-element type)
   :min (wasm-table-type-min type)
   :max (wasm-table-type-max type)))

(defun memory-type-of (memory)
  (make-wasm-memory-type :min (floor (length (wasm-memory-bytes memory)) +page-size+)
                         :max (wasm-memory-max memory)))

(defun table-type-of (table)
  (make-wasm-table-type :element (wasm-table-type table)
                        :min (length (wasm-table-elements table))
                        :max (wasm-table-max table)))

(defun eval-const (instance expr)
  (let ((stack nil))
    (loop for item across expr do
      (case (instr-op item)
        (:i32.const (push (i32 (instr-a item)) stack))
        (:i64.const (push (i64 (instr-a item)) stack))
        (:f32.const (push (instr-a item) stack))
        (:f64.const (push (instr-a item) stack))
        (:ref.func (push (make-wasm-funcref :instance instance :index (instr-a item)) stack))
        (:ref.null (push (if (eq (instr-a item) :funcref) +null-funcref+ +null-externref+) stack))
        (:global.get
         (push (wasm-gcell-value (aref (wasm-instance-globals instance) (instr-a item))) stack))
        (:end)))
    (car stack)))

(defun init-active-data (instance)
  (loop for data across (wasm-instance-datas instance)
        for def across (wasm-module-datas (wasm-instance-module instance))
        when (eq (wasm-data-mode def) :active)
          do (let ((offset (eval-const instance (wasm-data-offset def))))
               (memory-init (aref (wasm-instance-memories instance) 0)
                            (wasm-seg-items data) offset 0
                            (length (wasm-seg-items data)))
               (drop-seg data))))

(defun init-active-elem (instance)
  (loop for elem across (wasm-instance-elems instance)
        for def across (wasm-module-elems (wasm-instance-module instance))
        do (case (wasm-elem-mode def)
             (:active
              (let ((offset (eval-const instance (wasm-elem-offset def)))
                    (values (map 'vector (lambda (init) (eval-const instance init))
                                 (wasm-elem-inits def))))
                (table-init (aref (wasm-instance-tables instance) (wasm-elem-table def))
                            values offset 0 (length values))
                (drop-seg elem)
                (setf (wasm-seg-items elem) (make-array 0))))
             (:declarative
              (drop-seg elem)
              (setf (wasm-seg-items elem) (make-array 0))))))

(defun indirect-callee (instance table-index type-index raw-index)
  "One signature check. The caller funcalls the function with a known arity."
  (let* ((index (i32 raw-index))
         (table (aref (wasm-instance-tables instance) table-index))
         (elements (wasm-table-elements table)))
    (declare (type simple-vector elements))
    (unless (< index (length elements))
      (wasm-trap (format nil "undefined element ~A" index)))
    (let ((value (aref elements index)))
      (unless (wasm-funcref-p value)
        (wasm-trap (format nil "uninitialized element ~A" index)))
      (let* ((owner (wasm-funcref-instance value))
             (func-index (wasm-funcref-index value))
             (actual (aref (wasm-instance-func-types owner) func-index))
             (expected (aref (wasm-module-types (wasm-instance-module instance)) type-index)))
        (unless (sig-equal actual expected)
          (wasm-trap "indirect call type mismatch"))
        (values (aref (wasm-instance-funcs owner) func-index) owner)))))

(defun compile-module (input)
  (let ((module (if (wasm-module-p input) input (parse-module input))))
    (validate-module module)
    (let* ((imports (count :func (wasm-module-imports module) :key #'wasm-import-kind))
           (sigs (collect-sigs module))
           (funcs (make-array (length (wasm-module-codes module)))))
      (loop for code across (wasm-module-codes module)
            for index from 0
            do (setf (aref funcs index)
                     (compile-function module (aref sigs (+ imports index))
                                       (wasm-code-locals code)
                                       (wasm-code-body code))))
      (make-compiled-module :module module :funcs funcs))))

(defun instantiate (compiled imports)
  (let* ((module (compiled-module-module compiled))
         (func-imports nil)
         (table-imports nil)
         (memory-imports nil)
         (global-imports nil))
    (loop for item across (wasm-module-imports module) do
      (let ((provided (find-import imports (wasm-import-module item) (wasm-import-name item))))
        (match-import module item provided)
        (case (wasm-import-kind item)
          (:func (setf func-imports (nconc func-imports (list provided))))
          (:table (setf table-imports (nconc table-imports (list provided))))
          (:memory (setf memory-imports (nconc memory-imports (list provided))))
          (:global (setf global-imports
                         (nconc global-imports
                                (list (cons provided
                                            (car (wasm-import-type item))))))))))
    (let* ((funcs (make-array (+ (length func-imports) (length (compiled-module-funcs compiled)))))
           (func-types (collect-sigs module))
           (tables (make-array (+ (length table-imports) (length (wasm-module-tables module)))))
           (memories (make-array (+ (length memory-imports) (length (wasm-module-memories module)))))
           (globals (make-array (+ (length global-imports) (length (wasm-module-globals module)))))
           (elems (make-array (length (wasm-module-elems module))))
           (datas (map 'vector (lambda (data)
                                 (make-wasm-seg :items (wasm-data-bytes data)))
                       (wasm-module-datas module)))
           (instance (make-wasm-instance :module module :funcs funcs :func-types func-types
                                         :tables tables :memories memories :globals globals
                                         :elems elems :datas datas)))
      (loop for provided in func-imports for index from 0 do
        (let ((fn (wasm-extern-value provided))
              (owner (wasm-extern-instance provided))
              (sig (aref func-types index)))
          (setf (aref funcs index)
                (cond (owner (adapt-cross-instance fn owner sig))
                      ((host-adapt-p sig) (adapt-host-function fn sig))
                      (t fn)))))
      (loop for fn across (compiled-module-funcs compiled) for index from (length func-imports) do
        (setf (aref funcs index) fn))
      (loop for provided in table-imports for index from 0 do
        (setf (aref tables index) (wasm-extern-value provided)))
      (loop for type across (wasm-module-tables module)
            for index from (length table-imports)
            do (setf (aref tables index) (make-table type)))
      (loop for provided in memory-imports for index from 0 do
        (setf (aref memories index) (wasm-extern-value provided)))
      (loop for type across (wasm-module-memories module)
            for index from (length memory-imports)
            do (setf (aref memories index) (make-memory type)))
      (loop for (provided . type) in global-imports for index from 0 do
        (let ((cell (wasm-extern-value provided)))
          (gcell-store cell type (wasm-gcell-value cell))
          (setf (aref globals index) cell)))
      (loop for def across (wasm-module-globals module)
            for index from (length global-imports)
            do (setf (aref globals index)
                     (let ((cell (make-wasm-gcell)))
                       (gcell-store cell (wasm-global-def-type def)
                                    (eval-const instance (wasm-global-def-init def)))
                       cell)))
      (loop for def across (wasm-module-elems module)
            for index from 0
            do (setf (aref elems index)
                     (make-wasm-seg :items (map 'vector
                                                (lambda (init) (eval-const instance init))
                                                (wasm-elem-inits def)))))
      (let ((*wasm-instance* instance))
        (init-active-elem instance)
        (init-active-data instance)
        (when (wasm-module-start module)
          (sb-int:with-float-traps-masked (:invalid :overflow :divide-by-zero :underflow :inexact)
            (let ((*wasm-depth* 0))
              (funcall (aref funcs (wasm-module-start module)))))))
      instance)))

(defun global-type-at (module index)
  (let ((imports (loop for item across (wasm-module-imports module)
                       when (eq (wasm-import-kind item) :global)
                         collect (wasm-import-type item))))
    (if (< index (length imports))
        (nth index imports)
        (let ((def (aref (wasm-module-globals module) (- index (length imports)))))
          (cons (wasm-global-def-type def) (wasm-global-def-mutable def))))))

(defun export-index (instance name kind)
  (loop for item across (wasm-module-exports (wasm-instance-module instance))
        when (and (equal (wasm-export-name item) name)
                  (eq (wasm-export-kind item) kind))
          return (wasm-export-index item)))

(defun get-export (instance name)
  (let ((item (find name (wasm-module-exports (wasm-instance-module instance))
                    :key #'wasm-export-name :test #'equal)))
    (unless item (unlinkable (format nil "unknown export ~A" name)))
    (case (wasm-export-kind item)
      (:func (make-wasm-extern :kind :func
                               :value (aref (wasm-instance-funcs instance) (wasm-export-index item))
                               :type (aref (wasm-instance-func-types instance)
                                           (wasm-export-index item))
                               :instance instance))
      (:global (make-wasm-extern :kind :global
                                 :value (aref (wasm-instance-globals instance)
                                              (wasm-export-index item))
                                 :type (global-type-at (wasm-instance-module instance)
                                                       (wasm-export-index item))))
      (:memory (let ((memory (aref (wasm-instance-memories instance) (wasm-export-index item))))
                 (make-wasm-extern :kind :memory :value memory :type (memory-type-of memory))))
      (:table (let ((table (aref (wasm-instance-tables instance) (wasm-export-index item))))
                (make-wasm-extern :kind :table :value table :type (table-type-of table)))))))

(defun spec-to-lisp-args (types args)
  (loop for type across types
        for arg in args
        nconc (ecase type
                (:i64 (list (ldb (byte 32 0) arg)
                            (ldb (byte 32 32) (i64 arg))))
                (:i32 (list (ldb (byte 32 0) arg)))
                (:f32 (list (bits-to-f32 arg)))
                (:f64 (list (bits-to-f64 arg)))
                ((:funcref :externref) (list arg)))))

(defun lisp-to-spec-results (types values)
  (let ((rest values))
    (loop for type across types
          collect (ecase type
                    (:i64 (logior (pop rest) (ash (pop rest) 32)))
                    (:i32 (pop rest))
                    (:f32 (f32-to-bits (pop rest)))
                    (:f64 (f64-to-bits (pop rest)))
                    ((:funcref :externref) (pop rest))))))

(defun host-adapt-p (sig)
  (flet ((splitp (types)
           (find-if (lambda (type) (member type '(:i64 :f32 :f64))) types)))
    (or (splitp (sig-params sig)) (splitp (sig-results sig)))))

(defun adapt-host-function (fn sig)
  "Host imports still take one integer per wasm value. Compiled code passes halves."
  (let* ((results (coerce (sig-results sig) 'list))
         (groups (param-groups (sig-params sig)))
         (vars (group-vars groups))
         (spec-vars (loop for type in results collect (gensym "R")))
         (packed (let ((rest vars))
                   (loop for type in (coerce (sig-params sig) 'list)
                         collect (ecase type
                                   (:i64 (let ((lo (pop rest)) (hi (pop rest)))
                                           (i64-join-form lo hi)))
                                   (:i32 `(ldb (byte 32 0) ,(pop rest)))
                                   (:f32 (f32-to-bits-form (pop rest)))
                                   (:f64 (f64-to-bits-form (pop rest)))
                                   ((:funcref :externref) (pop rest))))))
         (unpacked (let ((rest spec-vars))
                     (loop for type in results
                           nconc (ecase type
                                   (:i64 (let ((n (pop rest)))
                                           `((ldb (byte 32 0) ,n)
                                             (ldb (byte 32 32) ,n))))
                                   (:i32 (list (pop rest)))
                                   (:f32 (list (f32-from-bits-form (pop rest))))
                                   (:f64 (list (f64-from-bits-form (pop rest))))
                                   ((:funcref :externref) (list (pop rest))))))))
    (compile nil
             `(lambda ,vars
                (declare (optimize (speed 3) (safety 0) (debug 0))
                         (ignorable ,@vars))
                ,(if results
                     `(multiple-value-bind ,spec-vars
                          (funcall ,fn ,@packed)
                        (values ,@unpacked))
                     `(funcall ,fn ,@packed))))))

(defun adapt-cross-instance (fn owner sig)
  (let* ((groups (param-groups (sig-params sig)))
         (vars (group-vars groups)))
    (compile nil
             `(lambda ,vars
                (declare (optimize (speed 3) (safety 0) (debug 0))
                         (ignorable ,@vars))
                (let ((*wasm-instance* ,owner))
                  (funcall (the function ,fn) ,@vars))))))

(defun invoke (instance name &rest args)
  (let ((extern (get-export instance name)))
    (unless (eq (wasm-extern-kind extern) :func)
      (wasm-trap "indirect call type mismatch"))
    (sb-int:with-float-traps-masked (:invalid :overflow :divide-by-zero :underflow :inexact)
      (let ((*wasm-instance* instance)
            (*wasm-depth* 0)
            (sig (wasm-extern-type extern)))
        (lisp-to-spec-results
         (sig-results sig)
         (multiple-value-list
          (apply (wasm-extern-value extern)
                 (spec-to-lisp-args (sig-params sig) args))))))))

(defun global-value (instance name)
  (let* ((extern (get-export instance name))
         (cell (wasm-extern-value extern))
         (type (car (wasm-extern-type extern))))
    (case type
      ((:i64 :f64) (logior (wasm-gcell-lo cell) (ash (wasm-gcell-hi cell) 32)))
      ((:i32 :f32) (wasm-gcell-lo cell))
      (t (wasm-gcell-value cell)))))
