let s:test_dir = fnamemodify(expand('<sfile>'), ':p:h')

function AssertJsonFilesEqual(actual_file, expected_file) abort
  let l:actual = json_decode(join(readfile(a:actual_file), "\n"))
  let l:expected = json_decode(join(readfile(a:expected_file), "\n"))
  call assert_equal(l:expected, l:actual)
endfunction

function AssertTextFilesEqual(actual_file, expected_file) abort
  call assert_equal(
        \ readfile(a:expected_file),
        \ readfile(a:actual_file))
endfunction

function ReadSelectedColumns(fixture_dir, columns) abort
  let l:file = a:fixture_dir . '/selected-columns.json'
  let l:selected_columns = json_decode(join(readfile(l:file), "\n"))

  call assert_equal(type([]), type(l:selected_columns))
  for l:column in l:selected_columns
    call assert_true(index(a:columns, l:column) >= 0,
          \ 'Unknown selected column: ' . l:column)
  endfor

  return l:selected_columns
endfunction

function ConvertJsonToFormatTest(case_name, format) abort
  let l:fixture_dir = s:test_dir . '/fixtures/copy-as-' . a:format . '/' . a:case_name
  let l:input_lines = readfile(l:fixture_dir . '/input.csv.json')
  let l:expected_file = l:fixture_dir . '/expected.' . a:format

  let l:result = xlsx_csv#ConvertJsonToFormat(l:input_lines, a:format)
  call assert_equal('', l:result.error)
  if empty(l:result.error)
    let l:actual_file = tempname()
    try
      call writefile(l:result.lines, l:actual_file)
      call AssertTextFilesEqual(l:actual_file, l:expected_file)
    finally
      call delete(l:actual_file)
    endtry
  endif
endfunction

function CreateCsvDotJsonFileTest(case_name) abort
  let l:fixture_dir = s:test_dir . '/fixtures/open-as-json/' . a:case_name
  let l:output_file = tempname() . '.json'

  try
    let l:Selector = function('ReadSelectedColumns', [l:fixture_dir])
    let l:error_msg = xlsx_csv#CreateCsvDotJsonFile(
          \ l:fixture_dir . '/input.csv',
          \ l:output_file,
          \ l:Selector)
    call assert_equal('', l:error_msg)
    if empty(l:error_msg)
      call AssertJsonFilesEqual(
            \ l:output_file,
            \ l:fixture_dir . '/expected.json')
    endif
  finally
    call delete(l:output_file)
  endtry
endfunction
