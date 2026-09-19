function s:DoNamingConflictsExist() abort
  let l:checks = [
    \ ['XlsxCsv', 'command'],
    \ ['g:xlsx_csv_', 'var'],
  \ ]
  for l:check in l:checks
    let l:conflicts = getcompletion(l:check[0], l:check[1])
    if !empty(l:conflicts)
      echoerr printf(
        \ 'Cannot load: namespace %s, %s already taken.
        \ Check other plugins or your .vimrc',
        \ l:check[0], l:check[1])
      return 1
    endif
  endfor

  return 0
endfunction

function s:CheckMillerVersion() abort
  if !executable('mlr')
    call xlsx_csv#EchoError('Failed to load: Miller (mlr) is not installed or is not on PATH.')
    return 0
  endif

  let l:version_output = systemlist(['mlr', '--version'])
  if v:shell_error != 0
    call xlsx_csv#EchoError('Failed to load: could not determine the Miller version.')
    return 0
  endif

  let l:version = matchstr(join(l:version_output, ' '), '\v\d+\.\d+(\.\d+)?')
  if empty(l:version)
    call xlsx_csv#EchoError('Failed to load: could not parse the Miller version.')
    return 0
  endif

  let l:parts = split(l:version, '\.')
  let l:major = str2nr(l:parts[0])
  let l:minor = str2nr(l:parts[1])
  if l:major < 6 || (l:major == 6 && l:minor < 21)
    let l:msg = printf(
      \ 'Failed to load: Miller %s is too old; version 6.21 or newer is required.',
      \ l:version)
    call xlsx_csv#EchoError(msg)
    return 0
  endif

  return 1
endfunction

" execution

if s:DoNamingConflictsExist()
  finish
endif

if !s:CheckMillerVersion()
  finish
endif


command -nargs=1 -complete=file XlsxCsvOpenAsJson call xlsx_csv#OpenAsJson(<q-args>)
command -nargs=0 XlsxCsvCopyTsv echo 'XlsxCsvCopyTsv run OK!'
