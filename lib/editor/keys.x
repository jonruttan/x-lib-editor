; # x-lib-editor -- what an editor is made of
;
; ## lib/editor/keys.x -- bytes from a terminal, as keys
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's read_key (libbb/read_key.c): a byte as itself, or a known escape
; sequence as its key code, a negative number.  After an Escape each further
; byte is waited for 50 ms; a lone Escape, or one with a single byte after it,
; is the Escape key, and that byte is held back for the next key.  A run no
; sequence starts is read on while bytes come, up to 15, and dropped, unless
; it is the terminal's report of where its cursor is.
;
; The bytes are the host's: a reader that answers the next one, blocking, or
; nil at the end, and a test of whether one comes within some milliseconds.
; Keys writes nothing.

(module editor/keys)

(import x/core/doors str-byte-ref str-byte-len int+ int- int* int< int| int&)

(def %k+ int+)
(def %k- int-)
(def %k< int<)

; each sequence as the bytes after the Escape, with its code; shortest first,
; as busybox orders them
(def %k-sequences
  (list (pair (bytes->str (list 127)) -44) (pair (bytes->str (list 8)) -44)
        (pair "d" -45) (pair "f" -36) (pair "b" -37)
        (pair "OA" -2) (pair "OB" -3) (pair "OC" -4) (pair "OD" -5)
        (pair "OH" -6) (pair "OF" -7)
        (pair "[A" -2) (pair "[B" -3) (pair "[C" -4) (pair "[D" -5)
        (pair "[H" -6) (pair "[F" -7)
        (pair "[1~" -6) (pair "[2~" -8) (pair "[3~" -9) (pair "[4~" -7)
        (pair "[5~" -10) (pair "[6~" -11) (pair "[7~" -6) (pair "[8~" -7)
        (pair "[1;3C" -36) (pair "[1;3D" -37)
        (pair "[1;5C" -68) (pair "[1;5D" -69)))

; A key read runs on every key typed, and a send costs hundreds of objects, so
; the reading is done here, by functions handed the method's own field
; accessors: GET is the method's field, PUT its set-field!.

