if exists('g:loaded_finder_vim')
    finish
endif

let g:loaded_finder_vim = 1

command! FindFile call finder#FindFile()
command! PickBuffer call finder#PickBuffer()