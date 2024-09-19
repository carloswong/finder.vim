if exists('g:loaded_finder_vim')
    finish
endif

let g:loaded_finder_vim = 1

" When arg passed, it will be used as ROOT for looking up files under the
" ROOT, otherwise the CWD will be used as ROOT
command! -nargs=? FindFile call finder#FindFile(<f-args>)
command! PickBuffer call finder#PickBuffer()
