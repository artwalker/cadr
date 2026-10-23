(in-package #:cadr-wasm)

(defstruct wbin bytes (pos 0) (limit 0))

(defun open-wbin (octets)
  (let ((bytes (coerce octets '(simple-array (unsigned-byte 8) (*)))))
    (make-wbin :bytes bytes :pos 0 :limit (length bytes))))

(defun wbin-eof (bin) (>= (wbin-pos bin) (wbin-limit bin)))

(defun peek-u8 (bin)
  (if (wbin-eof bin) nil (aref (wbin-bytes bin) (wbin-pos bin))))

(defun read-u8 (bin)
  (when (wbin-eof bin)
    (wasm-fail 'wasm-malformed "unexpected end of section or function"))
  (prog1 (aref (wbin-bytes bin) (wbin-pos bin))
    (incf (wbin-pos bin))))

(defun read-leb (bin signed width)
  (let ((result 0) (shift 0))
    (loop
      (when (<= width 0)
        (wasm-fail 'wasm-malformed "integer representation too long"))
      (let ((byte (read-u8 bin)))
        (when (and (< width 7)
                   (not (if signed
                            (let ((mask (logand (ash -1 (1- width)) #x7f)))
                              (or (zerop (logand byte mask))
                                  (= (logand byte mask) mask)))
                            (< (logand byte #x7f) (ash 1 width)))))
          (wasm-fail 'wasm-malformed "integer too large"))
        (setf result (logior result (ash (logand byte #x7f) shift)))
        (incf shift 7)
        (decf width 7)
        (when (zerop (logand byte #x80))
          (return (if (and signed (logbitp 6 byte))
                      (logior result (ash -1 shift))
                      result)))))))

(defun read-u32 (bin) (logand (read-leb bin nil 32) #xffffffff))
(defun read-s32 (bin) (read-leb bin t 32))
(defun read-s64 (bin) (read-leb bin t 64))
(defun read-s7 (bin) (read-leb bin t 7))
(defun read-s33 (bin) (read-leb bin t 33))
(defun read-u1 (bin) (read-leb bin nil 1))

(defun read-len32 (bin)
  (let ((mark (wbin-pos bin))
        (n (read-u32 bin)))
    (if (<= n (- (wbin-limit bin) mark))
        n
        (wasm-fail 'wasm-malformed "length out of bounds"))))

(defun read-bytes (bin count)
  (let ((out (make-array count :element-type '(unsigned-byte 8))))
    (dotimes (i count out)
      (setf (aref out i) (read-u8 bin)))))

(defun read-vec (bin reader)
  (let* ((count (read-len32 bin))
         (out (make-array count)))
    (dotimes (i count out)
      (setf (aref out i) (funcall reader bin)))))

(defun expect-byte (bin value message)
  (unless (= (read-u8 bin) value)
    (wasm-fail 'wasm-malformed message)))

(defun read-f32-bits (bin)
  (logior (read-u8 bin) (ash (read-u8 bin) 8)
          (ash (read-u8 bin) 16) (ash (read-u8 bin) 24)))

(defun read-f64-bits (bin)
  (logior (read-u32-raw bin) (ash (read-u32-raw bin) 32)))

(defun read-u32-raw (bin)
  (logior (read-u8 bin) (ash (read-u8 bin) 8)
          (ash (read-u8 bin) 16) (ash (read-u8 bin) 24)))

(defun utf8-code (octets index width minimum)
  (when (> (+ index width) (length octets))
    (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
  (let ((code (logand (aref octets index) (1- (ash 1 (- 8 width))))))
    (loop for i from 1 below width do
      (let ((next (aref octets (+ index i))))
        (unless (= (ldb (byte 2 6) next) 2)
          (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
        (setf code (logior (ash code 6) (logand next #x3f)))))
    (when (or (< code minimum) (> code #x10ffff) (<= #xd800 code #xdfff))
      (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
    code))

(defun read-utf8 (bin)
  (let* ((octets (read-bytes bin (read-len32 bin)))
         (index 0)
         (chars (make-array (length octets) :element-type 'character :fill-pointer 0)))
    (loop while (< index (length octets)) do
      (let ((lead (aref octets index)))
        (multiple-value-bind (code width)
            (cond ((< lead #x80) (values lead 1))
                  ((< lead #xc0)
                   (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                  ((< lead #xe0) (values (utf8-code octets index 2 #x80) 2))
                  ((< lead #xf0) (values (utf8-code octets index 3 #x800) 3))
                  ((< lead #xf8) (values (utf8-code octets index 4 #x10000) 4))
                  (t (wasm-fail 'wasm-malformed "malformed UTF-8 encoding")))
          (vector-push (code-char code) chars)
          (incf index width))))
    (coerce chars 'string)))

(defun read-valtype (bin)
  (let ((code (read-s7 bin)))
    (case code
      (-1 :i32) (-2 :i64) (-3 :f32) (-4 :f64) (-5 :v128)
      (-16 :funcref) (-17 :externref)
      (t (wasm-fail 'wasm-malformed "malformed reference type")))))

(defun read-reftype (bin)
  (let ((type (read-valtype bin)))
    (unless (member type '(:funcref :externref))
      (wasm-fail 'wasm-malformed "malformed reference type"))
    type))

(defun read-block-type (bin)
  (let ((mark (wbin-pos bin)))
    (handler-case
        (let ((index (read-s33 bin)))
          (if (>= index 0)
              (cons :index index)
              (progn (setf (wbin-pos bin) mark) (read-block-value bin))))
      (wasm-malformed ()
        (setf (wbin-pos bin) mark)
        (read-block-value bin)))))

(defun read-block-value (bin)
  (let ((mark (wbin-pos bin)))
    (handler-case
        (progn (expect-byte bin #x40 "END opcode expected") :empty)
      (wasm-malformed ()
        (setf (wbin-pos bin) mark)
        (cons :val (read-valtype bin))))))

(defun read-memop (bin)
  (let ((align (read-u32 bin)))
    (when (>= align 32)
      (wasm-fail 'wasm-malformed "malformed memop flags"))
    (values align (read-u32 bin))))

(defparameter *plain-opcodes*
  (let ((table (make-array 256 :initial-element nil)))
    (loop for (byte op) in
          '((#x00 :unreachable) (#x01 :nop) (#x0f :return)
            (#x1a :drop) (#x1b :select) (#x45 :i32.eqz) (#x46 :i32.eq)
            (#x47 :i32.ne) (#x48 :i32.lt-s) (#x49 :i32.lt-u) (#x4a :i32.gt-s)
            (#x4b :i32.gt-u) (#x4c :i32.le-s) (#x4d :i32.le-u) (#x4e :i32.ge-s)
            (#x4f :i32.ge-u) (#x50 :i64.eqz) (#x51 :i64.eq) (#x52 :i64.ne)
            (#x53 :i64.lt-s) (#x54 :i64.lt-u) (#x55 :i64.gt-s) (#x56 :i64.gt-u)
            (#x57 :i64.le-s) (#x58 :i64.le-u) (#x59 :i64.ge-s) (#x5a :i64.ge-u)
            (#x5b :f32.eq) (#x5c :f32.ne) (#x5d :f32.lt) (#x5e :f32.gt)
            (#x5f :f32.le) (#x60 :f32.ge) (#x61 :f64.eq) (#x62 :f64.ne)
            (#x63 :f64.lt) (#x64 :f64.gt) (#x65 :f64.le) (#x66 :f64.ge)
            (#x67 :i32.clz) (#x68 :i32.ctz) (#x69 :i32.popcnt) (#x6a :i32.add)
            (#x6b :i32.sub) (#x6c :i32.mul) (#x6d :i32.div-s) (#x6e :i32.div-u)
            (#x6f :i32.rem-s) (#x70 :i32.rem-u) (#x71 :i32.and) (#x72 :i32.or)
            (#x73 :i32.xor) (#x74 :i32.shl) (#x75 :i32.shr-s) (#x76 :i32.shr-u)
            (#x77 :i32.rotl) (#x78 :i32.rotr) (#x79 :i64.clz) (#x7a :i64.ctz)
            (#x7b :i64.popcnt) (#x7c :i64.add) (#x7d :i64.sub) (#x7e :i64.mul)
            (#x7f :i64.div-s) (#x80 :i64.div-u) (#x81 :i64.rem-s) (#x82 :i64.rem-u)
            (#x83 :i64.and) (#x84 :i64.or) (#x85 :i64.xor) (#x86 :i64.shl)
            (#x87 :i64.shr-s) (#x88 :i64.shr-u) (#x89 :i64.rotl) (#x8a :i64.rotr)
            (#x8b :f32.abs) (#x8c :f32.neg) (#x8d :f32.ceil) (#x8e :f32.floor)
            (#x8f :f32.trunc) (#x90 :f32.nearest) (#x91 :f32.sqrt) (#x92 :f32.add)
            (#x93 :f32.sub) (#x94 :f32.mul) (#x95 :f32.div) (#x96 :f32.min)
            (#x97 :f32.max) (#x98 :f32.copysign) (#x99 :f64.abs) (#x9a :f64.neg)
            (#x9b :f64.ceil) (#x9c :f64.floor) (#x9d :f64.trunc) (#x9e :f64.nearest)
            (#x9f :f64.sqrt) (#xa0 :f64.add) (#xa1 :f64.sub) (#xa2 :f64.mul)
            (#xa3 :f64.div) (#xa4 :f64.min) (#xa5 :f64.max) (#xa6 :f64.copysign)
            (#xa7 :i32.wrap-i64) (#xa8 :i32.trunc-f32-s) (#xa9 :i32.trunc-f32-u)
            (#xaa :i32.trunc-f64-s) (#xab :i32.trunc-f64-u) (#xac :i64.extend-i32-s)
            (#xad :i64.extend-i32-u) (#xae :i64.trunc-f32-s) (#xaf :i64.trunc-f32-u)
            (#xb0 :i64.trunc-f64-s) (#xb1 :i64.trunc-f64-u) (#xb2 :f32.convert-i32-s)
            (#xb3 :f32.convert-i32-u) (#xb4 :f32.convert-i64-s) (#xb5 :f32.convert-i64-u)
            (#xb6 :f32.demote-f64) (#xb7 :f64.convert-i32-s) (#xb8 :f64.convert-i32-u)
            (#xb9 :f64.convert-i64-s) (#xba :f64.convert-i64-u) (#xbb :f64.promote-f32)
            (#xbc :i32.reinterpret-f32) (#xbd :i64.reinterpret-f64)
            (#xbe :f32.reinterpret-i32) (#xbf :f64.reinterpret-i64)
            (#xc0 :i32.extend8-s) (#xc1 :i32.extend16-s) (#xc2 :i64.extend8-s)
            (#xc3 :i64.extend16-s) (#xc4 :i64.extend32-s) (#xd1 :ref.is-null))
          do (setf (aref table byte) op))
    table))

(defun read-prefix (bin)
  (case (read-u32 bin)
    (0 (instr :i32.trunc-sat-f32-s))
    (1 (instr :i32.trunc-sat-f32-u))
    (2 (instr :i32.trunc-sat-f64-s))
    (3 (instr :i32.trunc-sat-f64-u))
    (4 (instr :i64.trunc-sat-f32-s))
    (5 (instr :i64.trunc-sat-f32-u))
    (6 (instr :i64.trunc-sat-f64-s))
    (7 (instr :i64.trunc-sat-f64-u))
    (8 (prog1 (instr :memory.init (read-u32 bin))
         (expect-byte bin 0 "zero byte expected")))
    (9 (instr :data.drop (read-u32 bin)))
    (10 (expect-byte bin 0 "zero byte expected")
     (expect-byte bin 0 "zero byte expected")
     (instr :memory.copy))
    (11 (expect-byte bin 0 "zero byte expected")
     (instr :memory.fill))
    (12 (let* ((elem (read-u32 bin)) (table (read-u32 bin)))
          (instr :table.init table elem)))
    (13 (instr :elem.drop (read-u32 bin)))
    (14 (instr :table.copy (read-u32 bin) (read-u32 bin)))
    (15 (instr :table.grow (read-u32 bin)))
    (16 (instr :table.size (read-u32 bin)))
    (17 (instr :table.fill (read-u32 bin)))
    (t (wasm-fail 'wasm-malformed "illegal opcode"))))

(defun read-instr (bin)
  (let ((byte (read-u8 bin)))
    (case byte
      (#x02 (instr :block (read-block-type bin)))
      (#x03 (instr :loop (read-block-type bin)))
      (#x04 (instr :if (read-block-type bin)))
      (#x0c (instr :br (read-u32 bin)))
      (#x0d (instr :br-if (read-u32 bin)))
      (#x0e (instr :br-table (read-vec bin #'read-u32) (read-u32 bin)))
      (#x10 (instr :call (read-u32 bin)))
      (#x11 (instr :call-indirect (read-u32 bin) (read-u32 bin)))
      (#x1c (instr :select-t (read-vec bin #'read-valtype)))
      ((#x20 #x21 #x22 #x23 #x24 #x25 #x26)
       (instr (aref #(:local.get :local.set :local.tee :global.get :global.set
                      :table.get :table.set)
                    (- byte #x20))
              (read-u32 bin)))
      ((#x28 #x29 #x2a #x2b #x2c #x2d #x2e #x2f #x30 #x31 #x32 #x33 #x34 #x35
        #x36 #x37 #x38 #x39 #x3a #x3b #x3c #x3d #x3e)
       (multiple-value-bind (align offset) (read-memop bin)
         (instr (aref #(:i32.load :i64.load :f32.load :f64.load
                        :i32.load8-s :i32.load8-u :i32.load16-s :i32.load16-u
                        :i64.load8-s :i64.load8-u :i64.load16-s :i64.load16-u
                        :i64.load32-s :i64.load32-u
                        :i32.store :i64.store :f32.store :f64.store
                        :i32.store8 :i32.store16 :i64.store8 :i64.store16
                        :i64.store32)
                      (- byte #x28))
                align offset)))
      (#x3f (expect-byte bin 0 "zero byte expected") (instr :memory.size))
      (#x40 (expect-byte bin 0 "zero byte expected") (instr :memory.grow))
      (#x41 (instr :i32.const (read-s32 bin)))
      (#x42 (instr :i64.const (read-s64 bin)))
      (#x43 (instr :f32.const (read-f32-bits bin)))
      (#x44 (instr :f64.const (read-f64-bits bin)))
      (#xd0 (instr :ref.null (read-reftype bin)))
      (#xd2 (instr :ref.func (read-u32 bin)))
      (#xfc (read-prefix bin))
      (t (let ((op (aref *plain-opcodes* byte)))
           (if op
               (instr op)
               (wasm-fail 'wasm-malformed "illegal opcode")))))))

(defun read-expr (bin)
  (let ((out (make-array 16 :adjustable t :fill-pointer 0))
        (stack '(:body)))
    (loop
      (let ((byte (peek-u8 bin)))
        (unless byte
          (wasm-fail 'wasm-malformed "unexpected end of section or function"))
        (cond ((= byte #x0b)
               (read-u8 bin)
               (vector-push-extend (instr :end) out)
               (pop stack)
               (when (null stack) (return (coerce out 'simple-vector))))
              ((= byte #x05)
               (read-u8 bin)
               (unless (eq (car stack) :if)
                 (wasm-fail 'wasm-malformed "END opcode expected"))
               (setf (car stack) :else)
               (vector-push-extend (instr :else) out))
              (t (let ((item (read-instr bin)))
                   (vector-push-extend item out)
                   (case (instr-op item)
                     (:block (push :block stack))
                     (:loop (push :loop stack))
                     (:if (push :if stack))))))))))

(defun read-limits (bin)
  (let* ((flags (read-u1 bin))
         (min (read-u32 bin))
         (max (when (= flags 1) (read-u32 bin))))
    (cons min max)))

(defun read-table-type (bin)
  (let ((element (read-reftype bin))
        (limits (read-limits bin)))
    (make-wasm-table-type :element element :min (car limits) :max (cdr limits))))

(defun read-memory-type (bin)
  (let ((limits (read-limits bin)))
    (make-wasm-memory-type :min (car limits) :max (cdr limits))))

(defun read-global-type (bin)
  (let ((type (read-valtype bin))
        (mutable (read-u8 bin)))
    (case mutable
      (0 (cons type nil))
      (1 (cons type t))
      (t (wasm-fail 'wasm-malformed "malformed mutability")))))

(defun read-func-type (bin)
  (unless (= (read-s7 bin) -32)
    (wasm-fail 'wasm-malformed "malformed function type"))
  (cons (read-vec bin #'read-valtype) (read-vec bin #'read-valtype)))

(defvar *section-end* nil)

(defun read-sized (bin reader)
  (let* ((size (read-len32 bin))
         (start (wbin-pos bin))
         (end (+ start size)))
    (prog1 (let ((*section-end* end))
             (funcall reader bin))
      (unless (= (wbin-pos bin) end)
        (wasm-fail 'wasm-malformed "section size mismatch")))))

(defun skip-custom (bin)
  (loop while (eql (peek-u8 bin) 0) do
    (read-u8 bin)
    (read-sized bin
                (lambda (inner)
                  (read-utf8 inner)
                  (let ((remain (- *section-end* (wbin-pos inner))))
                    (when (minusp remain)
                      (wasm-fail 'wasm-malformed
                                 "unexpected end of section or function"))
                    (loop repeat remain do (read-u8 inner)))))))

(defun read-section (bin id reader empty)
  (skip-custom bin)
  (let ((byte (peek-u8 bin)))
    (cond ((null byte) empty)
          ((> byte 12) (wasm-fail 'wasm-malformed "malformed section id"))
          ((= byte id)
           (read-u8 bin)
           (read-sized bin reader))
          (t empty))))

(defun read-locals (bin)
  (let ((groups (read-vec bin (lambda (inner)
                                (cons (read-u32 inner) (read-valtype inner)))))
        (total 0)
        (locals nil))
    (loop for (count . type) across groups do
      (incf total count)
      (when (> total #xffffffff)
        (wasm-fail 'wasm-malformed "too many locals")))
    (loop for (count . type) across groups do
      (dotimes (i count) (push type locals)))
    (nreverse locals)))

(defun read-code (bin)
  (read-sized bin
              (lambda (inner)
                (make-wasm-code :locals (read-locals inner)
                                :body (read-expr inner)))))

(defun ref-func-expr (index)
  (coerce (list (instr :ref.func index) (instr :end)) 'simple-vector))

(defun read-elem-kind (bin)
  (if (zerop (read-u8 bin))
      :funcref
      (wasm-fail 'wasm-malformed "malformed element kind")))

(defun read-elem (bin)
  (let ((flags (read-u32 bin)))
    (case flags
      (0 (make-wasm-elem :type :funcref :mode :active :table 0
                         :offset (read-expr bin)
                         :inits (map 'vector #'ref-func-expr
                                     (read-vec bin #'read-u32))))
      (1 (make-wasm-elem :type (read-elem-kind bin) :mode :passive
                         :inits (map 'vector #'ref-func-expr
                                     (read-vec bin #'read-u32))))
      (2 (let ((table (read-u32 bin))
               (offset (read-expr bin)))
           (make-wasm-elem :type (read-elem-kind bin) :mode :active
                           :table table :offset offset
                           :inits (map 'vector #'ref-func-expr
                                       (read-vec bin #'read-u32)))))
      (3 (make-wasm-elem :type (read-elem-kind bin) :mode :declarative
                         :inits (map 'vector #'ref-func-expr
                                     (read-vec bin #'read-u32))))
      (4 (make-wasm-elem :type :funcref :mode :active :table 0
                         :offset (read-expr bin)
                         :inits (read-vec bin #'read-expr)))
      (5 (make-wasm-elem :type (read-reftype bin) :mode :passive
                         :inits (read-vec bin #'read-expr)))
      (6 (let ((table (read-u32 bin))
               (offset (read-expr bin)))
           (make-wasm-elem :type (read-reftype bin) :mode :active
                           :table table :offset offset
                           :inits (read-vec bin #'read-expr))))
      (7 (make-wasm-elem :type (read-reftype bin) :mode :declarative
                         :inits (read-vec bin #'read-expr)))
      (t (wasm-fail 'wasm-malformed "malformed elements segment kind")))))

(defun read-data (bin)
  (case (read-u32 bin)
    (0 (make-wasm-data :mode :active :memory 0 :offset (read-expr bin)
                       :bytes (read-bytes bin (read-len32 bin))))
    (1 (make-wasm-data :mode :passive
                       :bytes (read-bytes bin (read-len32 bin))))
    (2 (make-wasm-data :mode :active :memory (read-u32 bin)
                       :offset (read-expr bin)
                       :bytes (read-bytes bin (read-len32 bin))))
    (t (wasm-fail 'wasm-malformed "malformed data segment kind"))))

(defun body-uses-data-p (body)
  (loop for item across body
        thereis (member (instr-op item) '(:memory.init :data.drop))))

(defun parse-module (octets)
  (let ((bin (open-wbin octets)))
    (unless (= (read-u32-raw bin) #x6d736100)
      (wasm-fail 'wasm-malformed "magic header not detected"))
    (unless (= (read-u32-raw bin) 1)
      (wasm-fail 'wasm-malformed "unknown binary version"))
    (let* ((types (read-section bin 1 (lambda (s) (read-vec s #'read-func-type)) #()))
           (imports (read-section bin 2 (lambda (s) (read-vec s #'read-import)) #()))
           (func-types (read-section bin 3 (lambda (s) (read-vec s #'read-u32)) #()))
           (tables (read-section bin 4 (lambda (s) (read-vec s #'read-table-type)) #()))
           (memories (read-section bin 5 (lambda (s) (read-vec s #'read-memory-type)) #()))
           (globals (read-section bin 6 (lambda (s) (read-vec s #'read-global)) #()))
           (exports (read-section bin 7 (lambda (s) (read-vec s #'read-export)) #()))
           (start (read-section bin 8 (lambda (s) (read-u32 s)) nil))
           (elems (read-section bin 9 (lambda (s) (read-vec s #'read-elem)) #()))
           (data-count (read-section bin 12 (lambda (s) (read-u32 s)) nil))
           (codes (read-section bin 10 (lambda (s) (read-vec s #'read-code)) #()))
           (datas (read-section bin 11 (lambda (s) (read-vec s #'read-data)) #())))
      (skip-custom bin)
      (let ((rest (peek-u8 bin)))
        (when rest
          (if (> rest 12)
              (wasm-fail 'wasm-malformed "malformed section id")
              (wasm-fail 'wasm-malformed "unexpected content after last section"))))
      (unless (= (length func-types) (length codes))
        (wasm-fail 'wasm-malformed
                   "function and code section have inconsistent lengths"))
      (when (and data-count (/= data-count (length datas)))
        (wasm-fail 'wasm-malformed
                   "data count and data section have inconsistent lengths"))
      (when (and (null data-count)
                 (some (lambda (code) (body-uses-data-p (wasm-code-body code))) codes))
        (wasm-fail 'wasm-malformed "data count section required"))
      (make-wasm-module :types types :imports imports :func-types func-types
                        :tables tables :memories memories :globals globals
                        :exports exports :start start :elems elems
                        :data-count data-count :codes codes :datas datas))))

(defun read-import (bin)
  (let ((module (read-utf8 bin))
        (name (read-utf8 bin))
        (kind (read-u8 bin)))
    (case kind
      (0 (make-wasm-import :module module :name name :kind :func
                           :type (read-u32 bin)))
      (1 (make-wasm-import :module module :name name :kind :table
                           :type (read-table-type bin)))
      (2 (make-wasm-import :module module :name name :kind :memory
                           :type (read-memory-type bin)))
      (3 (make-wasm-import :module module :name name :kind :global
                           :type (read-global-type bin)))
      (t (wasm-fail 'wasm-malformed "malformed import kind")))))

(defun read-global (bin)
  (let ((type (read-global-type bin)))
    (make-wasm-global-def :type (car type) :mutable (cdr type)
                          :init (read-expr bin))))

(defun read-export (bin)
  (let* ((name (read-utf8 bin))
         (kind (read-u8 bin))
         (index (read-u32 bin)))
    (case kind
      (0 (make-wasm-export :name name :kind :func :index index))
      (1 (make-wasm-export :name name :kind :table :index index))
      (2 (make-wasm-export :name name :kind :memory :index index))
      (3 (make-wasm-export :name name :kind :global :index index))
      (t (wasm-fail 'wasm-malformed "malformed export kind")))))

(defun module-import-list (module)
  (map 'list (lambda (item)
               (list (wasm-import-module item)
                     (wasm-import-name item)
                     (wasm-import-kind item)))
       (wasm-module-imports module)))

(defun module-opcode-histogram (module)
  (let ((counts (make-hash-table)))
    (loop for code across (wasm-module-codes module) do
      (loop for item across (wasm-code-body code) do
        (incf (gethash (instr-op item) counts 0))))
    counts))
