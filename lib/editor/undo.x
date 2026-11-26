; # x-lib-editor -- what an editor is made of
;
; ## lib/editor/undo.x -- a buffer's changes, to take back
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox vi's undo (editors/vi.c, with FEATURE_VI_UNDO and its queue).  Every
; change to the text says how it may be undone: not at all, on its own,
; chained to the change before it so one pop takes both back, or queued, so a
; run of typing or backspacing comes back as one.  The queue holds 256 bytes
; before it is a record of its own.  The change count is the stack's height:
; each record pushed adds one, each popped takes one away.
;
; A pop answers what it did and says nothing: the messages, and where the
; cursor goes, are the editor's.

(module editor/undo)

(import editor/buffer Buffer)
(import x/core/doors str-make str->ptr ptr-set! int+ int- int<)

(def %u+ int+)
(def %u- int-)
(def %u< int<)

; the first N of BYTES as (BUFFER . LENGTH), a NUL after them
(def %u-bytes-copy
  (fn (_ bytes n)
    (def s (str-make (%u+ n 1)))
    (%u-fill (str->ptr s) 0 n bytes)
    (pair s n)))
(def %u-fill
  (fn (self ptr i n bytes)
    (if (if (%u< i n) (if (null? bytes) #f #t) #f)
      (do (ptr-set! ptr i (first bytes) 1) (self ptr (%u+ i 1) n (rest bytes)))
      ())))

; The pushes run on every key typed, and a send costs hundreds of objects, so
; the work a push and a commit share is done here, by functions handed the
; method's own field accessors: GET is the method's field, PUT its
; set-field!.

; a record pushed, the count one more
(def %u-record!
  (fn (_ get put start type text)
    (put 'stack (pair (list type start (rest text) (first text)) (get 'stack)))
    (put 'modified (%u+ (get 'modified) 1))))

