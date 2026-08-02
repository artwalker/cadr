(load (merge-pathnames "../support.lisp" *load-truename*))
(load (merge-pathnames "wad-finder.lisp" *load-truename*))
(load (merge-pathnames "doom-component.lisp" *load-truename*))

(cadr-agent:define-command
 "doom-overlay"
 :description "Run the 35 FPS DOOM overlay through the bundled external WebAssembly adapter"
 :handler
 (lambda (arguments context)
   (let* ((configured (example-trim arguments))
          (wad (or (and (plusp (length configured)) (probe-file configured))
                   (find-wad-file)))
          (wasm
            (or (and (uiop:getenv "CADR_DOOM_WASM")
                     (probe-file (uiop:getenv "CADR_DOOM_WASM")))
                (probe-file (merge-pathnames "doom/build/doom.wasm" *load-truename*)))))
     (unless wad
       (error "DOOM WAD not found; pass its path or set DOOM_WAD_PATH"))
     (unless wasm
       (error "DOOM WASM not found; set CADR_DOOM_WASM"))
     (cadr-agent:extension-context-custom-component
      context
      (lambda (tui theme keybindings done)
        (declare (ignore theme keybindings))
        (make-instance
         'doom-component
         :engine (start-doom-engine
                  wasm wad (lambda () (cadr-tui:tui-request-render tui)))
         :done done))
      :overlay-p t
      :overlay-options
      '(:anchor :center :width 82 :max-height 30 :margin 0 :focus t)))))
