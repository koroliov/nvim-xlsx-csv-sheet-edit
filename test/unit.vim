set rtp^=.

"call assert_equal(5, xlsx_csv#Foo())

if !empty(v:errors)
  call writefile(v:errors, '/dev/stderr')
  cquit 1
endif

qa!
