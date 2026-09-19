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

  try
    execute 'edit ' . fnameescape(a:file)
  catch
    call xlsx_csv#EchoError('Failed to open the file: ' . a:file)
  endtry
endfunction
