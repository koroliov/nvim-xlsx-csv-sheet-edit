function s:DoNamingConflictsExist() abort
  let l:checks = [
    \ ['XlsxCsv', 'command'],
    \ ['g:xlsx_csv_', 'var'],
  \ ]
  for l:check in l:checks
    let l:conflicts = getcompletion(l:check[0], l:check[1])
    if !empty(l:conflicts)
      echoerr printf(
        \ '[xlsx-csv-sheet-edit] Cannot load: namespace %s, %s already taken.
        \ Check other plugins or your .vimrc',
        \ l:check[0], l:check[1])
      return 1
    endif
  endfor

  return 0
endfunction

" execution

if s:DoNamingConflictsExist()
  finish
endif


command -nargs=1 XlsxCsvOpenJson call xlsx_csv#OpenJson(<q-args>)
command -nargs=0 XlsxCsvCopyTsv echo 'XlsxCsvCopyTsv run OK!'
