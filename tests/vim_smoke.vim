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

assert_equal(2, exists(':SimpleMultiNext'))
assert_match('simplemulti', maparg('<C-n>', 'n'))
if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
