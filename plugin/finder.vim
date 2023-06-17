if exists('loaded_findfile')
    finish
endif

let loaded_findfile = 1

command! FindFile call finder#FindFile()