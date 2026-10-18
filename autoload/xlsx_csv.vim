function xlsx_csv#EchoError(msgText) abort
  echohl ErrorMsg
  echomsg '[xlsx-csv-sheet-edit] ' . a:msgText
  echohl None
endfunction

function xlsx_csv#CopyAsFormat(format) abort
  let l:result = xlsx_csv#ConvertJsonToFormat(
        \ getline(1, '$'), a:format)
  if !empty(l:result.error)
    call xlsx_csv#EchoError(l:result.error)
    return
  endif

  call setreg('+', join(l:result.lines, "\n"))
  echomsg '[xlsx-csv-sheet-edit] ' . toupper(a:format) .
        \ ' copied to the system clipboard.'
endfunction

function xlsx_csv#ConvertJsonToFormat(json_lines, format) abort
  if a:format !~# '^\%(csv\|tsv\)$'
    return {'error': 'Unsupported output format: ' . a:format, 'lines': []}
  endif

  let l:parsed = s:ParseJsonArray(a:json_lines)
  if !empty(l:parsed.error)
    return {'error': l:parsed.error, 'lines': []}
  endif
  let l:objects = l:parsed.objects

  let l:columns = s:GetJsonColumns(a:json_lines, l:objects[0])
  if empty(l:columns)
    let l:columns = keys(l:objects[0])
  endif

  let l:empty_marker = '__xlsx_csv_empty_' .
        \ substitute(tempname(), '[^A-Za-z0-9]', '_', 'g') . '__'
  let l:normalized = s:NormalizeJsonObjects(
        \ l:objects, l:columns, l:empty_marker)
  if !empty(l:normalized.error)
    return {'error': l:normalized.error, 'lines': []}
  endif

  return s:RunMiller(l:normalized.objects, l:columns, l:empty_marker,
        \ a:format)
endfunction

function xlsx_csv#CreateCsvDotJsonFile(input_file, output_file, selector) abort
  let l:error_msg = xlsx_csv#ConvertToJson(a:input_file, a:output_file)
  if !empty(l:error_msg)
    return l:error_msg
  endif

  let l:parsed = s:ReadJsonObjects(a:output_file)
  if !empty(l:parsed.error)
    return l:parsed.error
  endif

  let l:selected = s:SelectJsonColumns(
        \ l:parsed.objects, l:parsed.columns, a:selector)
  if !empty(l:selected.error)
    return l:selected.error
  endif

  let l:metadata = s:BuildMetadata(
        \ l:parsed.objects, l:parsed.columns, l:selected.columns)
  if !empty(l:metadata.error)
    return l:metadata.error
  endif

  let l:output = s:BuildSelectedObjects(
        \ l:parsed.objects, l:parsed.columns, l:selected.columns,
        \ l:metadata.object)
  let l:json_lines = s:EncodeObjects(l:output.objects, l:output.column_orders)

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

"local functions
function s:ReadJsonObjects(file) abort
  let l:json_lines = readfile(a:file)
  try
    let l:objects = json_decode(join(l:json_lines, "\n"))
  catch
    return {'error': 'Failed to parse the JSON file: ' . a:file}
  endtry

  if type(l:objects) != type([]) || empty(l:objects)
    return {'error': '', 'objects': l:objects, 'columns': []}
  endif
  if type(l:objects[0]) != type({})
    return {'error': 'Expected JSON objects in the file: ' . a:file}
  endif

  return {'error': '', 'objects': l:objects,
        \ 'columns': s:GetJsonColumns(l:json_lines, l:objects[0])}
endfunction

