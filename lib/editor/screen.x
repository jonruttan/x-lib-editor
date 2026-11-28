; # x-lib-editor -- what an editor is made of
;
; ## lib/editor/screen.x -- rows drawn into a rectangle of the terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox vi's refresh: each row compared with the row as last drawn, and only
; the columns from the first that differs to the last written again, or the
; whole row when forced.  A row may come with a row of cells, one byte a
; column: a space for plain text, any other byte a class the host's colour
; function names an SGR sequence for; a run of one class is written after its
; sequence and followed by a reset.
;
; A pane is a rectangle of the terminal, or the whole of it.  Its rows and
; columns count from its corner, and every escape it answers is placed there.
; On the whole terminal a row's end is cleared with ESC [ K, the screen with
; ESC [ H ESC [ J, and the alternate screen is used; in a rectangle the same
; is done with spaces, and the alternate screen is the host's to choose.
;
; Escapes are answered as strings for the host to write: an editor writes
; many pieces a key, and a send costs hundreds of objects.  The placing is
; also a plain function, pane-goto, on the pane's view.

(module editor/screen)

(import x/core/doors str-byte-ref str-byte-len str-byte-sub str-make int+ int- int* int/ int% int<)

(def %p+ int+)
(def %p- int-)
(def %p< int<)
(def %p-min (fn (_ a b) (if (%p< a b) a b)))
(def %p-max (fn (_ a b) (if (%p< a b) b a)))

(def %p-esc (bytes->str (list 27)))
(def %p-reset (%str-concat (list %p-esc "[0m")))

; N in decimal, by the integer doors
(def %p-num
  (fn (_ n)
    (if (%p< n 10) (bytes->str (list (%p+ n 48))) (bytes->str (%p-digits n ())))))
(def %p-digits
  (fn (self n acc)
    (if (= n 0) acc (self (int/ n 10) (pair (%p+ (int% n 10) 48) acc)))))

; N spaces
(def %p-spaces
  (fn (_ n) (if (%p< 0 n) (str-byte-sub (str-make (%p+ n 1)) 0 n) "")))

; the escape that puts the cursor at row R, column C of the pane at TOP, LEFT,
; ROWS by COLS, each clipped to the pane
(def pane-goto
  (fn (_ top left rows cols r c)
    (def rr (%p-max 0 (%p-min r (%p- rows 1))))
    (def cc (%p-max 0 (%p-min c (%p- cols 1))))
    (%str-concat (list %p-esc "[" (%p-num (%p+ (%p+ top rr) 1)) ";"
                       (%p-num (%p+ (%p+ left cc) 1)) "H"))))

; --- drawing ----------------------------------------------------------------

(def %p-first-diff
  (fn (self a b i)
    (if (= (str-byte-ref a i) (str-byte-ref b i)) (self a b (%p+ i 1)) i)))
(def %p-last-diff
  (fn (self a b i)
    (if (= (str-byte-ref a i) (str-byte-ref b i)) (self a b (%p- i 1)) i)))

; the columns [I, E) of ROW, each run of one class in its sequence and a reset
(def %p-runs
  (fn (self colour row cells i e acc)
    (if (%p< i e)
      (let ((j (%p-run-end cells (str-byte-ref cells i) (%p+ i 1) e)))
        (def text (str-byte-sub row i (%p- j i)))
        (def sgr (if (= (str-byte-ref cells i) 32) "" (colour (str-byte-ref cells i))))
        (self colour row cells j e
          (pair (if (= (str-byte-len sgr) 0) text (%str-concat (list sgr text %p-reset))) acc)))
      acc)))
(def %p-run-end
  (fn (self cells c i e)
    (if (if (%p< i e) (= (str-byte-ref cells i) c) #f) (self cells c (%p+ i 1) e) i)))

; what row LI needs written: ROW against OLD (nil when none was drawn), all
; of it when FORCE; pieces onto ACC, last first
(def %p-row
  (fn (_ g li row old force acc)
    (match
      ((if force #t (null? old)) (pair row (pair (g li 0) acc)))
      ((str=? row old) acc)
      (#t (let ((cs (%p-first-diff row old 0)))
            (def ce (%p-last-diff row old (%p- (str-byte-len row) 1)))
            (pair (str-byte-sub row cs (%p+ (%p- ce cs) 1)) (pair (g li cs) acc)))))))

; the same with cells, OC the old row's cells or spaces
(def %p-row-cells
  (fn (_ g colour li row cells old oc force acc)
    (def last (%p- (str-byte-len row) 1))
    (match
      ((if force #t (null? old)) (%p-span g colour li row cells 0 last acc))
      ((str=? row old)
        (if (str=? cells oc) acc
          (%p-span g colour li row cells (%p-first-diff cells oc 0) (%p-last-diff cells oc last) acc)))
      ((str=? cells oc)
        (%p-span g colour li row cells (%p-first-diff row old 0) (%p-last-diff row old last) acc))
      (#t (%p-span g colour li row cells
            (%p-min (%p-first-diff row old 0) (%p-first-diff cells oc 0))
            (%p-max (%p-last-diff row old last) (%p-last-diff cells oc last)) acc)))))
(def %p-span
  (fn (_ g colour li row cells cs ce acc)
    (%p-runs colour row cells cs (%p+ ce 1) (pair (g li cs) acc))))

; every row's pieces: ROWS and CELLS (nil for none) against OLDS and OLDC
(def %p-draw
  (fn (self g colour blank li rows cells olds oldc force acc)
    (if (null? rows) acc
      (self g colour blank (%p+ li 1) (rest rows) (if (null? cells) () (rest cells))
        (if (null? olds) () (rest olds)) (if (null? oldc) () (rest oldc)) force
        (if (null? cells)
          (%p-row g li (first rows) (if (null? olds) () (first olds)) force acc)
          (%p-row-cells g colour li (first rows) (first cells)
            (if (null? olds) () (first olds)) (if (null? oldc) blank (first oldc)) force acc))))))

(def %p-clear-rows
  (fn (self g blank li n acc)
    (if (%p< li n) (self g blank (%p+ li 1) n (pair blank (pair (g li 0) acc))) acc)))

(def-class Pane ()
  (doc "busybox vi's screen, in a rectangle of the terminal or all of it: rows written where they differ from the rows last drawn, with escapes answered for the host to write."
    (note "A rectangle is (ROW COL ROWS COLS), from 0; nil is the whole terminal, sized by resize!.")
    (example "(let ((p (Pane make (list 2 4 3 10)))) (Str8 length (p draw! (list \"ab\") () #f)))" "8")
    (see draw!) (see pane-goto) (see view))

  top       ; the pane's first row on the terminal, from 0
  left      ; its first column
  rows      ; its height
  cols      ; its width
  whole     ; whether it is the whole terminal
  shown     ; the rows as last drawn, top first
  cells     ; their cells, nil for none
  colour    ; a cell's class byte to its SGR sequence

  (static
    (method make (self (param rect ANY "(ROW COL ROWS COLS), or nil for the whole terminal"))
      (doc "A pane on RECT with nothing drawn; the whole terminal is 24 by 80 until resize!."
        (returns Pane "A new pane")
        (example "((Pane make ()) view)" "(0 0 24 80 #t)"))
      (if (null? rect)
        (new-from self (list 'top 0 'left 0 'rows 24 'cols 80 'whole #t 'shown () 'cells ()
                             'colour (fn (_ . c) "")))
        (new-from self (list 'top (first rect) 'left (first (rest rect))
                             'rows (first (rest (rest rect))) 'cols (first (rest (rest (rest rect))))
                             'whole #f 'shown () 'cells () 'colour (fn (_ . c) "")))))

    (method bell (self)
      (doc "The terminal's bell." (returns STRING "BEL") (example "(Str8 length (Pane bell))" "1"))
      (bytes->str (list 7)))

    (method reverse (self (param s STRING "Text"))
      (doc "S in reverse video, as busybox writes its status messages."
        (returns STRING "S between ESC [ 7 m and ESC [ m")
        (example "(Str8 length (Pane reverse \"x\"))" "8"))
      (%str-concat (list %p-esc "[7m" s %p-esc "[m"))))

  ; --- what it is -------------------------------------------------------------

  (method view (self)
    (doc "Where the pane is, in one call: (TOP LEFT ROWS COLS WHOLE?), what pane-goto takes."
      (returns LIST "(TOP LEFT ROWS COLS WHOLE?)"))
    (list (field 'top) (field 'left) (field 'rows) (field 'cols) (field 'whole)))

  (method whole? (self)
    (doc "Whether the pane is the whole terminal." (returns BOOL "True when it is"))
    (field 'whole))

  (method resize! (self (param rows INTEGER "Rows") (param cols INTEGER "Columns"))
    (doc "The pane ROWS by COLS from its corner; what was drawn is forgotten."
      (returns Pane "self")
      (example "(((Pane make ()) resize! 30 100) view)" "(0 0 30 100 #t)"))
    (set-field! 'rows rows)
    (set-field! 'cols cols)
    (set-field! 'shown ())
    (set-field! 'cells ())
    self)

  (method colour! (self (param f CALLABLE "A cell's class byte to its SGR sequence"))
    (doc "How cells are coloured." (returns Pane "self"))
    (set-field! 'colour f)
    self)

  ; --- the rows ---------------------------------------------------------------

  (method shown (self)
    (doc "The rows as last drawn, top first." (returns LIST "The rows"))
    (field 'shown))

  (method reset! (self (param rows LIST "The rows the terminal now shows"))
    (doc "What the terminal shows, said without drawing it: after a clear, or a new screen."
      (returns Pane "self"))
    (set-field! 'shown rows)
    (set-field! 'cells ())
    self)

  (method draw! (self (param rows LIST "The rows, top first")
                      (param cells LIST "Their cells, or nil for plain rows")
                      (param force BOOL "Every row written whole"))
    (doc "The escapes that make the pane show ROWS: each row's columns from the first that differs from the row last drawn to the last, or all of it when FORCE or nothing was drawn there."
      (returns STRING "The escapes")
      (example "(let ((p (Pane make ()))) (p draw! (list \"abc\") () #f) (Str8 length (p draw! (list \"axc\") () #f)))" "7"))
    (let ((top (field 'top)) (left (field 'left)) (rs (field 'rows)) (cs (field 'cols)))
      (let ((g (fn (_ r c) (pane-goto top left rs cs r c))))
        (def out (%p-draw g (field 'colour) (%p-spaces cs) 0 rows cells
                   (field 'shown) (field 'cells) force ()))
        (set-field! 'shown rows)
        (set-field! 'cells cells)
        (%str-concat (List reverse out)))))

  ; --- the terminal -------------------------------------------------------------

  (method clear (self)
    (doc "The escapes that blank the pane: ESC [ H ESC [ J on the whole terminal, a row of spaces each row in a rectangle."
      (returns STRING "The escapes")
      (example "(Str8 length ((Pane make (list 0 0 2 3)) clear))" "18"))
    (if (field 'whole)
      (%str-concat (list %p-esc "[H" %p-esc "[J"))
      (let ((top (field 'top)) (left (field 'left)) (rs (field 'rows)) (cs (field 'cols)))
        (%str-concat (List reverse
          (%p-clear-rows (fn (_ r c) (pane-goto top left rs cs r c)) (%p-spaces cs) 0 rs ()))))))

  (method clear-eol (self (param r INTEGER "Row") (param c INTEGER "Column"))
    (doc "The escapes that blank row R from column C on, the cursor left there."
      (returns STRING "ESC [ K on the whole terminal, spaces in a rectangle"))
    (if (field 'whole) (%str-concat (list %p-esc "[K"))
      (%str-concat (list (%p-spaces (%p- (field 'cols) c))
                         (pane-goto (field 'top) (field 'left) (field 'rows) (field 'cols) r c)))))

  (method enter (self)
    (doc "What starts an editor's screen: the alternate screen on the whole terminal, nothing in a rectangle."
      (returns STRING "The escapes"))
    (if (field 'whole) (%str-concat (list %p-esc "[?1049h")) ""))

  (method leave (self)
    (doc "What ends it: the normal screen back on the whole terminal, nothing in a rectangle."
      (returns STRING "The escapes"))
    (if (field 'whole) (%str-concat (list %p-esc "[?1049l")) "")))

(provide editor/screen Pane pane-goto)
