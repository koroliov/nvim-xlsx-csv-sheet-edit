function xlsx_csv#EchoError(msgText) abort
  echohl ErrorMsg
  echomsg '[xlsx-csv-sheet-edit] ' . a:msgText
  echohl None
endfunction

function xlsx_csv#CopyAsCsv() abort
  let l:json_lines = []
  for l:line in getline(1, '$')
    if l:line !~# '@@XlsxCsvMark@@'
      call add(l:json_lines, l:line)
    endif
  endfor

  let l:input_file = tempname()
  try
    if writefile(l:json_lines, l:input_file) != 0
      call xlsx_csv#EchoError('Failed to prepare the current buffer for CSV conversion.')
      return
    endif

    let l:csv_lines = systemlist([
          \ 'mlr', '--ijson', '--ocsv', 'cat', l:input_file])
    if v:shell_error != 0
      call xlsx_csv#EchoError(
            \ 'Miller failed to convert the current buffer to CSV: '
            \ . join(l:csv_lines, ' '))
      return
    endif

    call setreg('+', join(l:csv_lines, "\n"))
    echomsg '[xlsx-csv-sheet-edit] CSV copied to the system clipboard.'
  finally
    call delete(l:input_file)
  endtry
endfunction

function s:SelectMarkColumns(columns) abort
  let l:selected = repeat([0], len(a:columns))
  let l:buffer = nvim_create_buf(v:false, v:true)
  let l:desired_width = 0

  for l:column in a:columns
    let l:desired_width = max([l:desired_width, strdisplaywidth(l:column)])
  endfor

  let l:width = min([max([20, l:desired_width + 10]), &columns - 4])
  let l:height = min([len(a:columns) + 3, &lines - 4])
  let l:visible_items = max([1, l:height - 3])
  let l:window = nvim_open_win(l:buffer, v:true, {
        \ 'relative': 'editor',
        \ 'row': max([0, (&lines - l:height) / 2]),
        \ 'col': max([0, (&columns - l:width) / 2]),
        \ 'width': l:width,
        \ 'height': l:height,
        \ 'style': 'minimal',
        \ 'border': 'rounded',
        \ })
  call nvim_buf_set_option(l:buffer, 'buftype', 'nofile')
  call nvim_buf_set_option(l:buffer, 'bufhidden', 'wipe')
  call nvim_win_set_option(l:window, 'wrap', v:false)

  let l:namespace = nvim_create_namespace('xlsx_csv_select_mark_columns')
  let l:current = 0
  let l:offset = 0

  while 1
    let l:menu = [
          \ 'Select columns to mark',
          \ '']
    for l:index in range(l:offset, min([len(a:columns) - 1, l:offset + l:visible_items - 1]))
      let l:mark = l:selected[l:index] ? '*' : ' '
      let l:prefix = l:index == l:current ? '> ' : '  '
      call add(l:menu, printf('%s[%s] %2d. %s', l:prefix, l:mark, l:index + 1, a:columns[l:index]))
    endfor
    call extend(l:menu, ['', 'Up/Down: move  Space: toggle  Enter: accept  q/Esc: cancel'])

    call nvim_buf_set_option(l:buffer, 'modifiable', v:true)
    call nvim_buf_set_lines(l:buffer, 0, -1, v:true, l:menu)
    call nvim_buf_set_option(l:buffer, 'modifiable', v:false)
    call nvim_buf_clear_namespace(l:buffer, l:namespace, 0, -1)
    call nvim_buf_add_highlight(l:buffer, l:namespace, 'CursorLine', 2 + l:current - l:offset, 0, -1)
    redraw

    let l:key = getcharstr()
    if l:key ==# "\<Up>" || l:key ==# 'k'
      let l:current = max([0, l:current - 1])
    elseif l:key ==# "\<Down>" || l:key ==# 'j'
      let l:current = min([len(a:columns) - 1, l:current + 1])
    elseif l:key ==# ' '
      let l:selected[l:current] = !l:selected[l:current]
    elseif l:key ==# "\<CR>"
      break
    elseif l:key ==# "\<Esc>" || l:key ==# 'q'
      let l:selected = []
      break
    endif

    if l:current < l:offset
      let l:offset = l:current
    elseif l:current >= l:offset + l:visible_items
      let l:offset = l:current - l:visible_items + 1
    endif
  endwhile

  call nvim_win_close(l:window, v:true)
  if nvim_buf_is_valid(l:buffer)
    call nvim_buf_delete(l:buffer, {'force': v:true})
  endif

  let l:result = []
  for l:index in range(0, len(a:columns) - 1)
    if l:selected[l:index]
      call add(l:result, l:index)
    endif
  endfor
  return l:result