function s:SelectJsonColumns(objects, columns, selector) abort
  let l:defaults = {}
  if !empty(a:objects)
    for l:index in range(0, len(a:columns) - 1)
      if s:NeedsColumnSelection(a:objects, a:columns[l:index])
        " Use the human-facing column number as the initial rank.
        let l:defaults[a:columns[l:index]] = string(l:index + 1)
      endif
    endfor
  endif

  " Keep the selector API unchanged while passing defaults to the built-in
  " selector through script-local context.
  let s:select_column_defaults = l:defaults
  try
    let l:selected_columns = call(a:selector, [a:columns])
  finally
    unlet! s:select_column_defaults
  endtry

  if type(l:selected_columns) != type([])
    return {'error': 'Column selector must return a list of column names.'}
  endif

  for l:column in l:selected_columns
    if index(a:columns, l:column) < 0
      return {'error': 'Column selector returned an unknown column: ' . l:column}
    endif
  endfor

  return {'error': '', 'columns': l:selected_columns}
endfunction

function s:BuildMetadata(objects, columns, selected_columns) abort
  let l:metadata = {}
  for l:column in a:columns
    let l:first_value = has_key(a:objects[0], l:column)
          \ ? s:ScalarText(a:objects[0][l:column])
          \ : ''
    let l:same_value = v:true

    for l:object in a:objects[1:]
      let l:value = has_key(l:object, l:column)
            \ ? s:ScalarText(l:object[l:column])
            \ : ''
      if l:value !=# l:first_value
        let l:same_value = v:false
        break
      endif
    endfor

    if index(a:selected_columns, l:column) >= 0
      let l:metadata[l:column] = v:false
    elseif l:same_value
      let l:metadata[l:column] = l:first_value
    else
      return {'error': 'Column is not selected and contains different values: '
            \ . l:column}
    endif
  endfor

  return {'error': '', 'object': l:metadata}
endfunction

function s:BuildSelectedObjects(objects, columns, selected_columns, metadata) abort
  let l:output_objects = [a:metadata]
  let l:column_orders = [a:columns]
  for l:object in a:objects
    let l:selected_object = {}
    for l:column in a:selected_columns
      let l:selected_object[l:column] = has_key(l:object, l:column)
            \ ? l:object[l:column]
            \ : ''
    endfor
    call add(l:output_objects, l:selected_object)
    call add(l:column_orders, a:selected_columns)
  endfor

  return {'objects': l:output_objects, 'column_orders': l:column_orders}
endfunction

function s:ParseJsonArray(lines) abort
  try
    let l:objects = json_decode(join(a:lines, "\n"))
  catch
    return {'error': 'Failed to parse JSON input.', 'objects': []}
  endtry

  if type(l:objects) != type([]) || empty(l:objects)
    return {'error': 'Expected a non-empty JSON array.', 'objects': []}
  endif
  if type(l:objects[0]) != type({})
    return {'error': 'Expected the first JSON array entry to be an object.',
          \ 'objects': []}
  endif
  return {'error': '', 'objects': l:objects}
endfunction

function s:NormalizeJsonObjects(objects, columns, empty_marker) abort
  let l:normalized = []
  for l:object_index in range(1, len(a:objects) - 1)
    let l:object = a:objects[l:object_index]
    if type(l:object) != type({})
      return {'error': printf('JSON entry %d is not an object.',
            \ l:object_index), 'objects': []}
    endif

    for l:field in keys(l:object)
      if index(a:columns, l:field) < 0
        return {'error': printf(
              \ 'JSON entry %d contains an unknown field: %s',
              \ l:object_index, l:field), 'objects': []}
      endif
    endfor

    let l:normalized_object = {}
    for l:column in a:columns
      let l:normalized_object[l:column] = has_key(l:object, l:column)
            \ ? l:object[l:column]
            \ : a:objects[0][l:column] is# v:false
            \   ? ''
            \   : a:objects[0][l:column]
      if type(l:normalized_object[l:column]) == type('')
            \ && empty(l:normalized_object[l:column])
        let l:normalized_object[l:column] = a:empty_marker
      endif
    endfor
    call add(l:normalized, l:normalized_object)
  endfor
  return {'error': '', 'objects': l:normalized}
endfunction

