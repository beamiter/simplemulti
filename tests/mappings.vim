vim9script

# Default-mapping guard.  plugin/simplemulti.vim is vim9script, so
# `if g:simplemulti_default_mappings` with a list or the string '0' is E745 /
# E1135 at source time and <C-n> is never installed.

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
const PLUGIN = ROOT .. '/plugin/simplemulti.vim'

def Load()
  if exists('g:loaded_simplemulti')
    unlet g:loaded_simplemulti
  endif
  execute 'source ' .. fnameescape(PLUGIN)
enddef

const DEFAULT_KEYS = [['<C-n>', 'n'], ['<C-Up>', 'n'], ['<C-Down>', 'n']]

def ClearMaps()
  for [lhs, mode] in DEFAULT_KEYS
    if maparg(lhs, mode) !=# ''
      execute mode .. 'unmap ' .. lhs
    endif
  endfor
enddef

ClearMaps()
Load()
assert_match('simplemulti-next', maparg('<C-n>', 'n'),
  '<C-n> was not installed on a free key')

ClearMaps()
nnoremap <C-n> :echo "user owns C-n"<CR>
Load()
assert_match('user owns C-n', maparg('<C-n>', 'n'),
  'the default overwrote a <C-n> the user had already bound')
assert_match('simplemulti-below', maparg('<C-Down>', 'n'),
  '<C-Down> was skipped because <C-n> was bound')
nunmap <C-n>

ClearMaps()
nmap <F8> <Plug>(simplemulti-next)
Load()
assert_equal('', maparg('<C-n>', 'n'),
  '<C-n> was installed even though the user had routed the action to <F8>')
nunmap <F8>

ClearMaps()
g:simplemulti_default_mappings = '0'
try
  Load()
catch
  assert_report('a string default-mappings flag threw at load: ' .. v:exception)
endtry
assert_match('simplemulti-next', maparg('<C-n>', 'n'),
  'a mistyped mappings flag skipped the defaults instead of falling back')
g:simplemulti_default_mappings = []
try
  Load()
catch
  assert_report('a list default-mappings flag threw at load: ' .. v:exception)
endtry
g:simplemulti_default_mappings = 0
ClearMaps()
Load()
for [lhs, mode] in DEFAULT_KEYS
  assert_equal('', maparg(lhs, mode),
    printf('%smap %s was installed with default mappings switched off', mode, lhs))
endfor
g:simplemulti_default_mappings = 1

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