endfunction

function s:GetJsonColumns(lines, object) abort
  let l:columns = []
  let l:inside_object = 0

  for l:line in a:lines
    if !l:inside_object && l:line =~# '^\s*{\s*$'
      let l:inside_object = 1
      continue
    endif

    if l:inside_object
      let l:column = matchstr(l:line, '^\s*"\zs[^"\\]*\ze"\s*:')
      if !empty(l:column)
        call add(l:columns, l:column)
      endif

      if l:line =~# '^\s*}\s*,\?\s*$'
        break
      endif
    endif
  endfor

  return empty(l:columns) ? keys(a:object) : l:columns
endfunction

function s:AddMarkRows(file, columns, selected_columns) abort
  let l:lines = readfile(a:file)

  try
    let l:objects = json_decode(join(l:lines, "\n"))
  catch
    call xlsx_csv#EchoError('Failed to parse the JSON file: ' . a:file)
    return 0
  endtry

  if type(l:objects) != type([])
    call xlsx_csv#EchoError('Expected a JSON array in the file: ' . a:file)
    return 0
  endif

  if empty(l:objects)
    return 1
  endif

  if type(l:objects[0]) != type({})
    call xlsx_csv#EchoError('Expected JSON objects in the file: ' . a:file)
    return 0
  endif

  let l:output_lines = []
  let l:row_number = 0

  for l:line in l:lines
    call add(l:output_lines, l:line)
    if l:line =~# '^\s*{\s*$'
      if l:row_number >= len(l:objects)
        call xlsx_csv#EchoError('Could not match JSON objects in the file: ' . a:file)
        return 0
      endif

      let l:mark = [l:row_number + 1]
      for l:column_index in a:selected_columns
        call add(l:mark, get(l:objects[l:row_number], a:columns[l:column_index], v:null))
      endfor

      let l:indent = matchstr(l:line, '^\s*') . '  '
      call add(l:output_lines, l:indent . '"@@XlsxCsvMark@@": ' . json_encode(l:mark) . ',')
      let l:row_number += 1
    endif
  endfor

  if l:row_number != len(l:objects)
    call xlsx_csv#EchoError('Could not locate all JSON objects in the file: ' . a:file)
    return 0
  endif

  if writefile(l:output_lines, a:file) != 0
    call xlsx_csv#EchoError('Failed to write the JSON file: ' . a:file)
    return 0
  endif

  return 1
endfunction

function xlsx_csv#OpenAsJson(file) abort
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

  let l:json_lines = readfile(l:output_file)
  try
    let l:objects = json_decode(join(l:json_lines, "\n"))
  catch
    call xlsx_csv#EchoError('Failed to parse the JSON file: ' . l:output_file)
    return
  endtry

  if type(l:objects) != type([]) || empty(l:objects)
    let l:selected_columns = []
  elseif type(l:objects[0]) != type({})
    call xlsx_csv#EchoError('Expected JSON objects in the file: ' . l:output_file)
    return
  else
    let l:columns = s:GetJsonColumns(l:json_lines, l:objects[0])
    let l:selected_columns = s:SelectMarkColumns(l:columns)
  endif

  if !empty(l:selected_columns) && !s:AddMarkRows(l:output_file, l:columns, l:selected_columns)
    return
  endif

  try
    execute 'edit ' . fnameescape(l:output_file)
  catch
    call xlsx_csv#EchoError('Failed to open the file: ' . l:output_file)
  endtry
endfunction
