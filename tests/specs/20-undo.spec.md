# editor/undo
# @weight 1

An Undo keeps a Buffer's changes as busybox vi's undo does: a stack of
records, chained or not, and a queue that makes a run of single bytes one
record.  Each case pushes a change, makes it on the buffer, and pops; a pop
answers each record it undid as (TYPE START LENGTH COUNT).

## one change

### a deletion put back

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (b insert! 0 "abc")
    (u push-delete! 1 1 (Undo alone))
    (b delete! 1 1)
    (def done (u pop!))
    (list done (Str8 sub 0 (b end) (b text)) (u modified))))
```
---
    (((1 1 1 1)) "abc" 0)

### an insertion taken out

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 2 (Undo alone))
    (b insert! 0 "ab")
    (list (u pop!) (b end))))
```
---
    (((0 0 2 1)) 0)

### nothing to undo

```x
(let ((b (Buffer make))) (null? ((Undo make b) pop!)))
```
---
    #t

### a change that may not be undone is not kept

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 2 (Undo none))
    (b insert! 0 "ab")
    (list (u stack) (u modified))))
```
---
    (() 0)

## chains

### one pop takes back a change and the one chained under it

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 1 (Undo alone))
    (b insert! 0 "x")
    (u push-insert! 1 1 (Undo chain))
    (b insert! 1 "y")
    (list (u pop!) (b end) (u modified))))
```
---
    (((2 1 1 2) (0 0 1 1)) 0 0)

### a chain that runs off the stack answers a chained record last

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 1 (Undo chain))
    (b insert! 0 "x")
    (def done (u pop!))
    (list done (Undo chained? (first (List last done))))))
```
---
    (((2 0 1 1)) #t)

## the queue

### a run of typing comes back as one

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 1 (Undo queued))
    (b insert! 0 "a")
    (u push-insert! 1 1 (Undo queued))
    (b insert! 1 "b")
    (u push-insert! 2 1 (Undo queued))
    (b insert! 2 "c")
    (list (u stack) (u pop!) (b end))))
```
---
    (() ((0 0 3 1)) 0)

### a run of backspacing comes back as one

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (b insert! 0 "abcde\n")
    (u push-delete! 2 1 (Undo queued))
    (b delete! 2 2)
    (u push-delete! 1 1 (Undo queued))
    (b delete! 1 1)
    (def done (u pop!))
    (list done (Str8 sub 0 (b end) (b text)))))
```
---
    (((1 1 2 1)) "abcde\n")

### a queued deletion as long as the text left keeps one byte fewer

busybox measures the queue against the text as it is when the queue is
committed, not as it was.

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (b insert! 0 "abc\n")
    (u push-delete! 2 1 (Undo queued))
    (b delete! 2 2)
    (u push-delete! 1 1 (Undo queued))
    (b delete! 1 1)
    (def done (u pop!))
    (list done (Str8 sub 0 (b end) (b text)))))
```
---
    (((1 1 1 1)) "ab\n")

### typing after backspacing commits the deletions first

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (b insert! 0 "ab\n")
    (u push-delete! 1 1 (Undo queued))
    (b delete! 1 1)
    (u push-insert! 1 1 (Undo queued))
    (b insert! 1 "x")
    (u commit!)
    (List map (fn (_ r) (first r)) (u stack))))
```
---
    (0 1)

## the count

### each record pushed counts, and a written text starts again at 0

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 1 (Undo alone))
    (u push-insert! 1 1 (Undo alone))
    (def n (u modified))
    (u modified! 0)
    (list n (u modified))))
```
---
    (2 0)

### a deletion of the whole text keeps one byte fewer

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (b insert! 0 "ab")
    (u push-delete! 0 2 (Undo alone))
    (first (rest (rest (first (u stack)))))))
```
---
    1

### flushing forgets the records

```x
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 1 (Undo alone))
    (u flush!)
    (list (u stack) (u pop!))))
```
---
    (() ())
