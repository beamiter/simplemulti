vim9script

var s_applying = false

# One cached Occurrences() answer, keyed on the buffer, the word and the text.
# SelectNext() used to rescan the whole buffer on every press -- 11.7 ms per
# <C-n> on a 20000-line buffer holding three occurrences of the word, paid in
# full again on the press that finds nothing left to select.  Now the first
# press pays it and the rest cost 0.05 ms.  The answer only moves
# when one of those three key parts moves, and painting the selections does not
# move any of them: prop_add() and prop_remove() leave b:changedtick alone
# (measured), so the entry survives the Refresh() that every press triggers.
# One entry is enough because a multi-cursor session works on one word at a
# time, and keying on bufnr() means switching buffers cannot serve a stale list.
var s_cache: dict<any> = {}

# `keys` is the Key() set of `items`, carried alongside so that AddItem() can
# reject a duplicate with a hash lookup.  It used to rebuild the whole key list
# with index(mapnew(...)) on every add, which made a run of selections
# quadratic: 400 <C-Down> presses cost 163 ms, and cost 70 ms once the set
# replaced the rebuild.  `painted` is the [first, last] line range the previous
# Refresh() actually put properties on, so the next one can sweep that range
# instead of the whole buffer, and `painted_tick` is the b:changedtick that
# range was recorded at -- the narrowing is only sound while the text has not
# moved underneath it.  It starts at -1, which no b:changedtick can equal, so
# the first Refresh() of every state sweeps the whole buffer once.
def EmptyState(): dict<any>
  return {items: [], keys: {}, painted: [0, 0], painted_tick: -1,
    word: '', primary: -1, changedtick: b:changedtick}
enddef

def State(): dict<any>
  # A b:simplemulti_state left behind by an older copy of this file -- the
  # buffer-local survives re-sourcing the plugin mid-session -- has no `keys`,
  # no `painted` and no `painted_tick`, and every access to them would throw
  # E716.  Treat a dict of the wrong shape the same as no dict at all.
  if !exists('b:simplemulti_state') || type(b:simplemulti_state) != v:t_dict
      || !has_key(b:simplemulti_state, 'keys') || !has_key(b:simplemulti_state, 'painted')
      || !has_key(b:simplemulti_state, 'painted_tick')
    b:simplemulti_state = EmptyState()
  endif
  return b:simplemulti_state
enddef

export def SetupHighlights()
  highlight default SimpleMultiSelection cterm=reverse gui=reverse
  highlight default SimpleMultiPrimary cterm=bold,reverse gui=bold,reverse
enddef

export def Setup()
  SetupHighlights()
  if empty(prop_type_get('SimpleMultiSelection'))
    prop_type_add('SimpleMultiSelection', {highlight: 'SimpleMultiSelection', combine: true})
  endif
  if empty(prop_type_get('SimpleMultiPrimary'))
    prop_type_add('SimpleMultiPrimary', {highlight: 'SimpleMultiPrimary', combine: true})
  endif
enddef

def Key(item: dict<any>): string
  return $'{item.lnum}:{item.col}'
enddef

