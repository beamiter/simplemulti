vim9script

var s_applying = false

def EmptyState(): dict<any>
  return {items: [], word: '', primary: -1, changedtick: b:changedtick}
enddef

def State(): dict<any>
  if !exists('b:simplemulti_state') || type(b:simplemulti_state) != v:t_dict
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
  prop_remove({type: 'SimpleMultiSelection', all: true}, 1, line('$'))
  prop_remove({type: 'SimpleMultiPrimary', all: true}, 1, line('$'))
  var state = State()
  for index in range(len(state.items))
    var item = state.items[index]
    var text = getline(item.lnum)
    var length = item.length > 0 ? item.length
      : (item.col <= strlen(text) ? 1 : 0)
    if length <= 0
      continue
    endif
    prop_add(item.lnum, item.col, {
      type: index == state.primary ? 'SimpleMultiPrimary' : 'SimpleMultiSelection',
      length: length,
    })
  endfor
  redraw
enddef

def WordAtCursor(): dict<any>
  var text = getline('.')
  var cursor_col = col('.')
  var start = 0
  while start < strlen(text)
    var found = match(text, '\k\+', start)
    if found < 0
      break
    endif
    var word = matchstr(text, '\k\+', found)
    var finish = found + strlen(word)
    if cursor_col >= found + 1 && cursor_col <= finish
      return {word: word, lnum: line('.'), col: found + 1, length: strlen(word)}
    endif
    start = finish
  endwhile
  return {}
enddef

def Occurrences(word: string): list<dict<any>>
  var out: list<dict<any>> = []
  if empty(word)
    return out
  endif
  var pattern = '\C\V\<' .. escape(word, '\') .. '\>'
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

def AddItem(item: dict<any>): bool
  var state = State()
  var key = Key(item)
  if index(mapnew(state.items, (_, value) => Key(value)), key) >= 0
    return false
  endif
  add(state.items, item)
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
  var occurrences = Occurrences(state.word)
  if empty(occurrences)
    return
  endif
  var selected: dict<bool> = {}
  for item in state.items
    selected[Key(item)] = true
  endfor
  var primary = state.items[state.primary]
  var after: list<dict<any>> = []
  var before: list<dict<any>> = []
  for item in occurrences
    if has_key(selected, Key(item))
      continue
    endif
    if item.lnum > primary.lnum || (item.lnum == primary.lnum && item.col > primary.col)
      add(after, item)
    else
      add(before, item)
    endif
  endfor
  var candidates = after + before
  if !empty(candidates)
    AddItem(candidates[0])
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
  state.items = Occurrences(state.word)
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
