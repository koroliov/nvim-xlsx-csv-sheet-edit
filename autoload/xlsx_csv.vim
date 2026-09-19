function xlsx_csv#EchoError(msgText) abort
  echohl ErrorMsg
  echomsg '[xlsx-csv-sheet-edit] ' . a:msgText
  echohl None
endfunction

function xlsx_csv#OpenJson(file) abort
  if !filereadable(a:file)
    call xlsx_csv#EchoError('Failed to open the file: ' . a:file)
    return
  endif

  let l:output_file = a:file . '.json'
  let l:error_file = tempname()
  let l:command = 'mlr --icsv --ojson cat ' . shellescape(a:file)
        \ . ' > ' . shellescape(l:output_file)
        \ . ' 2> ' . shellescape(l:error_file)
  call system(l:command)
  let l:exit_code = v:shell_error
  let l:error_lines = filereadable(l:error_file)
        \ ? readfile(l:error_file)
        \ : []
  call delete(l:error_file)

  if l:exit_code != 0
    let l:details = join(l:error_lines, ' ')
    if empty(l:details)
      let l:details = 'Miller exited with status ' . l:exit_code
    endif
    call xlsx_csv#EchoError('Miller failed for ' . a:file . ': ' . l:details)
    return
  endif

  try
    execute 'edit ' . fnameescape(l:output_file)
  catch
    call xlsx_csv#EchoError('Failed to open the file: ' . l:output_file)
  endtry
endfunction
