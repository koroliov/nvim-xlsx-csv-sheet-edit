function xlsx_csv#EchoError(msgText) abort
  echohl ErrorMsg
  echomsg '[xlsx-csv-sheet-edit] ' . a:msgText
  echohl None
endfunction

function xlsx_csv#CopyAsFormat(format) abort
  let l:json_lines = []
  for l:line in getline(1, '$')
    call add(l:json_lines, l:line)
  endfor

  let l:format_uc = toupper(a:format)
  let l:input_file = tempname()
  try
    if writefile(l:json_lines, l:input_file) != 0
      let l:msg = 'Failed to prepare the current buffer for ' .
        \ format_uc . ' conversion.'
      call xlsx_csv#EchoError()
      return
    endif

    let l:csv_lines = systemlist([
          \ 'mlr', '--ijson', '--o' . a:format, 'cat', l:input_file])
    if v:shell_error != 0
      call xlsx_csv#EchoError(
            \ 'Miller failed to convert the current buffer to ' . l:format_uc .
            \ ': ' . join(l:csv_lines, ' '))
      return
    endif

    call setreg('+', join(l:csv_lines, "\n"))
    echomsg '[xlsx-csv-sheet-edit] ' . format_uc .
      \ ' copied to the system clipboard.'
  finally
    call delete(l:input_file)
  endtry
endfunction

function s:CompareColumnRanks(left, right) abort
  let l:left_rank = str2nr(a:left[0])
  let l:right_rank = str2nr(a:right[0])
  if l:left_rank != l:right_rank
    return l:left_rank < l:right_rank ? -1 : 1
  endif

  " Keep the input order when two columns have the same rank.
  return a:left[1] - a:right[1]
endfunction

function s:SelectColumns(columns) abort
  " An empty string means that a column is not selected.  Otherwise the
  " value is a string containing only non-negative integer digits.
  let l:order = repeat([''], len(a:columns))
  let l:buffer = nvim_create_buf(v:false, v:true)
  let l:desired_width = 0

  for l:column in a:columns
    let l:desired_width = max([l:desired_width, strdisplaywidth(l:column)])
  endfor
  let l:desired_width = max([l:desired_width,
        \ strdisplaywidth('Select and order columns'),
        \ strdisplaywidth('Up/Down: move  0-9: enter rank  BS: delete  Space/c: clear  Enter: accept  q/Esc: cancel')])

  let l:width = min([max([20, l:desired_width + 14]), &columns - 4])
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
  call nvim_win_set_option(l:window, 'wrap', v:true)
  call nvim_win_set_option(l:window, 'linebreak', v:true)

  let l:namespace = nvim_create_namespace('xlsx_csv_select_mark_columns')
  let l:current = 0
  let l:offset = 0

  while 1
    let l:menu = [
          \ 'Select and order columns',
          \ '']
    for l:index in range(l:offset, min([len(a:columns) - 1, l:offset + l:visible_items - 1]))
      let l:rank = empty(l:order[l:index]) ? ' ' : l:order[l:index]
      let l:prefix = l:index == l:current ? '> ' : '  '
      call add(l:menu, printf('%s[%3s] %2d. %s', l:prefix, l:rank, l:index + 1, a:columns[l:index]))
    endfor
    call extend(l:menu, ['', 'Up/Down: move  0-9: enter rank  BS: delete  Space/c: clear  Enter: accept  q/Esc: cancel'])

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
    elseif l:key =~# '^[0-9]$'
      let l:order[l:current] .= l:key
    elseif l:key ==# "\<BS>" || l:key ==# "\<C-H>"
      if !empty(l:order[l:current])
        let l:order[l:current] = strpart(l:order[l:current], 0, strlen(l:order[l:current]) - 1)
      endif
    elseif l:key ==# ' ' || l:key ==# 'c'
      let l:order[l:current] = ''
    elseif l:key ==# "\<CR>"
      break
    elseif l:key ==# "\<Esc>" || l:key ==# 'q'
      let l:order = []
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

  let l:ranked = []
  for l:index in range(0, len(l:order) - 1)
    if !empty(l:order[l:index])
      call add(l:ranked, [l:order[l:index], l:index])
    endif
  endfor
  call sort(l:ranked, function('s:CompareColumnRanks'))

  let l:result = []
  for l:item in l:ranked
    call add(l:result, a:columns[l:item[1]])
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

