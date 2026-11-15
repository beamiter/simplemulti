#!/usr/bin/env python3
"""Exercise actual input() waits: timers may invalidate a pending multi-edit."""
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = r'''
vim9script
set nocompatible nomore
execute 'set runtimepath^=' .. fnameescape($SIMPLEMULTI_ROOT)
runtime plugin/simplemulti.vim
setline(1, ['alpha one', 'alpha two'])
cursor(1, 1)
simplemulti#SelectAll()
var origin = bufnr()
var fired = false
var failure = ''
def DuringPrompt(_timer: number)
  fired = true
  try
    if $SIMPLEMULTI_CASE ==# 'text'
      setline(1, ['prefix alpha one', 'prefix alpha two'])
    elseif $SIMPLEMULTI_CASE ==# 'switch'
      new
      setline(1, ['other buffer one', 'other buffer two'])
    elseif $SIMPLEMULTI_CASE ==# 'readonly'
      setlocal readonly
    elseif $SIMPLEMULTI_CASE ==# 'nomodifiable'
      setlocal nomodifiable
    elseif $SIMPLEMULTI_CASE ==# 'clear'
      simplemulti#Clear()
    elseif $SIMPLEMULTI_CASE ==# 'selection'
      simplemulti#RemoveCurrent()
    endif
  catch
    failure = v:exception
  finally
    feedkeys("X\<CR>", 'n')
  endtry
enddef
timer_start(50, DuringPrompt)
try
  simplemulti#Edit($SIMPLEMULTI_KIND, '')
catch
  assert_report('edit threw: ' .. v:exception)
endtry
assert_true(fired, 'timer never ran inside input()')
assert_equal('', failure, 'timer callback failed')
var expected = ['alpha one', 'alpha two']
if $SIMPLEMULTI_CASE ==# 'text'
  expected = ['prefix alpha one', 'prefix alpha two']
  assert_equal([], simplemulti#GetState().items, 'stale selections survived')
elseif $SIMPLEMULTI_CASE ==# 'unchanged'
  expected = $SIMPLEMULTI_KIND ==# 'replace' ? ['X one', 'X two']
    : $SIMPLEMULTI_KIND ==# 'insert' ? ['Xalpha one', 'Xalpha two']
    : ['alphaX one', 'alphaX two']
elseif $SIMPLEMULTI_CASE ==# 'switch'
  assert_equal(['other buffer one', 'other buffer two'], getline(1, '$'),
    'pending edit corrupted the new buffer')
elseif $SIMPLEMULTI_CASE ==# 'selection'
  assert_equal(1, len(simplemulti#GetState().items), 'selection change was lost')
endif
assert_equal(expected, getbufline(origin, 1, '$'), 'pending edit changed origin')
writefile(empty(v:errors) ? ['PASS'] : v:errors, $SIMPLEMULTI_RESULT)
qa!
'''


def main():
    vim = shutil.which('vim')
    if not vim:
        raise RuntimeError('vim is required')
    with tempfile.TemporaryDirectory(prefix='simplemulti-prompt-') as directory:
        script = Path(directory) / 'prompt.vim'
        script.write_text(SCRIPT)
        for kind in ('replace', 'insert', 'append'):
            for case in ('text', 'switch', 'readonly', 'nomodifiable',
                         'clear', 'selection', 'unchanged'):
                result = Path(directory) / f'{kind}-{case}.txt'
                env = dict(os.environ, TERM='xterm', SIMPLEMULTI_ROOT=str(ROOT),
                           SIMPLEMULTI_KIND=kind, SIMPLEMULTI_CASE=case,
                           SIMPLEMULTI_RESULT=str(result))
                master, slave = pty.openpty()
                process = subprocess.Popen(
                    [vim, '-N', '-u', 'NONE', '-n', '-i', 'NONE', '-S', str(script)],
                    stdin=slave, stdout=slave, stderr=slave, env=env)
                os.close(slave)
                output = bytearray()
                try:
                    deadline = time.monotonic() + 10
                    while process.poll() is None and time.monotonic() < deadline:
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                output.extend(os.read(master, 65536))
                            except OSError:
                                break
                    process.wait(timeout=max(0.1, deadline - time.monotonic()))
                    assert process.returncode == 0, (kind, case, output.decode(errors='replace'))
                    assert result.is_file(), (kind, case, 'missing completion marker')
                    assert result.read_text() == 'PASS\n', (kind, case, result.read_text())
                finally:
                    if process.poll() is None:
                        process.kill()
                    process.wait()
                    os.close(master)
                print(f'PASS prompt {kind}: {case}')


if __name__ == '__main__':
    main()
