.PHONY: check defcompile test regressions mappings prompt-changes

check: defcompile test regressions mappings prompt-changes

defcompile:
	vim -N -u NONE -n -i NONE -es -S tests/defcompile.vim

test:
	vim -N -u NONE -n -i NONE -es -S tests/vim_smoke.vim

# Needs a 351 KB single line and a 20000-line buffer to put a wall-clock budget
# on <C-n>; the smoke test's two-line fixture is far too small for either
# quadratic scan to show up in.
regressions:
	vim -N -u NONE -n -i NONE -es -S tests/regressions.vim

mappings:
	vim -N -u NONE -n -i NONE -es -S tests/mappings.vim

prompt-changes:
	python3 tests/prompt_changes.py
