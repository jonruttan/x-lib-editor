; # x-lib-editor -- what an editor is made of
;
; ## lib/editor/buffer.x -- a text, as bytes
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's vi keeps its text as one block of bytes with every place in it an
; offset, and a change moves the bytes after it; this is that block.  The
; block is a string made raw, one byte longer than its room so a NUL can sit
; after the last byte, and grown 10240 bytes past what an insertion needs,
; keeping all of the old one as busybox's realloc does.  A search is libc's
; memchr, memmem or strcspn through the FFI: a byte loop in x costs hundreds of
; objects a byte, a libc call two.
;
; The buffer counts its newlines and every change, and keeps the newlines
; before one place, so a line number is counted from the place nearest it.  A
; cursor is not the buffer's: each editor keeps its own.

(module editor/buffer)

(import x/core/doors str-byte-ref str-make str->ptr ptr->int ptr-set! ptr-call
  ffi-dlsym ffi-dlopen int+ int- int< int&)

(def %b+ int+)
(def %b- int-)
(def %b< int<)
(def %b-min (fn (_ a b) (if (%b< a b) a b)))
(def %b-max (fn (_ a b) (if (%b< a b) b a)))

; the libc calls, found once a buffer is made: an image saved and run again
; is a new process, where the old addresses mean nothing
(def %b-memchr (list ()))
(def %b-memmove (list ()))
(def %b-memcpy (list ()))
(def %b-memset (list ()))
(def %b-memmem (list ()))
(def %b-strcspn (list ()))
(def %b-strcasestr (list ()))
(def %b-read (list ()))
(def %b-write (list ()))
(def %b-resolve!
  (fn (_)
    (def lib (ffi-dlopen () 1))
    (%set-first! %b-memchr (ffi-dlsym lib "memchr"))
    (%set-first! %b-memmove (ffi-dlsym lib "memmove"))
    (%set-first! %b-memcpy (ffi-dlsym lib "memcpy"))
    (%set-first! %b-memset (ffi-dlsym lib "memset"))
    (%set-first! %b-memmem (ffi-dlsym lib "memmem"))
    (%set-first! %b-strcspn (ffi-dlsym lib "strcspn"))
    (%set-first! %b-strcasestr (ffi-dlsym lib "strcasestr"))
    (%set-first! %b-read (ffi-dlsym lib "read"))
    (%set-first! %b-write (ffi-dlsym lib "write"))))

; an address libc answered as an offset from BASE, or -1 for its NULL
(def %b-found (fn (_ base r) (if (= r 0) -1 (%b- r base))))

; the first newline in [A, B) of the bytes at BASE, or -1
(def buffer-find-newline
  (fn (_ base a b)
    (if (%b< a b)
      (%b-found base (ptr-call (first %b-memchr) (%b+ base a) 10 (%b- b a)))
      -1)))

(def %b-newlines-from
  (fn (self base a b n)
    (def at (buffer-find-newline base a b))
    (if (= at -1) n (self base (%b+ at 1) b (%b+ n 1)))))

; the newlines in [A, B) of the bytes at BASE
(def buffer-newlines (fn (_ base a b) (%b-newlines-from base a b 0)))

(def %b-last-nl-in
  (fn (self base lo hi found)
    (def at (buffer-find-newline base lo hi))
    (if (= at -1) found (self base (%b+ at 1) hi at))))

