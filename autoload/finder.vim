let s:find_file_buf = ''
let s:last_pattern = ''

" find appreciated window to open file
function! s:SelectAppreciatedWindow()
    let size = winnr('$')
    let result = 0
    for win_nr in range(size)
        let win_id = win_getid(win_nr)
        let bufnr = winbufnr(win_id)

        if bufnr == s:find_file_buf
            continue
        endif

        let result =  win_nr
        break
    endfor

    if result == 0
        echo "create new window"
        let result = winnr()
    endif

    return result
endfunction

function! s:OpenFile()
    let filepath = getline('.')
    let win_num = s:SelectAppreciatedWindow()
    execute win_num . 'wincmd w'
    execute 'edit ' . filepath

    call s:HideResultWindow()
endfunction

function! s:HideResultWindow()
    execute 'bd ' . s:find_file_buf
    let s:find_file_buf = 0
    silent! execute ':setlocal laststatus=1'
endfunction

function! s:DisplayResult(result)
    if s:find_file_buf
        let bufnr = s:find_file_buf
        execute 'buffer' bufnr
        call setbufvar(bufnr, '&modifiable', 1)
        silent execute '%delete'
    else
        let bufnr = bufadd('#FindFile#')
        let s:find_file_buf = bufnr
        call setbufvar(bufnr, '&buftype', 'nofile')
        execute 'split'
        execute 'buffer' bufnr

        nnoremap <buffer> <silent> <CR> :call s:OpenFile()<CR>
        nnoremap <buffer> <silent> q :call s:HideResultWindow()<CR>
        nnoremap <buffer> <silent> <ESC> :call s:HideResultWindow()<CR>
    endif

    let size = len(a:result)

    if !size
        setlocal nonu
        call setbufline(bufnr, 1, '--Not Result found--')
    else
        setlocal nu
        for i in range(size)
            call setbufline(bufnr, i+1, a:result[i])
        endfor
    endif 

    let lines = line('$')
    silent! execute 'resize' lines > 10 ? 10 : lines
    silent! execute ':setlocal laststatus=0'
    call setbufvar(bufnr, '&modifiable', 0)

endfunction

function! finder#FindFile()
    call inputsave()
    let pattern = input('FindFile> ', s:last_pattern)
    call inputrestore()
    
    let s:last_pattern = pattern
    if !len(pattern)
        return
    endif

    let command = 'fd  --strip-cwd-prefix -c never ' . pattern
    let output = systemlist(command)
    call s:DisplayResult(output)
endfunction