def Refresh()
  Setup()
  var state = State()
  # The two sweeps used to run over 1 to line('$') on every press.  That is
  # cheap while the buffer is small and stops being cheap when it is not: with
  # 1000 selections live the pair costs 0.037 ms at 2000 lines, 0.237 ms at
  # 20000, and 1.595 ms at 100000 -- by then three quarters of everything
  # Refresh() does.  Properties of ours can only exist where the previous
  # Refresh() put them, so sweeping that range (widened to cover the lines this
  # call is about to paint, in case a caller reordered items into it) removes
  # exactly the same properties for 0.001 ms.  Clear() keeps the whole-buffer
  # sweep as the backstop for anything that escapes this bookkeeping.
  var sweep_first: number = state.painted[0]
  var sweep_last: number = state.painted[1]
  if state.painted_tick != b:changedtick
    # ...but "properties of ours can only exist where the previous Refresh()
    # put them" stops being true the moment the text moves, because Vim keeps
    # text properties in the undo state.  Undo the :SimpleMultiReplace that
    # Clear() stripped the highlights for and Vim puts every one of them back,
    # on lines this state dict has since forgotten it ever painted; the next
    # <C-n> elsewhere in the buffer would then leave them standing forever.
    # Re-sourcing this file mid-session lands the same way: the fresh state
    # from State() has no memory of what the previous one painted.  So the
    # first Refresh() after any text change sweeps everything, and the presses
    # after it -- which cannot change text, only selections -- narrow again.
    # That is one whole-buffer sweep per session, not one per press.
    sweep_first = 1
    sweep_last = line('$')
  endif
  for item in state.items
    if sweep_first == 0 || item.lnum < sweep_first
      sweep_first = item.lnum
    endif
    if item.lnum > sweep_last
      sweep_last = item.lnum
    endif
  endfor
  if sweep_first > 0
    sweep_last = min([sweep_last, line('$')])
    if sweep_first <= sweep_last
      prop_remove({type: 'SimpleMultiSelection', all: true}, sweep_first, sweep_last)
      prop_remove({type: 'SimpleMultiPrimary', all: true}, sweep_first, sweep_last)
    endif
  endif
  var painted_first = 0
  var painted_last = 0
  for index in range(len(state.items))
    var item = state.items[index]
    var length = item.length
    if length <= 0
      # A Vertical() cursor carries no length; give it one column to show, and
      # nothing at all when it sits past the end of its line.  getline() is
      # only needed for those, so it stays out of the common path where every
      # item already knows how wide it is.
      length = item.col <= strlen(getline(item.lnum)) ? 1 : 0
    endif
    if length <= 0
      continue
    endif
    prop_add(item.lnum, item.col, {
      type: index == state.primary ? 'SimpleMultiPrimary' : 'SimpleMultiSelection',
      length: length,
    })
    if painted_first == 0 || item.lnum < painted_first
      painted_first = item.lnum
    endif
    if item.lnum > painted_last
      painted_last = item.lnum
    endif
  endfor
  state.painted = [painted_first, painted_last]
  state.painted_tick = b:changedtick
  redraw
enddef

