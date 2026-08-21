vim9script

# Two defects are pinned here.
#
#   1. WordAtCursor() walked the cursor's line run by run from column 1 --
#      match(text, '\k\+', start), matchstr() the run back out, advance --
#      which rescans the string from every offset and so is quadratic in line
#      length.  One <C-n> with the cursor near the end of a minified line cost
#      39 ms at 43 KB, 286 ms at 175 KB and 1086 ms at 351 KB: a full second of
#      frozen Vim for one keypress.  It now asks expand('<cword>') for the word
#      and recovers the column with a single anchored matchstrpos().
#
#      Taking the word from <cword> also settled a disagreement about where a
#      word ends.  \k\+ runs straight through a change of script; <cword> and
#      the \< \> atoms Occurrences() searches with both stop where
#      mb_get_class() changes.  So with the cursor on `name` inside `変数name`
#      the old scan called the word `変数name` and the scan then looked for
#      \<変数name\> -- never the \<name\> the cursor was actually on.
#
#   2. SelectNext() called Occurrences() on every press, and Occurrences()
#      walks the whole buffer: 12 ms per <C-n> on a 20000-line buffer, paid
#      again on the press that finds nothing left to select.  The answer is now
#      cached against {bufnr, word, b:changedtick}.  AddItem() rebuilt the
#      whole key list with index(mapnew(...)) to reject duplicates, which made
#      a run of selections quadratic; it carries a key set instead.
#
# The budgets below are wall-clock and deliberately loose: they are set an
# order of magnitude above what the fixed code needs and several times below
# what the code they replaced needed, so a busy machine cannot fail them but a
# return of either defect cannot pass them.  Sections 5 to 7 are not about
# those two defects; they hold down the machinery the fixes introduced -- the
# narrowed property sweep, the cache key, and the widened state dict -- each of
# which can fail quietly in a way no timing assertion would notice.

set nocompatible nomore
set encoding=utf-8
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplemulti.vim')

def Positions(): list<list<number>>
  return mapnew(simplemulti#GetState().items,
    (_, item) => [item.lnum, item.col, item.length])
enddef

# --- 1. A 351 KB single line: the quadratic scan -----------------------------
# 40000 keyword runs on one line.  The cursor sits in the last of them, which
# is the position the old scan had to walk the entire line to reach.
new
const HUGE = repeat('abcdefgh ', 40000)
setline(1, [HUGE])
assert_true(strlen(HUGE) > 100 * 1024,
  printf('the fixture must exceed 100 KB, it is %d bytes', strlen(HUGE)))
cursor(1, strlen(HUGE) - 4)
var started = reltime()
simplemulti#SelectNext()
var elapsed = reltimefloat(reltime(started)) * 1000
assert_true(elapsed < 300,
  printf('<C-n> on a %d KB single line took %.1f ms, budget 300 ms (it was 1086 ms)',
    strlen(HUGE) / 1024, elapsed))

# Fast is worthless if it points at the wrong text: the first item must be the
# run the cursor was actually in, not the first one on the line.
var state = simplemulti#GetState()
assert_equal('abcdefgh', state.word)
assert_equal(strlen(HUGE) - 8, state.items[0].col,
  'the word under the cursor was found at the wrong column')
assert_equal(8, state.items[0].length)
simplemulti#Clear()

