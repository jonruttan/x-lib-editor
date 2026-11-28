; # x-lib-editor -- what an editor is made of
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The bundle kit's generator writes tests/lib/harness.gen.x: the dialect
; bundle.xon declares, the bundle's lib/ on the import path, then this file.

(import editor/buffer Buffer)
(import editor/undo Undo)
(import editor/keys Keys keys-cursor-report)
(import editor/screen Pane pane-goto)
(import x/core/doors str-byte-ref str-byte-len)

; keys over BYTES, a list: read answers each in turn, ready? whether any is left
(def keys-over
  (fn (_ bytes)
    (def cell (list bytes))
    (Keys make
      (fn (_) (let ((bs (first cell)))
                (if (null? bs) () (do (%set-first! cell (rest bs)) (first bs)))))
      (fn (_ . ms) (if (null? (first cell)) #f #t)))))

; every key KEYS answers until the end
(def keys-all
  (fn (self k)
    (let ((c (k key))) (if (null? c) () (pair c (self k))))))

; S with each Escape shown as ^[
(def esc-shown
  (fn (_ s)
    (%str-concat
      (List map (fn (_ i) (if (= (str-byte-ref s i) 27) "^[" (bytes->str (list (str-byte-ref s i)))))
        (List range 0 (str-byte-len s))))))
