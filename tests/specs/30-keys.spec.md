# editor/keys
# @weight 1

Keys reads busybox's keys from a host's bytes.  Each case reads every key
from a list of bytes; `keys-over` answers them in turn, and says a byte is
coming while any are left.

## bytes and sequences

### bytes are themselves

```x
(keys-all (keys-over (list 120 121 10)))
```
---
    (120 121 10)

### an arrow is its code

```x
(list (keys-all (keys-over (list 27 91 65 27 79 66))) (Keys up) (Keys down))
```
---
    ((-2 -3) -2 -3)

### control and alt arrows

```x
(keys-all (keys-over (list 27 91 49 59 53 67 27 91 49 59 51 68 27 102)))
```
---
    (-68 -37 -36)

### the editing keys

```x
(keys-all (keys-over (list 27 91 51 126 27 91 53 126 27 91 70)))
```
---
    (-9 -10 -7)

## Escape

### a lone Escape is the key

```x
(keys-all (keys-over (list 27)))
```
---
    (27)

### an Escape and one byte after it: the Escape, then the byte

```x
(let ((k (keys-over (list 27 120))))
  (def first-key (k key))
  (def idle (k idle?))
  (list first-key idle (k key) (k idle?)))
```
---
    (27 #f 120 #t)

### a run no sequence starts is dropped

```x
(null? (keys-all (keys-over (list 27 91 90 120))))
```
---
    #t

## cursor reports

### a report is its code, the numbers kept

```x
(let ((k (keys-over (list 27 91 53 59 49 48 82 113))))
  (list (k key) (k cursor-reply) (k key)))
```
---
    (-256 (5 . 10) 113)

### what is a report

```x
(List map keys-cursor-report (list "[24;80R" "[0;80R" "[24;R" "[24;80" "[99999;1R"))
```
---
    ((24 . 80) () () () ())

## the table

### busybox's sequences, shortest first

```x
(list (List length (Keys sequences)) (first (List last (Keys sequences))))
```
---
    (29 "[1;5D")
