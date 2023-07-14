let s:finder_buf = 0
let s:last_win_num = -1
let s:finder_job = v:null
let g:finder_last_pattern = ''

function! s:is_finder_window(win_num)
    let win_id = win_getid(a:win_num)
    let bufnr = winbufnr(win_id)

    return bufnr == s:finder_buf
endfunction

" find appreciated window to open file
function! s:select_appreciated_window()
    if !s:is_finder_window(s:last_win_num)
        return s:last_win_num
    endif

    let result = -1
    let size = winnr('$')
    if size < 2
        return result
    endif

    for win_nr in range(size)
        if s:is_finder_window(win_nr)
            continue
        endif

        let result =  win_nr
        break
    endfor

    if result == -1 || result == 0
        execute 'top split'
        let result = winnr()
    endif

    return result
endfunction

function! finder#OpenFile()
    let line = getline('.')
    let info = split(line)

    call finder#HideResultWindow()

    let win_num = s:select_appreciated_window()
    silent! execute win_num . 'wincmd w'
    execute 'edit ' . info[1]
endfunction

function! finder#HideResultWindow()
    if s:finder_job != v:null && job_status(s:finder_job) == 'run'
        call job_stop(s:finder_job)
        let s:finder_job = v:null
    endif

    execute 'bd' s:finder_buf
    let s:finder_buf = 0
endfunction

function! s:prepare_finder_buffer() 
    let s:last_win_num = winnr()
    if s:finder_buf != 0
        let winnr = bufwinnr(s:finder_buf)
        silent! execute winnr . 'wincmd w'
        call setbufvar(s:finder_buf, '&modifiable', 1)
        silent execute '%delete'
    else
        botright split Finder
        let s:finder_buf = bufnr()

        redraw

        setlocal buftype=nofile
        setlocal bufhidden=hide
        setlocal noswapfile
        setlocal nobuflisted
        setlocal nonu
        setlocal nowrap

        syntax match Comment "\t.*$"

        nnoremap <buffer> <silent> <CR> :call finder#OpenFile()<CR>
        nnoremap <buffer> <silent> q :call finder#HideResultWindow()<CR>
        nnoremap <buffer> <silent> <ESC> :call finder#HideResultWindow()<CR>
    endif

    setlocal statusline=%#Pmenu#\ Search:\ %{g:finder_last_pattern}%=%l/%L
endfunction

function! s:append_matched_result(filepath)
    if empty(a:filepath)
        return
    endif

    if s:finder_buf == 0
        return
    endif

    let fname = fnamemodify(a:filepath, ":t")
    let text = printf(" %-30s\t%s", fname , a:filepath)
    let lines = line('$')
    if getline(1) == ''
        silent! call setbufline(s:finder_buf, 1, text)
    else
        silent! call appendbufline(s:finder_buf, lines, text)
    endif
endfunction

function! s:after_display_result()
    let lines = line('$')
    if lines == 1 && getline(1) == ''
        call setbufline(s:finder_buf, 1, '--Not result found--')
    else
        normal gg
    endif

    call setbufvar(s:finder_buf, '&modifiable', 0)
    silent! execute 'resize' lines > 10 ? 10 : lines
endfunction

function! s:on_finder_job_output(job, message)
    call s:append_matched_result(a:message)
endfunction

function! s:on_finder_job_stop(job, status)
    call s:after_display_result()
endfunction

function! finder#FindFile()
    let remain_pattern = ''
    if s:finder_buf && bufwinnr(s:finder_buf) != -1
        let remain_pattern = g:finder_last_pattern
    endif

    call inputsave()
    let pattern = input('Find> ', remain_pattern)
    call inputrestore()
    
    let g:finder_last_pattern = pattern
    if !len(pattern)
        return
    endif

    let default_command = 'fd  --strip-cwd-prefix -c never -t f {PATTERN}' 
    let g:finder_find_command = get(g:, 'finder_find_command', default_command)
    let command = substitute(g:finder_find_command, '{PATTERN}' , pattern, '')

    call s:prepare_finder_buffer()

    if has('job')
        " async mode
        if s:finder_job != v:null
            call job_stop(s:finder_job)
        endif

        let s:finder_job = job_start(command, {
                    \"out_cb" : function("s:on_finder_job_output"),
                    \"exit_cb": function("s:on_finder_job_stop")})
    else
        " sync mode
        let output = systemlist(command)
        for filepath in output
            call s:append_matched_result(filepath)
        endfor
        call s:after_display_result()
    endif

endfunction