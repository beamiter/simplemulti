vim9script

if exists('g:loaded_simplemulti')
  finish
endif
g:loaded_simplemulti = 1

if v:version < 901 || !has('textprop')
  echohl WarningMsg
  echomsg '[SimpleMulti] Vim 9.1 with +textprop is required.'
  echohl None
  finish
endif

g:simplemulti_default_mappings = get(g:, 'simplemulti_default_mappings', 1)
g:simplemulti_max_selections = get(g:, 'simplemulti_max_selections', 1000)

def DefaultMappings(): bool
  var configured: any = g:simplemulti_default_mappings
  if type(configured) == v:t_bool
    return configured
  endif
  return type(configured) == v:t_number ? configured != 0 : true
enddef

command! SimpleMultiNext simplemulti#SelectNext()
command! SimpleMultiAll simplemulti#SelectAll()
command! SimpleMultiAbove simplemulti#Vertical(-1)
command! SimpleMultiBelow simplemulti#Vertical(1)
command! SimpleMultiRemove simplemulti#RemoveCurrent()
command! SimpleMultiClear simplemulti#Clear()
command! -nargs=* SimpleMultiReplace simplemulti#Edit('replace', <q-args>)
command! -nargs=* SimpleMultiInsert simplemulti#Edit('insert', <q-args>)
command! -nargs=* SimpleMultiAppend simplemulti#Edit('append', <q-args>)
command! SimpleMultiDelete simplemulti#Edit('delete', '')
command! SimpleMultiHealth simplemulti#Health()

nnoremap <silent> <Plug>(simplemulti-next) <ScriptCmd>simplemulti#SelectNext()<CR>
nnoremap <silent> <Plug>(simplemulti-all) <ScriptCmd>simplemulti#SelectAll()<CR>
nnoremap <silent> <Plug>(simplemulti-above) <ScriptCmd>simplemulti#Vertical(-1)<CR>
nnoremap <silent> <Plug>(simplemulti-below) <ScriptCmd>simplemulti#Vertical(1)<CR>
nnoremap <silent> <Plug>(simplemulti-clear) <ScriptCmd>simplemulti#Clear()<CR>

# A default key is installed only into a slot that is still free, and only when
# the user has not already routed this <Plug> target somewhere of their own.
# <C-n> in particular is Vim's own "one line down" in Normal mode, so taking it
# unconditionally changed a motion every user already has muscle memory for --
# and whether the plugin or the user won depended only on load order, which is
# not a rule anyone can follow. maparg() answers "is this key still free";
# hasmapto() answers "has the user already bound this action elsewhere", in
# which case they do not also want the default key taken.
if DefaultMappings()
  if maparg('<C-n>', 'n') ==# '' && !hasmapto('<Plug>(simplemulti-next)', 'n')
    nmap <C-n> <Plug>(simplemulti-next)
  endif
  if maparg('<C-Up>', 'n') ==# '' && !hasmapto('<Plug>(simplemulti-above)', 'n')
    nmap <C-Up> <Plug>(simplemulti-above)
  endif
  if maparg('<C-Down>', 'n') ==# '' && !hasmapto('<Plug>(simplemulti-below)', 'n')
    nmap <C-Down> <Plug>(simplemulti-below)
  endif
endif

highlight default SimpleMultiSelection cterm=reverse gui=reverse
highlight default SimpleMultiPrimary cterm=bold,reverse gui=bold,reverse
simplemulti#Setup()

augroup SimpleMulti
  autocmd!
  autocmd TextChanged,TextChangedI * simplemulti#Invalidate()
  autocmd BufWipeout * simplemulti#OnWipe(str2nr(expand('<abuf>')))
  autocmd ColorScheme * call simplemulti#SetupHighlights()
augroup END
