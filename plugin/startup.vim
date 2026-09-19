function! s:CheckNamingConflicts(commands) abort
  for l:command in a:commands
    if exists(':' . l:command) != 0
      echoerr printf(
            \ '[xlsx-csv-sheet-edit] Cannot load: :%s already exists',
            \ l:command)
      return 0
    endif
  endfor

  return 1
endfunction

if !s:CheckNamingConflicts(['XlsxCsvOpenJson', 'XlsxCsvCopyTsv'])
  finish
endif

command -nargs=1 XlsxCsvOpenJson echo 'XlsxCsvOpenJson run OK!'
command -nargs=0 XlsxCsvCopyTsv echo 'XlsxCsvCopyTsv run OK!'