# The one pattern both WordAtCursor() and Occurrences() search with, so that
# the word the cursor is on is by construction a word the scan can find.
def WordPattern(word: string): string
  return '\C\V\<' .. escape(word, '\') .. '\>'
enddef

# This used to walk the line run by run from column 1 -- match(text, '\k\+',
# start), matchstr() the run back out, advance, repeat -- which rescans the
# string from each offset and is quadratic in line length.  One <C-n> with the
# cursor near the end of a minified .js/.css/.json line cost 34 ms at 43 KB,
# 287 ms at 175 KB and 1087 ms at 351 KB: a full second of frozen Vim for a
# keypress.  expand('<cword>') answers the same question in 0.0001 ms no matter
# how long the line is, and one matchstrpos() anchored near the cursor recovers
# the start column in 0.012 ms, flat -- 35 ms for the whole press at 351 KB,
# the rest of which is Occurrences() walking that one enormous line.
#
# Taking the word from <cword> rather than from \k\+ also settles a
# disagreement that mattered on multibyte text.  \k\+ treats a run of keyword
# characters as one word whatever scripts they mix; <cword> and the \< \> atoms
# both split it where mb_get_class() changes.  So with the cursor on `name`
# inside `変数name` the old scan called the word `変数name`, and Occurrences()
# then hunted for \<変数name\> -- never the \<name\> the user was pointing at,
# and never the standalone `name` elsewhere in the buffer.  Now both ends agree,
# because the anchor below searches with the very pattern Occurrences() uses.
def WordAtCursor(): dict<any>
  var word = expand('<cword>')
  # <cword> falls forward to the next word on the line when the cursor sits on
  # whitespace, and hands back a run of punctuation when it sits on
  # punctuation.  The second is not a word at all; the first is a word, but not
  # this one, and the span check below is what rejects it.
  if empty(word) || word !~# '^\k\+$'
    return {}
  endif
  var cursor_col = col('.')
  # An occurrence covering the cursor cannot begin earlier than
  # cursor_col - strlen(word), and two occurrences of the same word cannot
  # overlap, so the first match at or after that probe is the one under the
  # cursor.  The probe deliberately starts short of the word and so can land
  # inside whatever precedes it, which is why the fourth argument is here:
  # given a {start} but no {count}, match() searches a copy of the string
  # truncated at {start}, and \< then fires on the truncated head --
  # match('abcdef', '\<def\>', 3) claims a word boundary in the middle of
  # `abcdef` where match('abcdef', '\<def\>', 3, 1) correctly finds none.  The
  # two agree at every probe this actually produces (5021 cursor positions over
  # a mixed-script corpus, no disagreement), so the {count} is not covering for
  # a live bug -- it is what makes the anchor correct on its own terms instead
  # of by an accident of the arithmetic above it.
  var hit = matchstrpos(getline('.'), WordPattern(word),
    max([0, cursor_col - strlen(word)]), 1)
  if hit[1] < 0 || cursor_col < hit[1] + 1 || cursor_col > hit[2]
    return {}
  endif
  return {word: word, lnum: line('.'), col: hit[1] + 1, length: strlen(word)}
enddef

# A per-line match() walk, and it stays one.  Both of the obvious replacements
# lose on the input this plugin has to survive: matchbufline() has no result
# cap where the loop below stops at `maximum`, and a searchpos() loop -- which
# is 5x faster here for a word with a handful of hits in a 20000-line buffer
# (2.6 ms against 13.3 ms) -- costs 105 ms against this loop's 19 ms on a
# 351 KB single line full of matches, because it pays per match on a line it
# has to re-walk.  That line is exactly the minified .js/.css case WordAtCursor()
# was rewritten for, so it is not the case to regress.  What made the per-press
# cost go away was not scanning faster but not scanning again: see
# CachedOccurrences().
def Occurrences(word: string): list<dict<any>>
  var out: list<dict<any>> = []
  if empty(word)
    return out
  endif
  var pattern = WordPattern(word)
  var maximum = get(g:, 'simplemulti_max_selections', 1000)
  for lnum in range(1, line('$'))
    var text = getline(lnum)
    var start = 0
    while start < strlen(text)
      var found = match(text, pattern, start)
      if found < 0
        break
      endif
      add(out, {lnum: lnum, col: found + 1, length: strlen(word)})
      if len(out) >= maximum
        return out
      endif
      start = found + max([1, strlen(word)])
    endwhile
  endfor
  return out
enddef

def CachedOccurrences(word: string): list<dict<any>>
  # The cap belongs in the key as much as the buffer, the word and the text do:
  # it is an input to Occurrences(), not a property of the buffer, and raising
  # it is the one way a user changes the answer without touching a character.
  # Without it, `:SimpleMultiAll` with the cap at 5 and then again with it at 40
  # comes back with 5 -- a truncated selection, which is worse than the scan the
  # cache saved.
  var maximum = get(g:, 'simplemulti_max_selections', 1000)
  if get(s_cache, 'bufnr', -1) == bufnr()
      && get(s_cache, 'word', '') ==# word
      && get(s_cache, 'changedtick', -1) == b:changedtick
      && get(s_cache, 'maximum', -1) == maximum
    return s_cache.items
  endif
  var items = Occurrences(word)
  s_cache = {bufnr: bufnr(), word: word, changedtick: b:changedtick,
    maximum: maximum, items: items}
  return items
enddef

def AddItem(item: dict<any>): bool
  var state = State()
  var key = Key(item)
  if has_key(state.keys, key)
    return false
  endif
  add(state.items, item)
  state.keys[key] = true
  state.primary = len(state.items) - 1
  state.changedtick = b:changedtick
  cursor(item.lnum, item.col)
  Refresh()
  return true
enddef

export def SelectNext()
  if !&l:modifiable || &l:readonly
    return
  endif
  var state = State()
  if empty(state.items)
    var first = WordAtCursor()
    if empty(first)
      return
    endif
    state.word = first.word
    AddItem(first)
  endif
  var occurrences = CachedOccurrences(state.word)
  if empty(occurrences)
    return
  endif
  # Occurrences come back in buffer order, so the wrapped search this wants is
  # just the first unselected one past the primary, falling back to the first
  # unselected one overall.  This used to split all thousand of them into two
  # lists and concatenate those into a third, to read one item out of the
  # front.  state.keys is already the selected set, so the skip test is a hash
  # lookup instead of the key list AddItem() rebuilt for the same purpose.
  var primary = state.items[state.primary]
  var after: dict<any> = {}
  var before: dict<any> = {}
  for item in occurrences
    if has_key(state.keys, Key(item))
      continue
    endif
    if item.lnum > primary.lnum || (item.lnum == primary.lnum && item.col > primary.col)
      after = item
      break
    elseif empty(before)
      before = item
    endif
  endfor
  var candidate = empty(after) ? before : after
  if !empty(candidate)
    AddItem(candidate)
  endif
enddef

export def SelectAll()
  var state = State()
  if empty(state.word)
    var first = WordAtCursor()
    if empty(first)
      return
    endif
    state.word = first.word
  endif
  # copy(): CachedOccurrences() hands back the list it is holding onto, and
  # AddItem() and RemoveCurrent() mutate state.items in place.  Without the
  # copy a later <C-n> or <C-x> would edit the cache from under the next press.
  state.items = copy(CachedOccurrences(state.word))
  state.keys = {}
  for item in state.items
    state.keys[Key(item)] = true
  endfor
  state.primary = empty(state.items) ? -1 : 0
  state.changedtick = b:changedtick
  Refresh()
enddef

export def Vertical(delta: number)
  if delta != 1 && delta != -1
    return
  endif
  var state = State()
  if empty(state.items)
    AddItem({lnum: line('.'), col: col('.'), length: 0})
  endif
  var primary = state.items[state.primary]
  var target_line = primary.lnum + delta
  if target_line < 1 || target_line > line('$')
    return
  endif
  AddItem({
    lnum: target_line,
    col: min([primary.col, strlen(getline(target_line)) + 1]),
    length: 0,
  })
enddef

export def RemoveCurrent()
  var state = State()
  if state.primary < 0 || state.primary >= len(state.items)
    return
  endif
  remove(state.keys, Key(state.items[state.primary]))
  remove(state.items, state.primary)
  state.primary = empty(state.items) ? -1 : min([state.primary, len(state.items) - 1])
  if empty(state.items)
    state.word = ''
  endif
  Refresh()
enddef

def CompareDescending(left: dict<any>, right: dict<any>): number
  if left.lnum != right.lnum
    return right.lnum - left.lnum
  endif
  return right.col - left.col
enddef

def ApplyOne(item: dict<any>, kind: string, value: string)
  var text = getline(item.lnum)
  var start = item.col - 1
  var length = get(item, 'length', 0)
  var replacement = kind ==# 'replace' ? value
    : kind ==# 'insert' ? value .. strpart(text, start, length)
    : kind ==# 'append' ? strpart(text, start, length) .. value
    : ''
  setline(item.lnum,
    strpart(text, 0, start) .. replacement .. strpart(text, start + length))
enddef

export def Edit(kind: string, argument: string)
  var state = State()
  if empty(state.items) || index(['replace', 'insert', 'append', 'delete'], kind) < 0
    return
  endif
  var value = argument
  if empty(value) && kind !=# 'delete'
    value = input($'SimpleMulti {kind}: ')
  endif
  var items = sort(deepcopy(state.items), CompareDescending)
  s_applying = true
  try
    var first = true
    for item in items
      if !first
        silent! undojoin
      endif
      ApplyOne(item, kind, value)
      first = false
    endfor
  finally
    s_applying = false
  endtry
  Clear()
enddef

export def Clear()
  if exists('b:simplemulti_state')
    b:simplemulti_state = EmptyState()
  endif
  # Dropping the cached scan here is not what keeps it correct -- the bufnr,
  # word and changedtick in its key do that -- it just stops a finished session
  # from holding its thousand-item list until the next word is picked.
  s_cache = {}
  # The one sweep that stays whole-buffer.  Refresh() only clears the range it
  # painted, so this is where a property that outlived its bookkeeping goes.
  prop_remove({type: 'SimpleMultiSelection', all: true}, 1, line('$'))
  prop_remove({type: 'SimpleMultiPrimary', all: true}, 1, line('$'))
  redraw
enddef

export def Invalidate()
  if s_applying || !exists('b:simplemulti_state')
    return
  endif
  var state = State()
  if !empty(state.items) && state.changedtick != b:changedtick
    Clear()
  endif
enddef

export def GetState(): dict<any>
  return deepcopy(State())
enddef

export def Health()
  var state = State()
  echomsg 'SimpleMulti health'
  echomsg $'  textprop: {has("textprop") ? "yes" : "no"}'
  echomsg $'  selections: {len(state.items)}'
  echomsg $'  cap: {get(g:, "simplemulti_max_selections", 1000)}'
enddef