# The cursor on the line's trailing whitespace is not on a word at all, and
# <cword> falls forward to the next one -- which on this line is off to the
# left, behind the cursor.  Nothing may be selected.
cursor(1, strlen(HUGE))
simplemulti#SelectNext()
assert_equal(0, len(simplemulti#GetState().items),
  'a cursor on whitespace selected the word <cword> fell forward to')
simplemulti#Clear()
bwipe!

# --- 2. Multibyte words ------------------------------------------------------
# `変数name` is one \k\+ run and two words: \< and \> split it where the script
# changes, and so does <cword>.  Whichever half the cursor is on is the half
# that gets selected, and the other half's occurrences elsewhere are found.
new
setline(1, ['変数name = 1', 'let 変数name = 2', 'name alone', '変数 alone'])

cursor(1, 7)
assert_equal('name', expand('<cword>'), 'the fixture is not testing what it thinks')
simplemulti#SelectAll()
assert_equal('name', simplemulti#GetState().word,
  'the cursor was on `name`; \k\+ used to swallow the CJK head as well')
assert_equal([[1, 7, 4], [2, 11, 4], [3, 1, 4]], Positions(),
  'the standalone `name` on line 3 must be found together with the two tails')
simplemulti#Clear()

cursor(1, 1)
simplemulti#SelectAll()
assert_equal('変数', simplemulti#GetState().word)
assert_equal([[1, 1, 6], [2, 5, 6], [4, 1, 6]], Positions(),
  'the CJK head must select the CJK heads and the standalone one')
simplemulti#Clear()

# A word that is entirely multibyte and stands alone still round-trips, and
# `length` stays a byte count because that is what prop_add() and ApplyOne()
# both want.
setline(1, ['café au café', 'un café'])
if line('$') > 2
  deletebufline('%', 3, line('$'))
endif
cursor(1, 1)
simplemulti#SelectAll()
assert_equal('café', simplemulti#GetState().word)
# `café` is five bytes, so the second one on line 1 starts at column 10, not
# at the column 9 it would occupy if these were character counts.
assert_equal([[1, 1, 5], [1, 10, 5], [2, 4, 5]], Positions(),
  'an accented word must be measured in bytes, not characters')
simplemulti#Edit('replace', 'tea')
assert_equal(['tea au tea', 'un tea'], getline(1, 2),
  'replacing a multibyte word cut it at the wrong byte')
simplemulti#Clear()

# 'iskeyword' decides what a word is, and <cword> honours it -- a CSS-style
# hyphenated name is one word once `-` is a keyword character.
setline(1, ['font-size and font-size', 'font'])
if line('$') > 2
  deletebufline('%', 3, line('$'))
endif
setlocal iskeyword+=-
cursor(1, 3)
simplemulti#SelectAll()
assert_equal('font-size', simplemulti#GetState().word,
  "'iskeyword' was ignored when picking the word under the cursor")
assert_equal([[1, 1, 9], [1, 15, 9]], Positions(),
  'the bare `font` on line 2 is not the same word once - is a keyword char')
setlocal iskeyword-=-
simplemulti#Clear()
bwipe!

# --- 3. The selection cap ----------------------------------------------------
# Occurrences() is the only thing that enforces the cap, and SelectNext() now
# reads a cached copy of its result rather than calling it each press.  If the
# cache ever grew its own path to the buffer, this is what would catch it.
new
var dense: list<string> = []
for i in range(400)
  add(dense, 'target target target target target')
endfor
setline(1, dense)
g:simplemulti_max_selections = 25
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(25, len(simplemulti#GetState().items), 'SelectAll ignored the cap')

# Raising the cap changes the answer without changing a character of the
# buffer, so it has to be part of the cache key.  No Clear() in between: that
# drops the cache and would hide the bug this pins.
g:simplemulti_max_selections = 60
simplemulti#SelectAll()
assert_equal(60, len(simplemulti#GetState().items),
  'raising the cap was served the list the old cap truncated')
g:simplemulti_max_selections = 25
simplemulti#Clear()

cursor(1, 1)
for i in range(60)
  simplemulti#SelectNext()
endfor
assert_equal(25, len(simplemulti#GetState().items),
  'repeated <C-n> walked past the cap the cached scan is supposed to hold')
# Every selection is distinct: the key set replaced the index(mapnew(...))
# duplicate check, and a key set that stopped being maintained would let the
# same position in twice.
var keys = {}
for item in simplemulti#GetState().items
  keys[$'{item.lnum}:{item.col}'] = true
endfor
assert_equal(25, len(keys), 'the same position was selected more than once')
simplemulti#Clear()

# Removing a selection has to take its key out with it, or that position can
# never be selected again.
cursor(1, 1)
simplemulti#SelectNext()
simplemulti#SelectNext()
var before_remove = Positions()
assert_equal(3, len(before_remove))
simplemulti#RemoveCurrent()
assert_equal(2, len(Positions()))
simplemulti#SelectNext()
assert_equal(before_remove, Positions(),
  'a removed position could not be selected again: its key outlived it')
g:simplemulti_max_selections = 1000
simplemulti#Clear()
bwipe!

# A non-positive or mistyped cap falls back to the documented default instead
# of turning the first hit into an accidental cap of one or raising a type
# error from the expression mapping.
new
setline(1, 'alpha alpha alpha')
cursor(1, 1)
g:simplemulti_max_selections = 0
simplemulti#SelectAll()
assert_equal(3, len(Positions()), 'a zero cap unexpectedly meant one selection')
g:simplemulti_max_selections = 'many'
try
  simplemulti#SelectAll()
catch
  assert_report('a mistyped selection cap threw: ' .. v:exception)
endtry
assert_equal(3, len(Positions()), 'a mistyped cap did not fall back to the default')
g:simplemulti_max_selections = 1000
simplemulti#Clear()
bwipe!

# --- 4. The scan is not repeated per keypress --------------------------------
# The first <C-n> pays for the buffer walk.  Every press after it answers from
# the cache, so ten of them together have to cost less than that first one did
# -- a ratio rather than a stopwatch reading, so the assertion means the same
# thing on a fast machine and a loaded one.  Before the cache each press
# repeated the whole walk and the ten cost ten times the first.
new
var big: list<string> = []
for i in range(20000)
  add(big, printf('  var filler_%d = compute(alpha, beta) # padding', i))
endfor
big[10] = '  var rare_identifier = 1'
big[9000] = '  echo rare_identifier'
big[19990] = '  return rare_identifier'
setline(1, big)
cursor(11, 8)
started = reltime()
simplemulti#SelectNext()
var first_press = reltimefloat(reltime(started)) * 1000
started = reltime()
for i in range(10)
  simplemulti#SelectNext()
endfor
var ten_presses = reltimefloat(reltime(started)) * 1000
assert_equal(3, len(Positions()),
  'the fixture must run out of occurrences, so the later presses are pure scan')
assert_true(ten_presses < first_press,
  printf('ten more <C-n> cost %.1f ms against %.1f ms for the first: the buffer '
    .. 'is being rescanned every press', ten_presses, first_press))
simplemulti#Clear()
bwipe!

# --- 5. Refresh() leaves no highlight behind ---------------------------------
# Refresh() sweeps the line range it painted last time instead of the whole
# buffer.  A selection that goes away must take its highlight with it even
# though the sweep no longer covers every line.
new
var spread = repeat(['padding'], 60)
spread[0] = 'alpha here'
spread[49] = 'and alpha too'
setline(1, spread)
cursor(1, 1)
simplemulti#SelectNext()
simplemulti#SelectNext()
assert_equal([[1, 1, 5], [50, 5, 5]], Positions())
assert_equal(1, len(prop_list(50)), 'the far selection was never highlighted')
simplemulti#RemoveCurrent()
assert_equal([[1, 1, 5]], Positions())
assert_equal(0, len(prop_list(50)),
  'the narrowed sweep left the removed selection highlighted on line 50')
assert_equal(1, len(prop_list(1)), 'the surviving selection lost its highlight')
simplemulti#Clear()
assert_equal(0, len(prop_list(1)), 'Clear() left a property behind')
bwipe!

# Vim keeps text properties in the undo state.  Undoing a :SimpleMultiReplace
# therefore puts back every highlight Clear() stripped when the edit was
# applied -- on lines the state dict no longer remembers painting, so a sweep
# narrowed to what it does remember cannot reach them and they stand until the
# next :SimpleMultiClear.  Refresh() sweeps the whole buffer once whenever
# b:changedtick has moved since its last paint, which is what covers this.
new
setline(1, ['alpha beta', 'gamma alpha', 'delta'])
# Seal the fixture into its own undo block so the undo below takes back the
# replacement and not the setline().
&l:undolevels = &l:undolevels
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(2, len(Positions()))
simplemulti#Edit('replace', 'X')
assert_equal(0, len(prop_list(1)) + len(prop_list(2)),
  'Edit() ends in Clear(), which must leave no highlight')
silent undo
assert_equal(['alpha beta', 'gamma alpha', 'delta'], getline(1, 3))
assert_true(len(prop_list(1)) + len(prop_list(2)) > 0,
  'this test assumes undo restores text properties; if it stopped doing so the '
  .. 'assertion below would pass for the wrong reason')
cursor(3, 1)
simplemulti#SelectNext()
assert_equal([[3, 1, 5]], Positions())
assert_equal(1, len(prop_list(3)), 'the new selection was never highlighted')
assert_equal(0, len(prop_list(1)) + len(prop_list(2)),
  'undo put back highlights on lines 1 and 2 and the narrowed sweep never '
  .. 'cleaned them up: two words are still reverse-video with nothing selected')
simplemulti#Clear()
bwipe!

# --- 6. The cached scan follows the buffer -----------------------------------
# The cache is keyed on {bufnr, word, b:changedtick, iskeyword}.  Text
# properties do not move b:changedtick, so painting a selection must not evict
# it; editing the text or changing the definition of a word must.
new
setline(1, ['alpha beta', 'alpha gamma', 'delta'])
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(2, len(Positions()))
simplemulti#Clear()
setline(3, 'alpha delta')
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(3, len(Positions()),
  'the cached scan survived an edit that added an occurrence')
simplemulti#Clear()

# Changing 'iskeyword' changes the meaning of the \< / \> atoms without
# changing either the text, b:changedtick, or the standalone word under the
# cursor.  The prefix in `font-size` is an occurrence before `-` becomes a
# keyword character and is not one afterwards.  No Clear() between the two
# calls: that would discard the cache and hide this regression.
setline(1, ['font-size font'])
if line('$') > 1
  deletebufline('%', 2, line('$'))
endif
setlocal iskeyword-=-
cursor(1, 11)
simplemulti#SelectAll()
assert_equal([[1, 1, 4], [1, 11, 4]], Positions())
setlocal iskeyword+=-
simplemulti#SelectAll()
assert_equal([[1, 11, 4]], Positions(),
  "the cached scan survived an 'iskeyword' change")
setlocal iskeyword-=-
simplemulti#Clear()

# If the new keyword grammar leaves zero occurrences, SelectAll must not keep
# that dead word as a permanent session and ignore what the cursor moves to.
setline(1, ['font-size other'])
setlocal iskeyword-=-
cursor(1, 1)
simplemulti#SelectAll()
assert_equal([[1, 1, 4]], Positions())
setlocal iskeyword+=-
simplemulti#SelectAll()
assert_equal([], Positions())
cursor(1, 11)
simplemulti#SelectAll()
assert_equal('other', simplemulti#GetState().word)
assert_equal([[1, 11, 5]], Positions(),
  'a zero-result word locked later SelectAll calls onto the old session')
setlocal iskeyword-=-
simplemulti#Clear()

# A second buffer with the same word must not be served the first one's answer.
var first = bufnr()
new
setline(1, ['alpha'])
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(1, len(Positions()),
  'a different buffer was served the cached scan of the previous one')
simplemulti#Clear()
bwipe!
execute $'buffer {first}'
bwipe!

# --- 7. A state dict from an older copy of the plugin ------------------------
# b:simplemulti_state outlives a re-source of autoload/simplemulti.vim, so a
# buffer touched before this file gained `keys` and `painted` still holds a
# dict without them, and every access would throw E716.  State() has to treat a
# dict of the wrong shape as no dict at all.
new
setline(1, ['alpha beta', 'alpha gamma'])
b:simplemulti_state = {items: [], word: '', primary: -1, changedtick: b:changedtick}
cursor(1, 1)
try
  simplemulti#SelectNext()
catch
  assert_report('a pre-existing state dict threw: ' .. v:exception)
endtry
assert_equal([[1, 1, 5], [2, 1, 5]], Positions(),
  'the stale state dict was not replaced with a usable one')
simplemulti#Clear()
bwipe!

# The same hazard one revision along: a dict that has `keys` and `painted` but
# not the `painted_tick` Refresh() reads to decide how wide to sweep.  Every
# key this file adds has to be in the guard, not just the first two.
new
setline(1, ['alpha beta', 'alpha gamma'])
b:simplemulti_state = {items: [], keys: {}, painted: [0, 0],
  word: '', primary: -1, changedtick: b:changedtick}
cursor(1, 1)
try
  simplemulti#SelectNext()
catch
  assert_report('a state dict without painted_tick threw: ' .. v:exception)
endtry
assert_equal([[1, 1, 5], [2, 1, 5]], Positions(),
  'the half-old state dict was not replaced with a usable one')
simplemulti#Clear()
bwipe!

# --- 8. One edit, one undo ---------------------------------------------------
# Edit() undojoin()s every replacement after the first so that the whole
# multi-cursor change is a single undo block.  Without it, `u` would walk back
# through the selections one at a time.
new
setline(1, ['alpha beta alpha', 'alpha tail', 'gamma alpha'])
# Seal the setup into its own undo block, or the first replacement joins it and
# undoing would take the fixture with it.
&l:undolevels = &l:undolevels
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(4, len(Positions()))
simplemulti#Edit('replace', 'X')
assert_equal(['X beta X', 'X tail', 'gamma X'], getline(1, 3))
silent undo
assert_equal(['alpha beta alpha', 'alpha tail', 'gamma alpha'], getline(1, 3),
  'one undo did not take back all four replacements: the undojoin is broken')
silent redo
assert_equal(['X beta X', 'X tail', 'gamma X'], getline(1, 3),
  'the redo did not put the whole edit back either')
bwipe!

# --- 9. Vertical cursors keep their display column --------------------------
# A byte column is not a screen column in front of a tab, and clamping to a
# short line must not become the anchor for every line visited afterwards.
new
setlocal tabstop=8
setline(1, ["\talpha", 'x', '        omega'])
cursor(1, 2)
assert_equal(9, virtcol('.'), 'the fixture must start after an eight-cell tab')
simplemulti#Vertical(1)
simplemulti#Vertical(1)
assert_equal([[1, 2, 0], [2, 2, 0], [3, 9, 0]], Positions(),
  'a tab or short row collapsed the vertical cursor column')
simplemulti#Edit('insert', '>')
assert_equal(["\t>alpha", 'x>', '        >omega'], getline(1, 3))
bwipe!

# Public calls can run before TextChanged is delivered.  Stale byte ranges are
# discarded instead of editing unrelated text, and a buffer becoming
# non-modifiable must not throw from setline().
new
setline(1, ['alpha one', 'alpha two'])
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(2, len(Positions()))
setline(1, ['prefix alpha', 'alpha two'])
var externally_changed = getline(1, 2)
try
  simplemulti#Edit('replace', 'X')
catch
  assert_report('editing stale selections threw: ' .. v:exception)
endtry
assert_equal(externally_changed, getline(1, 2),
  'stale selection columns edited unrelated text')
assert_equal([], Positions(), 'stale selections were not discarded')

cursor(2, 1)
simplemulti#SelectAll()
setlocal nomodifiable
try
  simplemulti#Edit('replace', 'X')
catch
  assert_report('a non-modifiable buffer threw: ' .. v:exception)
endtry
assert_equal(externally_changed, getline(1, 2))
setlocal modifiable
simplemulti#Clear()
bwipe!

if !empty(v:errors)
  for error in v:errors
    echomsg error
  endfor
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit 1
endif
echomsg '[SimpleMulti] regression tests passed'
qall!