function s:RunMiller(objects, columns, empty_marker, format) abort
  let l:json_lines = s:EncodeObjects(
        \ a:objects, repeat([a:columns], len(a:objects)))
  let l:input_file = tempname()
  try
    if writefile(l:json_lines, l:input_file) != 0
      return {'error': 'Failed to prepare JSON for conversion.', 'lines': []}
    endif

    let l:format_lines = systemlist([
          \ 'mlr', '--ijson', '--o' . a:format, 'cat', l:input_file])
    if v:shell_error != 0
      return {'error': 'Miller failed to convert JSON to ' . toupper(a:format)
            \ . ': ' . join(l:format_lines, ' '), 'lines': []}
    endif

    return {'error': '', 'lines': s:RemoveEmptyMarkers(
          \ l:format_lines, a:empty_marker)}
  finally
    call delete(l:input_file)
  endtry
endfunction

function s:RemoveEmptyMarkers(lines, marker) abort
  let l:result = copy(a:lines)
  for l:index in range(0, len(l:result) - 1)
    let l:result[l:index] = substitute(l:result[l:index], a:marker, '', 'g')
  endfor
  return l:result
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
  let l:state = {'order': s:InitialColumnOrder(a:columns),
        \ 'current': 0, 'offset': 0}
  let l:buffer = nvim_create_buf(v:false, v:true)
  let l:dimensions = s:ColumnSelectorDimensions(a:columns)
  let l:window = s:OpenColumnSelectorWindow(l:buffer, l:dimensions)
  let l:namespace = nvim_create_namespace('xlsx_csv_select_mark_columns')

  while 1
    call s:RenderColumnSelector(l:buffer, l:namespace, a:columns,
          \ l:state, l:dimensions.visible_items)

    let l:key = getcharstr()
    if !s:HandleColumnSelectorKey(l:key, l:state, len(a:columns),
          \ l:dimensions.visible_items)
      break
    endif
  endwhile

  call nvim_win_close(l:window, v:true)
  if nvim_buf_is_valid(l:buffer)
    call nvim_buf_delete(l:buffer, {'force': v:true})
  endif

  let l:ranked = []
  for l:index in range(0, len(l:state.order) - 1)
    if !empty(l:state.order[l:index])
      call add(l:ranked, [l:state.order[l:index], l:index])
    endif
  endfor
  call sort(l:ranked, function('s:CompareColumnRanks'))

  let l:result = []
  for l:item in l:ranked
    call add(l:result, a:columns[l:item[1]])
  endfor
  return l:result
endfunction

function s:InitialColumnOrder(columns) abort
  " An empty string means that a column is not selected.  Otherwise the
  " value is a string containing only non-negative integer digits.
  let l:order = repeat([''], len(a:columns))
  for l:index in range(0, len(a:columns) - 1)
    let l:column = a:columns[l:index]
    if has_key(s:, 'select_column_defaults')
          \ && has_key(s:select_column_defaults, l:column)
      let l:order[l:index] = s:select_column_defaults[l:column]
    endif
  endfor
  return l:order
endfunction

function s:ColumnSelectorDimensions(columns) abort
  let l:desired_width = 0
  for l:column in a:columns
    let l:desired_width = max([l:desired_width, strdisplaywidth(l:column)])
  endfor
  let l:desired_width = max([l:desired_width,
        \ strdisplaywidth('Select and order columns'),
        \ strdisplaywidth('Up/Down: move  0-9: enter rank  BS: delete  Space/c: clear  Enter: accept  q/Esc: cancel')])

  let l:height = min([len(a:columns) + 3, &lines - 4])
  return {'width': min([max([20, l:desired_width + 14]), &columns - 4]),
        \ 'height': l:height, 'visible_items': max([1, l:height - 3])}
endfunction

