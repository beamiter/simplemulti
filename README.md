# SimpleMulti

Selection-first multiple editing for Vim9. `<C-n>` selects the word under the
cursor and then its next occurrence; `:SimpleMultiAll` selects every exact
occurrence. Vertical cursors, insert, append, replace and delete operations are
applied as one undo block.

Vertical cursors keep their display column across tabs and short lines, while
edits on a short line clamp safely to its end.

`g:simplemulti_max_selections` caps a scan at 1000 selections by default;
non-positive or non-numeric values fall back to that safe default.

Unlike UI-heavy multicursor emulation, SimpleMulti keeps ordinary Vim modes
intact and exposes explicit batch-edit commands. It works unchanged in
SimpleRemote buffers because edits remain normal buffer modifications.