; the next byte: the one held back first
(def %k-next-byte
  (fn (_ get put)
    (def held (get 'held))
    (if (null? held)
      ((get 'read))
      (do (put 'held ()) held))))

; a byte, a sequence's code, or nil at the end of the input
(def %k-read
  (fn (self get put)
    (def c (%k-next-byte get put))
    (match
      ((null? c) ())
      ((= c 27) (%k-escape self get put))
      (#t c))))

(def %k-escape
  (fn (_ again get put)
    (def held (get 'held))
    (put 'held ())
    (def got (%k-match get %k-sequences (if (null? held) "" (bytes->str (list held)))))
    (match
      ((null? got) ())
      ((number? got) got)
      ((null? (rest got)) (%k-escape-rest again get put (%k-drain get put (first got))))
      (#t (%k-escape-rest again get put (first got))))))

; a code on a match; (BUF) when no sequence matched with the bytes BUF; (BUF .
; stop) when the bytes stopped coming first; nil at the end of the input
(def %k-match
  (fn (self get seqs buf)
    (if (null? seqs) (list buf)
      (%k-try self get seqs buf 0))))

(def %k-try
  (fn (_ walk get seqs buf i)
    (def want (first (first seqs)))
    (match
      ((= i (str-byte-len want)) (rest (first seqs)))
      ((%k< i (str-byte-len buf))
        (if (= (str-byte-ref buf i) (str-byte-ref want i))
          (%k-try walk get seqs buf (%k+ i 1))
          (walk get (rest seqs) buf)))
      (((get 'ready?) 50) (%k-more walk get seqs buf i))
      (#t (pair buf (lit stop))))))

(def %k-more
  (fn (_ walk get seqs buf i)
    (def b ((get 'read)))
    (if (null? b) ()
      (%k-try walk get seqs (%str-concat (list buf (bytes->str (list b)))) i))))

; no sequence matched: more bytes read while they come, up to 15, each one
; read making the run a cursor report if it now is one
(def %k-drain
  (fn (self get put buf)
    (if (if (%k< (str-byte-len buf) 15) ((get 'ready?) 50) #f)
      (%k-drained self get put buf ((get 'read)))
      buf)))
(def %k-drained
  (fn (_ again get put buf b)
    (if (null? b) ()
      (%k-drained-report again get put (%str-concat (list buf (bytes->str (list b))))))))
(def %k-drained-report
  (fn (_ again get put buf)
    (def rc (keys-cursor-report buf))
    (if (null? rc) (again get put buf)
      (do (put 'reply rc) -256))))

(def %k-escape-rest
  (fn (_ again get put buf)
    (match
      ((null? buf) ())
      ((number? buf) buf)
      ((%k< (str-byte-len buf) 2)
        (do (put 'held (if (= (str-byte-len buf) 0) () (int& (str-byte-ref buf 0) 255))) 27))
      (#t (again get put)))))

; busybox's test for a cursor report: [ ROW ; COL R, each number from 1
; through 0x7FFF; (ROW . COL), or nil
(def %k-digit? (fn (_ c) (if (%k< c 48) #f (if (%k< 57 c) #f #t))))
(def %k-digits-end
  (fn (self s i)
    (if (if (%k< i (str-byte-len s)) (%k-digit? (str-byte-ref s i)) #f) (self s (%k+ i 1)) i)))
(def %k-number
  (fn (self s i j n)
    (if (%k< i j) (self s (%k+ i 1) j (%k+ (int* n 10) (%k- (str-byte-ref s i) 48))) n)))
(def %k-number-at
  (fn (_ s i)
    (def end (%k-digits-end s i))
    (pair (%k-number s i end 0) end)))

(def keys-cursor-report
  (fn (_ s)
    (def n (str-byte-len s))
    (match
      ((%k< n 5) ())
      ((not (= (str-byte-ref s 0) 91)) ())
      ((not (= (str-byte-ref s (%k- n 1)) 82)) ())
      ((not (%k-digit? (str-byte-ref s 1))) ())
      (#t (%k-report-col s (%k-number-at s 1))))))
(def %k-report-col
  (fn (_ s row)
    (def at (rest row))
    (def ok? (if (%k< (%k+ at 1) (str-byte-len s))
               (if (= (str-byte-ref s at) 59) (%k-digit? (str-byte-ref s (%k+ at 1))) #f)
               #f))
    (if ok? (%k-report-end s (first row) (%k-number-at s (%k+ at 1))) ())))
(def %k-report-end
  (fn (_ s row col)
    (match
      ((not (= (rest col) (%k- (str-byte-len s) 1))) ())
      ((%k< row 1) ())
      ((%k< (first col) 1) ())
      ((%k< 32767 (int| row (first col))) ())
      (#t (pair row (first col))))))

(def-class Keys ()
  (doc "busybox's read_key over a host's bytes: each key a byte, or a negative code for a known escape sequence."
    (note "READ answers the next byte, blocking, or nil at the end; READY? answers whether one comes within MS milliseconds.")
    (example "(let ((c (list (list 27 91 65 120)))) (let ((k (Keys make (fn (_) (let ((b (first (first c)))) (%set-first! c (rest (first c))) b)) (fn (_ ms) (not (null? (first c))))))) (list (k key) (k key))))" "(-2 120)")
    (see key) (see idle?) (see cursor-reply))

  read      ; the host's byte reader
  ready?    ; the host's test for a byte coming
  held      ; the byte after a lone Escape, for the next key, or nil
  reply     ; the last cursor report, (ROW . COL)

  (static
    ; the keys' codes, busybox's KEYCODE_ values
    (up -2)
    (down -3)
    (right -4)
    (left -5)
    (home -6)
    (end -7)
    (insert -8)
    (delete -9)
    (page-up -10)
    (page-down -11)
    (alt-right -36)
    (alt-left -37)
    (alt-backspace -44)
    (alt-d -45)
    (ctrl-right -68)
    (ctrl-left -69)
    (cursor-report -256)
    (escape 27)

    (method make (self (param read CALLABLE "The next byte, blocking, or nil at the end")
                       (param ready? CALLABLE "Whether a byte comes within MS milliseconds"))
      (doc "Keys over READ and READY?, nothing held back."
        (returns Keys "New keys")
        (example "(null? ((Keys make (fn (_) ()) (fn (_ ms) #f)) key))" "#t"))
      (new-from self (list 'read read 'ready? ready? 'held () 'reply ())))

    (method sequences (self)
      (doc "The escape sequences known, each the bytes after the Escape with its code, shortest first."
        (returns LIST "Each (BYTES . CODE)")
        (example "(rest (first (Keys sequences)))" "-44"))
      %k-sequences))

  (method key (self)
    (doc "The next key: a byte, a sequence's code, or nil at the end of the input. A cursor report answers (Keys cursor-report), its numbers kept for cursor-reply."
      (returns ANY "A byte, a code, or nil")
      (example "((Keys make (fn (_) 120) (fn (_ ms) #f)) key)" "120"))
    (%k-read field set-field!))

  (method idle? (self)
    (doc "Whether no key waits: nothing held back and no byte coming now. A byte is held back only after key answers an Escape."
      (returns BOOL "True when none waits"))
    (if (null? (field 'held)) (if ((field 'ready?) 0) #f #t) #f))

  (method cursor-reply (self)
    (doc "The last cursor report key answered, (ROW . COL), or nil."
      (returns ANY "(ROW . COL) or nil"))
    (field 'reply))

  (method drop! (self)
    (doc "Nothing held back: a new run's keys start clean." (returns Keys "self"))
    (set-field! 'held ())
    self))

(provide editor/keys Keys keys-cursor-report)