function s:OpenColumnSelectorWindow(buffer, dimensions) abort
  let l:window = nvim_open_win(a:buffer, v:true, {
        \ 'relative': 'editor',
        \ 'row': max([0, (&lines - a:dimensions.height) / 2]),
        \ 'col': max([0, (&columns - a:dimensions.width) / 2]),
        \ 'width': a:dimensions.width,
        \ 'height': a:dimensions.height,
        \ 'style': 'minimal',
        \ 'border': 'rounded',
        \ })
  call nvim_buf_set_option(a:buffer, 'buftype', 'nofile')
  call nvim_buf_set_option(a:buffer, 'bufhidden', 'wipe')
  call nvim_win_set_option(l:window, 'wrap', v:true)
  call nvim_win_set_option(l:window, 'linebreak', v:true)
  return l:window
endfunction

function s:RenderColumnSelector(buffer, namespace, columns, state, visible_items) abort
  let l:menu = ['Select and order columns', '']
  for l:index in range(a:state.offset,
        \ min([len(a:columns) - 1, a:state.offset + a:visible_items - 1]))
    let l:rank = empty(a:state.order[l:index]) ? ' ' : a:state.order[l:index]
    let l:prefix = l:index == a:state.current ? '> ' : '  '
    call add(l:menu, printf('%s[%3s] %2d. %s', l:prefix, l:rank,
          \ l:index + 1, a:columns[l:index]))
  endfor
  call extend(l:menu, ['',
        \ 'Up/Down: move  0-9: enter rank  BS: delete  Space/c: clear  Enter: accept  q/Esc: cancel'])

  call nvim_buf_set_option(a:buffer, 'modifiable', v:true)
  call nvim_buf_set_lines(a:buffer, 0, -1, v:true, l:menu)
  call nvim_buf_set_option(a:buffer, 'modifiable', v:false)
  call nvim_buf_clear_namespace(a:buffer, a:namespace, 0, -1)
  call nvim_buf_add_highlight(a:buffer, a:namespace, 'CursorLine',
        \ 2 + a:state.current - a:state.offset, 0, -1)
  redraw
endfunction

function s:HandleColumnSelectorKey(key, state, column_count, visible_items) abort
  if a:key ==# "\<Up>" || a:key ==# 'k'
    let a:state.current = max([0, a:state.current - 1])
  elseif a:key ==# "\<Down>" || a:key ==# 'j'
    let a:state.current = min([a:column_count - 1, a:state.current + 1])
  elseif a:key =~# '^[0-9]$'
    let a:state.order[a:state.current] .= a:key
  elseif a:key ==# "\<BS>" || a:key ==# "\<C-H>"
    if !empty(a:state.order[a:state.current])
      let a:state.order[a:state.current] = strpart(
            \ a:state.order[a:state.current], 0,
            \ strlen(a:state.order[a:state.current]) - 1)
    endif
  elseif a:key ==# ' ' || a:key ==# 'c'
    let a:state.order[a:state.current] = ''
  elseif a:key ==# "\<CR>"
    return v:false
  elseif a:key ==# "\<Esc>" || a:key ==# 'q'
    let a:state.order = []
    return v:false
  endif

  if a:state.current < a:state.offset
    let a:state.offset = a:state.current
  elseif a:state.current >= a:state.offset + a:visible_items
    let a:state.offset = a:state.current - a:visible_items + 1
  endif
  return v:true
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

function s:ScalarText(value) abort
  if type(a:value) == type('')
    return a:value
  endif
  return printf('%s', a:value)
endfunction

function s:NeedsColumnSelection(objects, column) abort
  let l:first_value = has_key(a:objects[0], a:column)
        \ ? s:ScalarText(a:objects[0][a:column])
        \ : ''
  let l:has_non_empty_value = !empty(l:first_value)

  for l:object in a:objects[1:]
    let l:value = has_key(l:object, a:column)
          \ ? s:ScalarText(l:object[a:column])
          \ : ''
    let l:has_non_empty_value = l:has_non_empty_value || !empty(l:value)
    if l:value !=# l:first_value && l:has_non_empty_value
      return v:true
    endif
  endfor

  return v:false
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
