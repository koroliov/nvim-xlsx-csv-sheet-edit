set rtp^=.
let s:test_dir = fnamemodify(expand('<sfile>'), ':p:h')
execute 'source ' . fnameescape(s:test_dir . '/helpers.vim')

" cases CreateCsvDotJsonFileTest
call CreateCsvDotJsonFileTest('case-01')

" cases ConvertJsonToFormatTest
call ConvertJsonToFormatTest('case-01', 'tsv')

if !empty(v:errors)
  call writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qa!
