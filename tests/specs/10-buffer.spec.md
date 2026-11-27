# editor/buffer
# @weight 1

A Buffer is a text as one block of bytes, busybox vi's: every place in it an
offset, and a change moving the bytes after it.  Each case makes its own
buffer.

## making one

### an empty buffer, with room for 10240 bytes

```x
(let ((b (Buffer make))) (list (b end) (b room) (b newlines) (b version)))
```
---
    (0 10240 0 0)

## lines

### where a line starts and ends, and the one after

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab\ncd\n")
  (list (b end) (b newlines) (b end-line 0) (b next-line 1) (b begin-line 4)))
```
---
    (6 2 2 3 3)

### the line before, and the first and last lines' own ends

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab\ncd\n")
  (list (b prev-line 4) (b prev-line 1) (b next-line 4) (b find-line 2) (b find-line 3)))
```
---
    (0 0 5 3 5)

### lines walked by count, both ways

```x
(let ((b (Buffer make)))
  (b insert! 0 "a\nb\nc\nd\n")
  (list (b next-lines 0 2) (b prev-lines 6 2) (b next-lines 2 0)))
```
---
    (4 2 2)

### busybox's count_lines, either way round

```x
(let ((b (Buffer make)))
  (b insert! 0 "a\nb\nc\n")
  (list (b count-lines 0 2) (b count-lines 4 0)))
```
---
    (2 3)

### the newlines before a place, counted from the one asked for last

```x
(let ((b (Buffer make)))
  (b insert! 0 "a\nb\nc\n")
  (list (b lines-before 4) (b lines-before 1) (b lines-before 6)))
```
---
    (2 0 3)

### a change before the kept place forgets it

```x
(let ((b (Buffer make)))
  (b insert! 0 "a\nb\nc\n")
  (b lines-before 6)
  (b insert! 0 "\n")
  (b lines-before 7))
```
---
    4

## changing

### bytes put in at a place

```x
(let ((b (Buffer make)))
  (b insert! 0 "ac")
  (b insert! 1 "b")
  (b insert! 3 "!xyz" 1)
  (list (b end) (Str8 sub 0 (b end) (b text))))
```
---
    (4 "abc!")

### spaces opened at a place

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab")
  (b open! 1 2)
  (list (b end) (Str8 sub 0 4 (b text))))
```
---
    (4 "a  b")

### bytes taken out, both ends kept, answering where the rest starts

```x
(let ((b (Buffer make)))
  (b insert! 0 "abcd")
  (def at (b delete! 1 2))
  (list at (b end) (Str8 sub 0 (b end) (b text))))
```
---
    (1 2 "ad")

### the last bytes taken out answer the new last byte

```x
(let ((b (Buffer make)))
  (b insert! 0 "abcd")
  (list (b delete! 2 3) (b end)))
```
---
    (1 2)

### a span past the end takes nothing out

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab")
  (list (b closes? 1 5) (b delete! 1 5) (b end) (b closes? 0 1)))
```
---
    (#f 1 2 #t)

### a deletion counts the newlines it took

```x
(let ((b (Buffer make)))
  (b insert! 0 "a\nb\nc\n")
  (b delete! 1 3)
  (list (b newlines) (Str8 sub 0 (b end) (b text))))
```
---
    (1 "ac\n")

### one byte replaced, the newline count kept

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab")
  (b byte-set! 1 10)
  (def nl (b newlines))
  (b byte-set! 1 66)
  (list nl (b newlines) (b byte 1)))
```
---
    (1 0 66)

### one byte put in, the newline count kept

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab")
  (def v (b version))
  (b insert-byte! 1 10)
  (list (b newlines) (b end) (Str8 sub 0 3 (b text)) (- (b version) v)))
```
---
    (1 3 "a\nb" 1)

### every change moves the version

```x
(let ((b (Buffer make)))
  (def v0 (b version))
  (b insert! 0 "ab")
  (def v1 (b version))
  (b delete! 0 0)
  (list v0 v1 (b version)))
```
---
    (0 1 2)

### a text past the room grows the block, keeping it

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab")
  (b insert! 1 (Str8 repeat 10240 "x"))
  (list (b end) (b room) (b byte 0) (b byte 10241)))
```
---
    (10242 20482 97 98)

### clearing it leaves no text

```x
(let ((b (Buffer make)))
  (b insert! 0 "a\nb\n")
  (b clear!)
  (list (b end) (b newlines) (b room)))
```
---
    (0 0 10240)

## reading it

### bytes copied out, with their count

```x
(let ((b (Buffer make)))
  (b insert! 0 "abcdef")
  (let ((c (b copy 2 3))) (list (rest c) (Str8 sub 0 3 (first c)))))
```
---
    (3 "cde")

### a search, byte for byte

```x
(let ((b (Buffer make)))
  (b insert! 0 "abcabc")
  (list (b find 1 5 "ab" 2) (b find 0 3 "ca" 2) (b find-newline 0 6)))
```
---
    (3 -1 -1)

### a search in any case, the byte after the text put back

```x
(let ((b (Buffer make)))
  (b insert! 0 "Hello World\n")
  (b byte-set! 12 7)
  (list (b find-any-case 0 "WORLD") (b find-any-case 7 "hello") (b byte 12)))
```
---
    (6 -1 7)

### where the plain bytes end

```x
(let ((b (Buffer make)))
  (b insert! 0 "ab\tc\n")
  (list (b plain-end 0 (bytes->str (list 9 10))) (b plain-end 3 (bytes->str (list 9 10)))))
```
---
    (2 4)