function xlsx_csv#ConvertToJson(input_file, output_file) abort
  if !filereadable(a:input_file)
    return 'Failed to open the file: ' . a:input_file
  endif

  let l:error_file = tempname()
  let l:command = 'mlr --icsv --ojson cat ' . shellescape(a:input_file)
        \ . ' > ' . shellescape(a:output_file)
        \ . ' 2> ' . shellescape(l:error_file)

  try
    call system(l:command)
    let l:exit_code = v:shell_error
    let l:error_lines = filereadable(l:error_file)
          \ ? readfile(l:error_file)
          \ : []

    if l:exit_code != 0
      let l:details = join(l:error_lines, ' ')
      if empty(l:details)
        let l:details = 'Miller exited with status ' . l:exit_code
      endif
      return 'Miller failed for ' . a:input_file . ': ' . l:details
    endif

    return ''
  finally
    call delete(l:error_file)
  endtry
endfunction

function s:ScalarText(value) abort
  if type(a:value) == type('')
    return a:value
  endif
  return printf('%s', a:value)
endfunction

function s:EncodeObjects(objects, column_orders) abort
  let l:lines = ['[']

  for l:object_index in range(0, len(a:objects) - 1)
    let l:columns = a:column_orders[l:object_index]
    call add(l:lines, '  {')
    for l:column_index in range(0, len(l:columns) - 1)
      let l:column = l:columns[l:column_index]
      let l:value = has_key(a:objects[l:object_index], l:column)
            \ ? a:objects[l:object_index][l:column]
            \ : ''
      let l:comma = l:column_index == len(l:columns) - 1 ? '' : ','
      call add(l:lines, printf('    %s: %s%s', json_encode(l:column),
            \ json_encode(l:value), l:comma))
    endfor
    let l:object_comma = l:object_index == len(a:objects) - 1 ? '' : ','
    call add(l:lines, '  }' . l:object_comma)
  endfor

  call add(l:lines, ']')
  return l:lines
endfunction

function xlsx_csv#CreateCsvDotJsonFile(input_file, output_file, selector) abort
  let l:error_msg = xlsx_csv#ConvertToJson(a:input_file, a:output_file)
  if !empty(l:error_msg)
    return l:error_msg
  endif

  let l:json_lines = readfile(a:output_file)
  try
    let l:objects = json_decode(join(l:json_lines, "\n"))
  catch
    return 'Failed to parse the JSON file: ' . a:output_file
  endtry

  if type(l:objects) != type([]) || empty(l:objects)
    let l:columns = []
  elseif type(l:objects[0]) != type({})
    return 'Expected JSON objects in the file: ' . a:output_file
  else
    let l:columns = s:GetJsonColumns(l:json_lines, l:objects[0])
  endif

  let l:selected_columns = call(a:selector, [l:columns])
  if type(l:selected_columns) != type([])
    return 'Column selector must return a list of column names.'
  endif

  for l:column in l:selected_columns
    if index(l:columns, l:column) < 0
      return 'Column selector returned an unknown column: ' . l:column
    endif
  endfor

  let l:metadata = {}
  for l:column in l:columns
    let l:first_value = has_key(l:objects[0], l:column)
          \ ? s:ScalarText(l:objects[0][l:column])
          \ : ''
    let l:same_value = v:true

    for l:object in l:objects[1:]
      let l:value = has_key(l:object, l:column)
            \ ? s:ScalarText(l:object[l:column])
            \ : ''
      if l:value !=# l:first_value
        let l:same_value = v:false
        break
      endif
    endfor

    if index(l:selected_columns, l:column) >= 0
      let l:metadata[l:column] = v:false
    elseif l:same_value
      let l:metadata[l:column] = l:first_value
    else
      return 'Column is not selected and contains different values: ' . l:column
    endif
  endfor

  let l:output_objects = [l:metadata]
  let l:column_orders = [l:columns]
  for l:object in l:objects
    let l:selected_object = {}
    for l:column in l:selected_columns
      let l:selected_object[l:column] = has_key(l:object, l:column)
            \ ? l:object[l:column]
            \ : ''
    endfor
    call add(l:output_objects, l:selected_object)
    call add(l:column_orders, l:selected_columns)
  endfor
  let l:json_lines = s:EncodeObjects(l:output_objects, l:column_orders)

  if writefile(l:json_lines, a:output_file) != 0
    return 'Failed to write the JSON file: ' . a:output_file
  endif

  return ''
endfunction

function xlsx_csv#OpenAsJson(file) abort
  let l:output_file = a:file . '.json'
  let l:error_msg = xlsx_csv#CreateCsvDotJsonFile(
        \ a:file,
        \ l:output_file,
        \ function('s:SelectColumns'))
  if !empty(l:error_msg)
    call xlsx_csv#EchoError(l:error_msg)
    return
  endif

  try
    execute 'edit ' . fnameescape(l:output_file)
  catch
    call xlsx_csv#EchoError('Failed to open the file: ' . l:output_file)
  endtry
endfunction
