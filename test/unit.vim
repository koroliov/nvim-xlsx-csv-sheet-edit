set rtp^=.
let s:test_dir = fnamemodify(expand('<sfile>'), ':p:h')

execute 'source ' . fnameescape(s:test_dir . '/helpers.vim')

" cases
call CreateCsvDotJsonFileTest('case-01')

if !empty(v:errors)
  call writefile(v:errors, '/dev/stderr')
  cquit 1
endif

qa!