; the last newline before P, or -1: libc has no backward memchr everywhere,
; so the text before P is searched forward, 128 bytes at a time from P back
(def %b-nl-before
  (fn (self base p)
    (def lo (if (%b< p 128) 0 (%b- p 128)))
    (def at (%b-last-nl-in base lo p -1))
    (match
      ((%b< -1 at) at)
      ((= lo 0) -1)
      (#t (self base lo)))))

(def buffer-begin-line
  (fn (_ base p) (if (%b< 0 p) (%b+ (%b-nl-before base p) 1) p)))

(def buffer-end-line
  (fn (_ base end p)
    (def last (%b- end 1))
    (if (%b< p last)
      (%b-end-line-at (buffer-find-newline base p last) last)
      p)))
(def %b-end-line-at (fn (_ at last) (if (= at -1) last at)))

(def buffer-next-line
  (fn (_ text base end p)
    (def e (buffer-end-line base end p))
    (if (if (%b< e (%b- end 1)) (= (str-byte-ref text e) #\newline) #f) (%b+ e 1) e)))

(def buffer-prev-line
  (fn (_ text base p)
    (def b (buffer-begin-line base p))
    (buffer-begin-line base
      (if (if (%b< 0 b) (= (str-byte-ref text (%b- b 1)) #\newline) #f) (%b- b 1) b))))

; whether taking out P through Q, both kept, from a text of END bytes takes
; anything: the span ends inside the text and starts in it
(def %b-closes?
  (fn (_ end p q)
    (def src (if (%b< q p) (%b+ p 1) (%b+ q 1)))
    (def dest (if (%b< q p) q p))
    (if (%b< end src) #f (if (%b< dest 0) #f (%b< dest end)))))

(def buffer-count-lines
  (fn (_ base end start stop)
    (def a (if (%b< stop start) stop start))
    (def z (if (%b< stop start) start stop))
    (%b-newlines-from base a (%b-min (%b+ (buffer-end-line base end z) 1) end) 0)))

(def buffer-plain-end
  (fn (_ base a reject) (%b+ a (ptr-call (first %b-strcspn) (%b+ base a) reject))))

(def buffer-next-lines
  (fn (self text base end p n)
    (if (%b< 0 n) (self text base end (buffer-next-line text base end p) (%b- n 1)) p)))

(def buffer-prev-lines
  (fn (self text base p n)
    (if (%b< 0 n) (self text base (buffer-prev-line text base p) (%b- n 1)) p)))

; the newlines before P, from N known before POS, in the bytes at BASE
(def buffer-lines-before
  (fn (_ base pos n p)
    (if (%b< p pos)
      (%b- n (%b-newlines-from base p pos 0))
      (%b+ n (%b-newlines-from base pos p 0)))))

(def %b-io-all
  (fn (self cell fd base at left done)
    (if (%b< 0 left)
      (%b-io-got self cell fd base at left done (ptr-call (first cell) fd (%b+ base at) left))
      done)))
(def %b-io-got
  (fn (_ again cell fd base at left done r)
    (if (%b< 0 r) (again cell fd base (%b+ at r) (%b- left r) (%b+ done r)) done)))

(def-class Buffer ()
  (doc "A text as one block of bytes, busybox vi's: every place in it an offset, a change moving the bytes after it. It counts its newlines and its changes; a cursor is the editor's, not the buffer's."
    (note "Offsets are bytes. The byte after the text is the block's own, and an edit can leave a byte there, as busybox's realloc does.")
    (example "(let ((b (Buffer make))) (b insert! 0 \"ab\\ncd\\n\") (b end-line 0))" "2")
    (see insert!) (see delete!) (see begin-line))

  text      ; the block, a string made raw, room bytes and a NUL
  tptr      ; its address as a pointer, for ptr-set!
  taddr     ; and as an integer, for libc
  room      ; the bytes it holds, less the NUL
  end       ; the bytes of text in it
  version   ; one more each change
  nls       ; the newlines in the text
  lc-pos    ; a place in the text
  lc-n      ; and the newlines before it

  (static
    (method make (self)
      (doc "An empty buffer: no bytes of text, room for 10240."
        (returns Buffer "A new buffer")
        (example "((Buffer make) end)" "0"))
      (%b-resolve!)
      (let ((b (new-from self (list 'text "" 'tptr () 'taddr 0 'room 0 'end 0
                                    'version 0 'nls 0 'lc-pos 0 'lc-n 0))))
        (b room! 10240)
        (ptr-set! (b pointer) 0 0 1)
        b)))

  ; --- reading ---------------------------------------------------------------

  (method view (self)
    (doc "What an editor keeps between two changes, in one call: the block, its address, the text's length, the change count and the newlines."
      (returns LIST "(TEXT ADDRESS END VERSION NEWLINES)")
      (example "(let ((b (Buffer make))) (b insert! 0 \"a\\nb\") (rest (rest (b view))))" "(3 1 1)"))
    (list (field 'text) (field 'taddr) (field 'end) (field 'version) (field 'nls)))

  (method text (self)
    (doc "The block itself, its room bytes and a NUL: changed in place by an edit, and replaced when the buffer grows."
      (returns STRING "The block")
      (example "(let ((b (Buffer make))) (b insert! 0 \"hi\") (Str8 sub 0 2 (b text)))" "\"hi\""))
    (field 'text))

  (method pointer (self)
    (doc "The block's address, as a pointer." (returns ANY "Its address"))
    (field 'tptr))

  (method address (self)
    (doc "The block's address, as an integer, for libc." (returns INTEGER "Its address"))
    (field 'taddr))

  (method room (self)
    (doc "The bytes the block holds before it must grow."
      (returns INTEGER "Its room")
      (example "((Buffer make) room)" "10240"))
    (field 'room))

  (method end (self)
    (doc "The bytes of text." (returns INTEGER "The text's length")
      (example "(let ((b (Buffer make))) (b insert! 0 \"abc\") (b end))" "3"))
    (field 'end))

  (method version (self)
    (doc "A count of the changes: two equal versions mean the same text."
      (returns INTEGER "The change count"))
    (field 'version))

  (method newlines (self)
    (doc "The newlines in the text." (returns INTEGER "Their count")
      (example "(let ((b (Buffer make))) (b insert! 0 \"a\\nb\\n\") (b newlines))" "2"))
    (field 'nls))

  (method byte (self (param p INTEGER "An offset"))
    (doc "The byte at P." (returns INTEGER "Its value")
      (example "(let ((b (Buffer make))) (b insert! 0 \"A\") (b byte 0))" "65"))
    (int& (str-byte-ref (field 'text) p) 255))

  (method copy (self (param p INTEGER "An offset") (param len INTEGER "A byte count"))
    (doc "LEN bytes from P, as many as the block holds, in a raw buffer of their own with a NUL after."
      (returns PAIR "(BUFFER . LENGTH)"))
    (let ((n (%b-max 0 (%b-min len (%b- (field 'room) p)))))
      (let ((s (str-make (%b+ n 1))))
        (ptr-call (first %b-memcpy) (ptr->int (str->ptr s)) (%b+ (field 'taddr) p) n)
        (pair s n))))

  (method newlines-in (self (param a INTEGER "From") (param b INTEGER "To, not kept"))
    (doc "The newlines in [A, B)." (returns INTEGER "Their count"))
    (%b-newlines-from (field 'taddr) a b 0))

  (method find-newline (self (param a INTEGER "From") (param b INTEGER "To, not kept"))
    (doc "The first newline in [A, B), or -1." (returns INTEGER "Its offset"))
    (buffer-find-newline (field 'taddr) a b))

  (method find (self (param from INTEGER "From") (param room INTEGER "The bytes searched")
                     (param pat STRING "The bytes sought") (param len INTEGER "Their count"))
    (doc "The first LEN bytes of PAT wholly in the ROOM bytes from FROM, or -1."
      (returns INTEGER "Its offset")
      (example "(let ((b (Buffer make))) (b insert! 0 \"abcabc\") (b find 1 5 \"ab\" 2))" "3"))
    (let ((base (field 'taddr)))
      (%b-found base (ptr-call (first %b-memmem) (%b+ base from) room pat len))))

  (method find-any-case (self (param from INTEGER "From") (param pat STRING "The bytes sought"))
    (doc "The first PAT from FROM in any case, as libc's strcasestr: up to the next NUL, which the byte after the text is while it searches. The byte there is put back after."
      (returns INTEGER "Its offset, or -1"))
    (let ((base (field 'taddr)) (ptr (field 'tptr)) (end (field 'end)))
      (let ((was (int& (str-byte-ref (field 'text) end) 255)))
        (ptr-set! ptr end 0 1)
        (let ((r (ptr-call (first %b-strcasestr) (%b+ base from) pat)))
          (ptr-set! ptr end was 1)
          (%b-found base r)))))

  (method find-nul (self (param from INTEGER "From") (param room INTEGER "The bytes searched"))
    (doc "The first NUL byte in the ROOM bytes from FROM, or -1." (returns INTEGER "Its offset"))
    (let ((base (field 'taddr)))
      (%b-found base (ptr-call (first %b-memchr) (%b+ base from) 0 room))))

  (method plain-end (self (param a INTEGER "From") (param reject STRING "The bytes that end it"))
    (doc "Where the bytes from A that are none of REJECT end, as libc's strcspn: at a NUL, too."
      (returns INTEGER "That offset"))
    (buffer-plain-end (field 'taddr) a reject))

  ; --- lines -----------------------------------------------------------------

  (method begin-line (self (param p INTEGER "An offset"))
    (doc "Where the line holding P starts."
      (returns INTEGER "That offset")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\\ncd\\n\") (b begin-line 4))" "3"))
    (buffer-begin-line (field 'taddr) p))

  (method end-line (self (param p INTEGER "An offset"))
    (doc "Where the line holding P ends: its newline, or the text's last byte."
      (returns INTEGER "That offset")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\\ncd\\n\") (b end-line 3))" "5"))
    (buffer-end-line (field 'taddr) (field 'end) p))

  (method next-line (self (param p INTEGER "An offset"))
    (doc "Where the line after P's starts, or P's line's end on the last line."
      (returns INTEGER "That offset")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\\ncd\\n\") (b next-line 1))" "3"))
    (buffer-next-line (field 'text) (field 'taddr) (field 'end) p))

  (method prev-line (self (param p INTEGER "An offset"))
    (doc "Where the line before P's starts, or P's line's start on the first."
      (returns INTEGER "That offset")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\\ncd\\n\") (b prev-line 4))" "0"))
    (buffer-prev-line (field 'text) (field 'taddr) p))

  (method next-lines (self (param p INTEGER "An offset") (param n INTEGER "Lines"))
    (doc "Where the line N after P's starts." (returns INTEGER "That offset"))
    (buffer-next-lines (field 'text) (field 'taddr) (field 'end) p n))

  (method prev-lines (self (param p INTEGER "An offset") (param n INTEGER "Lines"))
    (doc "Where the line N before P's starts." (returns INTEGER "That offset"))
    (buffer-prev-lines (field 'text) (field 'taddr) p n))

  (method find-line (self (param li INTEGER "A line number, from 1"))
    (doc "Where line LI starts, the last line's start past the end."
      (returns INTEGER "That offset")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\\ncd\\n\") (b find-line 2))" "3"))
    (buffer-next-lines (field 'text) (field 'taddr) (field 'end) 0 (%b- li 1)))

  (method count-lines (self (param start INTEGER "An offset") (param stop INTEGER "Another"))
    (doc "busybox's count_lines: the newlines from the earlier of the two through the end of the later's line, never past the text's last byte."
      (returns INTEGER "Their count")
      (example "(let ((b (Buffer make))) (b insert! 0 \"a\\nb\\nc\\n\") (b count-lines 0 2))" "2"))
    (buffer-count-lines (field 'taddr) (field 'end) start stop))

  (method lines-before (self (param p INTEGER "An offset"))
    (doc "The newlines before P, counted from the place asked for last, which it then keeps."
      (returns INTEGER "Their count")
      (example "(let ((b (Buffer make))) (b insert! 0 \"a\\nb\\nc\\n\") (b lines-before 4))" "2"))
    (let ((k (buffer-lines-before (field 'taddr) (field 'lc-pos) (field 'lc-n) p)))
      (set-field! 'lc-pos p)
      (set-field! 'lc-n k)
      k))

  ; --- changing ---------------------------------------------------------------

  (method room! (self (param room INTEGER "The bytes it is to hold"))
    (doc "A new block of ROOM bytes, zeroed, with all of the old one copied in, past the end too, as busybox's realloc keeps it."
      (returns Buffer "self"))
    (let ((old (field 'text)) (old-room (field 'room)) (old-end (field 'end))
          (s (str-make (%b+ room 1))))
      (let ((ptr (str->ptr s)))
        (let ((addr (ptr->int ptr)))
          (ptr-call (first %b-memset) addr 0 (%b+ room 1))
          (set-field! 'text s)
          (set-field! 'tptr ptr)
          (set-field! 'taddr addr)
          (set-field! 'room room)
          (if (%b< 0 old-end)
            (ptr-call (first %b-memcpy) addr old (%b-min old-room room))
            ())
          self))))

  ; A change's bookkeeping is written out in each method that changes the
  ; text, not sent to a helper: a send costs hundreds of objects, and these
  ; run on every key typed.

  (method clear! (self)
    (doc "No text, in a new block of 10240 bytes, the change count kept."
      (returns Buffer "self")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\") (b clear!) (b end))" "0"))
    (set-field! 'end 0)
    (self room! 10240)
    (ptr-set! (field 'tptr) 0 0 1)
    (set-field! 'nls 0)
    (set-field! 'version (%b+ (field 'version) 1))
    (set-field! 'lc-pos 0)
    (set-field! 'lc-n 0)
    self)

  (method touch! (self (param p INTEGER "Where the text changed"))
    (doc "Counts a change at P made to the block directly: the version moves, and the newlines kept for a place past P are forgotten."
      (returns Buffer "self"))
    (set-field! 'version (%b+ (field 'version) 1))
    (if (%b< p (field 'lc-pos)) (do (set-field! 'lc-pos 0) (set-field! 'lc-n 0)) ())
    self)

  (method open! (self (param p INTEGER "An offset") (param size INTEGER "A byte count"))
    (doc "busybox's text_hole_make: SIZE spaces opened at P, the block grown 10240 past what that needs when it must."
      (returns Buffer "self")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\") (b open! 1 2) (Str8 sub 0 4 (b text)))" "\"a  b\""))
    (if (%b< 0 size)
      (let ((new-end (%b+ (field 'end) size)))
        (if (%b< (field 'room) new-end) (self room! (%b+ new-end 10240)) ())
        (set-field! 'version (%b+ (field 'version) 1))
        (if (%b< p (field 'lc-pos)) (do (set-field! 'lc-pos 0) (set-field! 'lc-n 0)) ())
        (let ((base (field 'taddr)))
          (ptr-call (first %b-memmove) (%b+ base (%b+ p size)) (%b+ base p) (%b- (field 'end) p))
          (set-field! 'end new-end)
          (ptr-call (first %b-memset) (%b+ base p) 32 size)))
      ())
    self)

  (method byte-set! (self (param p INTEGER "An offset") (param b INTEGER "A byte"))
    (doc "The byte at P made B, the newline count kept."
      (returns Buffer "self")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ab\") (b byte-set! 1 10) (b newlines))" "1"))
    (let ((was (str-byte-ref (field 'text) p)))
      (if (= was #\newline) (set-field! 'nls (%b- (field 'nls) 1)) ())
      (if (= b #\newline) (set-field! 'nls (%b+ (field 'nls) 1)) ())
      (set-field! 'version (%b+ (field 'version) 1))
      (if (%b< p (field 'lc-pos)) (do (set-field! 'lc-pos 0) (set-field! 'lc-n 0)) ())
      (ptr-set! (field 'tptr) p b 1)
      self))

  (method insert-byte! (self (param p INTEGER "An offset") (param b INTEGER "A byte"))
    (doc "The byte B put in at P, as busybox's stupid_insert: open! and byte-set! in one call, for an editor's typing."
      (returns Buffer "self")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ac\") (b insert-byte! 1 98) (Str8 sub 0 3 (b text)))" "\"abc\""))
    (let ((new-end (%b+ (field 'end) 1)))
      (if (%b< (field 'room) new-end) (self room! (%b+ new-end 10240)) ())
      (set-field! 'version (%b+ (field 'version) 1))
      (if (%b< p (field 'lc-pos)) (do (set-field! 'lc-pos 0) (set-field! 'lc-n 0)) ())
      (if (= b #\newline) (set-field! 'nls (%b+ (field 'nls) 1)) ())
      (let ((base (field 'taddr)))
        (ptr-call (first %b-memmove) (%b+ base (%b+ p 1)) (%b+ base p) (%b- (field 'end) p))
        (set-field! 'end new-end)
        (ptr-set! (field 'tptr) p b 1)))
    self)

  (method insert! (self (param p INTEGER "An offset") (param s STRING "The bytes")
                        . (param len INTEGER "How many of them; default all"))
    (doc "S put in at P, as busybox's string_insert: the room opened, the bytes copied in, their newlines counted."
      (returns Buffer "self")
      (example "(let ((b (Buffer make))) (b insert! 0 \"ac\") (b insert! 1 \"b\") (Str8 sub 0 3 (b text)))" "\"abc\""))
    (let ((n (if (null? len) (Str8 length s) (first len))))
      (self open! p n)
      (ptr-call (first %b-memcpy) (%b+ (field 'taddr) p) s n)
      (set-field! 'nls (%b+ (field 'nls) (%b-newlines-from (field 'taddr) p (%b+ p n) 0)))
      self))

  (method closes? (self (param p INTEGER "An offset") (param q INTEGER "Another, kept"))
    (doc "Whether delete! of P through Q takes bytes out: the span ends inside the text and starts in it."
      (returns BOOL "True when it does"))
    (%b-closes? (field 'end) p q))

  (method delete! (self (param p INTEGER "An offset") (param q INTEGER "Another, kept"))
    (doc "busybox's text_hole_delete: P through Q taken out, both kept, when closes? says so; answers where the text after them now starts, or its last byte."
      (returns INTEGER "That offset")
      (example "(let ((b (Buffer make))) (b insert! 0 \"abcd\") (b delete! 1 2) (Str8 sub 0 2 (b text)))" "\"ad\""))
    (let ((src (if (%b< q p) (%b+ p 1) (%b+ q 1))) (dest (if (%b< q p) q p))
          (base (field 'taddr)) (end (field 'end)))
      (if (%b-closes? end p q)
        (do (set-field! 'nls (%b- (field 'nls) (%b-newlines-from base dest src 0)))
            (set-field! 'version (%b+ (field 'version) 1))
            (if (%b< dest (field 'lc-pos)) (do (set-field! 'lc-pos 0) (set-field! 'lc-n 0)) ())
            (if (%b< src end) (ptr-call (first %b-memmove) (%b+ base dest) (%b+ base src) (%b- end src)) ())
            (let ((e (%b- end (%b- src dest))))
              (set-field! 'end (if (%b< e 1) 0 e))
              (match
                ((%b< e 1) 0)
                ((%b< dest e) dest)
                (#t (%b- e 1)))))
        dest)))

  ; --- descriptors -----------------------------------------------------------

  (method read! (self (param fd INTEGER "A descriptor") (param p INTEGER "An offset")
                      (param size INTEGER "The bytes to read"))
    (doc "SIZE bytes opened at P and read from FD into them; what could not be read is taken out again. The newlines read are counted."
      (returns INTEGER "The bytes read"))
    (self open! p size)
    (let ((cnt (%b-io-all %b-read fd (field 'taddr) p size 0)))
      (if (%b< cnt size) (self delete! (%b+ p cnt) (%b- (%b+ p size) 1)) ())
      (set-field! 'nls (%b+ (field 'nls) (%b-newlines-from (field 'taddr) p (%b+ p cnt) 0)))
      cnt))

  (method write-to (self (param fd INTEGER "A descriptor") (param from INTEGER "From")
                         (param to INTEGER "To, not kept"))
    (doc "The bytes [FROM, TO) written to FD, as many as it takes." (returns INTEGER "The bytes written"))
    (%b-io-all %b-write fd (field 'taddr) from (%b- to from) 0)))

(provide editor/buffer Buffer buffer-find-newline buffer-newlines buffer-begin-line
  buffer-end-line buffer-next-line buffer-prev-line buffer-next-lines buffer-prev-lines
  buffer-count-lines buffer-plain-end buffer-lines-before)
