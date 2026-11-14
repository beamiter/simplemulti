vim9script

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplemulti.vim')

new
setline(1, ['alpha beta alpha', 'alpha tail'])
cursor(1, 2)
simplemulti#SelectNext()
assert_equal(2, len(simplemulti#GetState().items))
simplemulti#SelectNext()
assert_equal(3, len(simplemulti#GetState().items))
simplemulti#Edit('replace', 'x')
assert_equal(['x beta x', 'x tail'], getline(1, 2))
assert_equal(0, len(simplemulti#GetState().items))

cursor(1, 1)
simplemulti#Vertical(1)
assert_equal(2, len(simplemulti#GetState().items))
simplemulti#Edit('insert', '>')
assert_equal(['>x beta x', '>x tail'], getline(1, 2))

setline(1, ['one one', 'one'])
cursor(1, 1)
simplemulti#SelectAll()
assert_equal(3, len(simplemulti#GetState().items))
simplemulti#Edit('delete', '')
assert_equal([' ', ''], getline(1, 2))

# Empty/cancelled prompts must not change text or discard the live session.
# 'n' queues unmapped input for input(); typed Escape can flush typeahead and
# make a headless Vim exit before the assertions are reached.
for kind in ['replace', 'insert', 'append']
  for answer in ["\<Esc>", "\<CR>"]
    setline(1, ['keep keep', 'keep'])
    cursor(1, 1)
    simplemulti#SelectAll()
    var before = simplemulti#GetState()
    var tick = b:changedtick
    feedkeys(answer, 'n')
    simplemulti#Edit(kind, '')
    assert_equal(['keep keep', 'keep'], getline(1, 2),
      'cancelled ' .. kind .. ' changed text')
    assert_equal(tick, b:changedtick, 'cancelled edit created a text change')
    assert_equal(before, simplemulti#GetState(),
      'cancelled edit discarded the selection session')
    simplemulti#Clear()
  endfor
endfor
# A confirmed nonempty answer still applies, and explicit Delete still erases.
cursor(1, 1)
simplemulti#SelectAll()
feedkeys("new\<CR>", 'n')
simplemulti#Edit('replace', '')
assert_equal(['new new', 'new'], getline(1, 2))
cursor(1, 1)
simplemulti#SelectAll()
simplemulti#Edit('delete', '')
assert_equal([' ', ''], getline(1, 2))

assert_equal(2, exists(':SimpleMultiNext'))
assert_match('simplemulti', maparg('<C-n>', 'n'))
assert_true(exists('#SimpleMulti#ColorScheme'),
  'no ColorScheme autocmd restores selection highlights')
assert_true(exists('#SimpleMulti#BufWipeout'),
  'no BufWipeout autocmd drops the occurrence cache')

try
  simplemulti#Edit('nope', 'x')
catch
  assert_report('an unknown edit kind threw: ' .. v:exception)
endtry

b:simplemulti_state = {keys: {}, painted: [], painted_tick: 0}
try
  simplemulti#Clear()
catch
  assert_report('an incomplete restored selection state threw: ' .. v:exception)
endtry

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
