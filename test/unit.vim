set rtp^=.
let s:test_dir = fnamemodify(expand('<sfile>'), ':p:h')

function! AssertJsonFilesEqual(actual_file, expected_file) abort
  let l:actual = json_decode(join(readfile(a:actual_file), "\n"))
  let l:expected = json_decode(join(readfile(a:expected_file), "\n"))
  call assert_equal(l:expected, l:actual)
endfunction

function! RunConvertToJsonFixture(case_name) abort
  let l:fixture_dir = s:test_dir . '/fixtures/open-as-json/' . a:case_name
  let l:output_file = tempname() . '.json'

  try
    let l:errorMsg = xlsx_csv#ConvertToJson(
          \ l:fixture_dir . '/input.csv',
          \ l:output_file)
    call assert_equal('', l:errorMsg)
    call AssertJsonFilesEqual(
          \ l:output_file,
          \ l:fixture_dir . '/expected.json')
  finally
    call delete(l:output_file)
  endtry
endfunction

" cases
call RunConvertToJsonFixture('case-01')

if !empty(v:errors)
  call writefile(v:errors, '/dev/stderr')
  cquit 1
endif

qa!