; a deletion of the whole text keeps one byte fewer: the newline an empty
; text gets back
(def %u-del-len
  (fn (_ get len) (if (= len ((get 'buf) end)) (%u- len 1) len)))

; busybox's undo_queue_commit: what the queue holds, as one record starting
; where the queued change starts; filled while empty, a record busybox pushes
; and can not undo
(def %u-commit!
  (fn (_ get put)
    (if (%u< 0 (get 'q))
      (do (match
            ((= (get 'state) 1)
              (%u-record! get put (get 'spos) 1
                (%u-bytes-copy (get 'bytes) (%u-del-len get (get 'q)))))
            ((= (get 'state) 0) (%u-record! get put (get 'spos) 0 (pair "" (get 'q))))
            (#t (%u-record! get put (get 'spos) 64 (pair "" (get 'q)))))
          (put 'state 64)
          (put 'q 0)
          (put 'bytes ()))
      ())))

; one byte about to go, onto the queue of deletions; the queue of insertions,
; if that is what it holds, is committed first
(def %u-queue-del!
  (fn (_ get put src len)
    (if (= len 1)
      (do (if (= (get 'state) 0) (%u-commit! get put) ())
          (put 'state 1)
          (put 'spos src)
          (put 'q (%u+ (get 'q) 1))
          (put 'bytes (pair ((get 'buf) byte src) (get 'bytes)))
          (if (= (get 'q) 256) (%u-commit! get put) ()))
      ())))

; LEN bytes put in, onto the queue of insertions, committed each time it
; fills -- which leaves it empty while the count goes on, as busybox's does
(def %u-queue-ins!
  (fn (_ get put src len)
    (if (%u< 0 len)
      (do (if (= (get 'state) 1) (%u-commit! get put) ())
          (if (= (get 'state) 64) (do (put 'state 0) (put 'spos src)) ())
          (%u-count-in! get put len))
      ())))
(def %u-count-in!
  (fn (self get put len)
    (if (%u< 0 len)
      (do (put 'q (%u+ (get 'q) 1))
          (if (= (get 'q) 256) (%u-commit! get put) ())
          (self get put (%u- len 1)))
      ())))

; busybox's undo_push: LEN bytes at SRC as a record of TYPE, or onto the queue
(def %u-push!
  (fn (_ get put src len type)
    (match
      ((= type 64) ())
      ((= type 5) (%u-queue-del! get put src len))
      ((= type 4) (%u-queue-ins! get put src len))
      ((if (= type 1) #t (= type 3))
        (%u-record! get put src type ((get 'buf) copy src (%u-del-len get len))))
      (#t (%u-record! get put src type (pair "" len))))))

(def-class Undo ()
  (doc "busybox vi's undo for one Buffer: a stack of records, each the text put in or taken out at a place, chained or not, and a queue that makes a run of single bytes one record."
    (note "A record is (TYPE START LENGTH TEXT); TEXT, a raw buffer, is what a deletion took.")
    (example "(let ((b (Buffer make))) (let ((u (Undo make b))) (u push-insert! 0 2 (Undo alone)) (b insert! 0 \"ab\") (u pop!) (b end)))" "0")
    (see push-insert!) (see push-delete!) (see pop!))

  buf       ; the Buffer
  stack     ; the records, newest first
  q         ; the bytes queued
  state     ; what the queue holds: ins, del or empty
  spos      ; where the queued change starts
  bytes     ; the bytes a queued deletion took, leftmost first
  modified  ; the change count

  (static
    ; how a change may be undone, as a caller says it
    (none 0)
    (alone 1)
    (chain 2)
    (queued 3)
    ; the records' types, and the queue's own states
    (ins 0)
    (del 1)
    (ins-chain 2)
    (del-chain 3)
    (ins-queued 4)
    (del-queued 5)
    (use-spos 32)
    (empty 64)
    (queue-max 256)

    (method make (self (param buf Buffer "The buffer whose changes it keeps"))
      (doc "Nothing to undo and nothing queued, for BUF."
        (returns Undo "A new undo")
        (example "((Undo make (Buffer make)) modified)" "0"))
      (new-from self (list 'buf buf 'stack () 'q 0 'state 64 'spos 0 'bytes () 'modified 0)))

    (method chained? (self (param type INTEGER "A record's type"))
      (doc "Whether a record of TYPE is chained to the one below it, so a pop goes on to that one."
        (returns BOOL "True when it is")
        (example "(Undo chained? (Undo del-chain))" "#t"))
      (if (= type 3) #t (= type 2)))

    (method deletion? (self (param type INTEGER "A record's type"))
      (doc "Whether a record of TYPE kept text taken out, which a pop puts back."
        (returns BOOL "True when it did")
        (example "(Undo deletion? (Undo del))" "#t"))
      (if (= type 1) #t (= type 3))))

  ; --- the count ---------------------------------------------------------------

  (method modified (self)
    (doc "The change count: the records pushed less the ones popped, unless set since."
      (returns INTEGER "The count"))
    (field 'modified))

  (method modified! (self (param n INTEGER "The count"))
    (doc "The change count made N: 0 once the text is written." (returns Undo "self"))
    (set-field! 'modified n)
    self)

  (method stack (self)
    (doc "The records, newest first." (returns LIST "Each (TYPE START LENGTH TEXT)"))
    (field 'stack))

  (method flush! (self)
    (doc "busybox's flush_undo_data: nothing to undo, for a new text. The queue is kept."
      (returns Undo "self"))
    (set-field! 'stack ())
    self)

  ; --- pushing -----------------------------------------------------------------

  (method push! (self (param src INTEGER "Where") (param len INTEGER "The bytes")
                      (param type INTEGER "A record's type"))
    (doc "busybox's undo_push: LEN bytes at SRC as a record of TYPE, or onto the queue. A deletion is pushed before its bytes go, so they are copied while still there."
      (returns INTEGER "The change count"))
    (%u-push! field set-field! src len type)
    (field 'modified))

  (method push-insert! (self (param p INTEGER "Where") (param len INTEGER "The bytes")
                             (param how INTEGER "none, alone, chain or queued"))
    (doc "busybox's undo_push_insert: LEN bytes put in at P, recorded as HOW says."
      (returns INTEGER "The change count"))
    (match
      ((= how 1) (%u-push! field set-field! p len 0))
      ((= how 2) (%u-push! field set-field! p len 2))
      ((= how 3) (%u-push! field set-field! p len 4))
      (#t ()))
    (field 'modified))

  (method push-delete! (self (param p INTEGER "Where") (param len INTEGER "The bytes")
                             (param how INTEGER "none, alone, chain or queued"))
    (doc "The same for LEN bytes about to be taken out at P." (returns INTEGER "The change count"))
    (match
      ((= how 1) (%u-push! field set-field! p len 1))
      ((= how 2) (%u-push! field set-field! p len 3))
      ((= how 3) (%u-push! field set-field! p len 5))
      (#t ()))
    (field 'modified))

  (method commit! (self)
    (doc "busybox's undo_queue_commit: what the queue holds, as one record starting where the queued change starts."
      (returns INTEGER "The change count"))
    (%u-commit! field set-field!)
    (field 'modified))

  ; --- popping -----------------------------------------------------------------

  (method pop! (self)
    (doc "busybox's undo_pop: the queue committed, then the newest record undone and the ones chained under it. Answers what each did, in order, as (TYPE START LENGTH COUNT), COUNT the change count before the record came off; nothing when there was nothing to undo. When the last one answered is chained, or none is, the stack ran out."
      (returns LIST "The records undone")
      (example "(let ((b (Buffer make))) (let ((u (Undo make b))) (b insert! 0 \"abc\") (u push-delete! 1 1 (Undo alone)) (b delete! 1 1) (u pop!)))" "((1 1 1 1))"))
    (%u-commit! field set-field!)
    (List reverse (self %pop-on! ())))

  (method %pop-on! (self (param done LIST "What was undone, newest first"))
    (doc "Records undone until one not chained, or none left." (returns LIST "DONE and these"))
    (let ((stack (field 'stack)))
      (if (null? stack) done
        (let ((rec (first stack)))
          (let ((type (first rec)))
            (self %apply! rec)
            (let ((entry (list type (first (rest rec)) (first (rest (rest rec))) (field 'modified))))
              (set-field! 'stack (rest (field 'stack)))
              (set-field! 'modified (%u- (field 'modified) 1))
              (if (Undo chained? type)
                (self %pop-on! (pair entry done))
                (pair entry done))))))))

  (method %apply! (self (param rec LIST "A record"))
    (doc "A record's change taken back: a deletion's bytes put in again, an insertion's taken out."
      (returns Undo "self"))
    (let ((type (first rec)) (start (first (rest rec))) (len (first (rest (rest rec))))
          (b (field 'buf)))
      (match
        ((Undo deletion? type) (b insert! start (first (rest (rest (rest rec)))) len))
        ((if (= type 0) #t (= type 2))
          (let ((q (%u- (%u+ start len) 1)))
            ; busybox's text_hole_delete counts one down, then one up when the
            ; bytes go
            (if (b closes? start q) () (set-field! 'modified (%u- (field 'modified) 1)))
            (b delete! start q)))
        (#t ())))
    self))

(provide editor/undo Undo)
