# x-lib-editor

What an editor is made of, for [x-lang](https://github.com/jonruttan/x-lang),
written in x: a text and its undo, kept apart from any one editor's keys or
screen.

x-lib-editor holds the bundle `editor`. It is a library: it has modules and no
entry.

- `editor/buffer`, class `Buffer`: a text as one block of bytes, busybox vi's,
  with every place in it an offset. It counts its newlines and its changes,
  and finds lines, newlines and text with libc. A cursor is not the buffer's:
  each editor keeps its own. Its line walks are also functions,
  `buffer-begin-line`, `buffer-next-line` and the rest, on a block's address
  and length: an editor that keeps its buffer's `view` walks lines on every
  key without a send.
- `editor/undo`, class `Undo`: busybox vi's undo for one Buffer, with
  chained records and a queue that makes a run of typing one change. A pop
  answers what it undid and prints nothing.

```x
(import editor/buffer Buffer)
(import editor/undo Undo)
(let ((b (Buffer make)))
  (let ((u (Undo make b)))
    (u push-insert! 0 6 (Undo alone))
    (b insert! 0 "hello\n")
    (u pop!)
    (b end)))
```

[x-lib-editor-vi](https://github.com/jonruttan/x-lib-editor-vi) is vi on top
of it.

## Using it

Installed under x's `bundles/` directory, an import of an `editor/` module
finds it with nothing declared:

```sh
make install
```

A bundle that depends on it says so in its `bundle.xon`:

```x
(requires-bundle "editor" "v0.1.0" "jonruttan/x-lib-editor")
```

## Working on it

```sh
make check
```

## Licence

MIT No Attribution.
