function s:EchoError(msgText) abort
  echohl ErrorMsg
  echomsg a:msgText
  echohl None
endfunction

function xlsx_csv#OpenJson(file) abort
  if !filereadable(a:file)
    call s:EchoError('Failed to open the file: ' . a:file)
    return
  endif

  try
    execute 'edit ' . fnameescape(a:file)
  catch
    call s:EchoError('Failed to open the file: ' . a:file)
  endtry
endfunction
