# SimpleMulti

Selection-first multiple editing for Vim9. `<C-n>` selects the word under the
cursor and then its next occurrence; `:SimpleMultiAll` selects every exact
occurrence. Vertical cursors, insert, append, replace and delete operations are
applied as one undo block.

Unlike UI-heavy multicursor emulation, SimpleMulti keeps ordinary Vim modes
intact and exposes explicit batch-edit commands. It works unchanged in
SimpleRemote buffers because edits remain normal buffer modifications.
