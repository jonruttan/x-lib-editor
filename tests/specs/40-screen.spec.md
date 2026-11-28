# editor/screen
# @weight 1

A Pane draws rows into a rectangle of the terminal, or the whole of it, and
answers the escapes.  `esc-shown` prints each Escape as `^[`.

## drawing

### the first rows are written whole, placed in the rectangle

```x
(esc-shown ((Pane make (list 2 4 3 10)) draw! (list "ab" "cd") () #f))
```
---
    "^[[3;5Hab^[[4;5Hcd"

### a row again: only what differs

```x
(let ((p (Pane make ())))
  (p draw! (list "abcd" "wxyz") () #f)
  (esc-shown (p draw! (list "axyd" "wxyz") () #f)))
```
---
    "^[[1;2Hxy"

### the same rows: nothing

```x
(let ((p (Pane make ())))
  (p draw! (list "abc") () #f)
  (p draw! (list "abc") () #f))
```
---
    ""

### forced: every row whole

```x
(let ((p (Pane make ())))
  (p draw! (list "abc") () #f)
  (esc-shown (p draw! (list "abc") () #t)))
```
---
    "^[[1;1Habc"

### rows said to be shown are not written

```x
(let ((p (Pane make ())))
  (p reset! (list "   "))
  (list (p draw! (list "   ") () #f) (p shown)))
```
---
    ("" ("   "))

## colour

### a run of one class: its sequence, the text, a reset

```x
(let ((p ((Pane make ()) colour! (fn (_ c) "S"))))
  (esc-shown (p draw! (list "abc") (list " A ") #f)))
```
---
    "^[[1;1HaSb^[[0mc"

### the cells alone changed: their columns written again

```x
(let ((p ((Pane make ()) colour! (fn (_ c) "S"))))
  (p draw! (list "abcd") (list "    ") #f)
  (esc-shown (p draw! (list "abcd") (list "  A ") #f)))
```
---
    "^[[1;3HSc^[[0m"

## the terminal

### a rectangle is cleared with spaces

```x
(esc-shown ((Pane make (list 0 0 2 3)) clear))
```
---
    "^[[1;1H   ^[[2;1H   "

### the whole terminal with ESC [ H ESC [ J

```x
(esc-shown ((Pane make ()) clear))
```
---
    "^[[H^[[J"

### a row's end, in a rectangle and on the whole terminal

```x
(list (esc-shown ((Pane make (list 1 2 2 5)) clear-eol 0 2))
      (esc-shown ((Pane make ()) clear-eol 0 2)))
```
---
    ("   ^[[2;5H" "^[[K")

### the alternate screen is the whole terminal's

```x
(list (esc-shown ((Pane make ()) enter)) ((Pane make (list 0 0 5 5)) enter)
      (esc-shown ((Pane make ()) leave)))
```
---
    ("^[[?1049h" "" "^[[?1049l")

### the cursor is clipped to the pane

```x
(list (esc-shown (pane-goto 0 0 24 80 30 -1)) (esc-shown (pane-goto 5 10 3 4 1 2)))
```
---
    ("^[[24;1H" "^[[7;13H")

### a resize forgets what was drawn

```x
(let ((p (Pane make ())))
  (p draw! (list "abc") () #f)
  (p resize! 10 40)
  (list (p view) (esc-shown (p draw! (list "abc") () #f))))
```
---
    ((0 0 10 40 #t) "^[[1;1Habc")
