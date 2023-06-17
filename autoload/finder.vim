let s:find_file_buf = 0
let s:last_pattern = ''
let s:last_win_num = -1

function! s:IsFinderWindow(win_num)
    let win_id = win_getid(a:win_num)
    let bufnr = winbufnr(win_id)

    return bufnr == s:find_file_buf
endfunction

" find appreciated window to open file
function! s:SelectAppreciatedWindow()
    if !s:IsFinderWindow(s:last_win_num)
        return s:last_win_num
    endif

    let result = -1
    let size = winnr('$')
    if size < 2
        return result
    endif

    for win_nr in range(size)
        if s:IsFinderWindow(win_nr)
            continue
        endif

        let result =  win_nr
        break
    endfor

    return result
endfunction

function! finder#OpenFile()
    let filepath = getline('.')
    let win_num = s:SelectAppreciatedWindow()

    if win_num == -1
        execute 'top split'
        let win_num = winnr()
    endif

    execute win_num . 'wincmd w'
    execute 'edit ' . filepath

    call finder#HideResultWindow()
endfunction

function! finder#HideResultWindow()
    execute 'bd ' . s:find_file_buf
    let s:find_file_buf = 0
    silent! execute ':setlocal laststatus=1'
endfunction

function! s:DisplayResult(result)
    let s:last_win_num = winnr()
    if s:find_file_buf
        let bufnr = s:find_file_buf
        execute 'buffer' bufnr
        call setbufvar(bufnr, '&modifiable', 1)
        silent execute '%delete'
    else
        let bufnr = bufadd('#FindFile#')
        let s:find_file_buf = bufnr
        call setbufvar(bufnr, '&buftype', 'nofile')
        execute 'bo split'
        execute 'buffer' bufnr

        nnoremap <buffer> <silent> <CR> :call finder#OpenFile()<CR>
        nnoremap <buffer> <silent> q :call finder#HideResultWindow()<CR>
        nnoremap <buffer> <silent> <ESC> :call finder#HideResultWindow()<CR>
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
