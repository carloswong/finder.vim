let s:finder_buf = 0
let s:last_win_num = -1
let s:finder_job = v:null
let g:finder_last_pattern = ''

let g:finder_window_height = get(g:, 'finder_window_height', 10)

" public functions

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

    let g:finder_mode = 'Files'
    call s:prepare_finder_window()

    redraw
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
            call s:send_matched_filepath(filepath)
        endfor
        call s:after_display_result()
    endif

endfunction

function! finder#PickBuffer()
    let g:finder_mode = 'Buffers'
    call s:prepare_finder_window()

    let buffers = filter(range(1, bufnr('$')), 's:filter_buffer(v:val)')
    for buf in buffers
        let filepath = bufname(buf)
        if empty(filepath)
            let fname = '[No Name]' 
        else
            let fname = fnamemodify(filepath, ":t")
        endif

        let modified = getbufvar(buf, '&modified') ? '[+]' : ''
        let fname = fname . modified

        if empty(filepath) || !filereadable(filepath)
            let filepath = 'Buffer#' . buf
        endif
        call s:append_matched_result(fname, filepath)
    endfor
    call s:after_display_result()
endfunction

function! finder#OpenSelected(type)
    if s:finder_buf == 0
        return
    endif

    let line = getline('.')
    "call finder#HideFinderWindow()

    let win_num = s:select_appreciated_window()
    silent! execute win_num . 'wincmd w'

    if a:type == 1
        " vertical split
        vsplit
    elseif a:type == 2
        " horizontal split
        split
    endif

    let item = s:get_fname_or_bufnr(line)
    if g:finder_mode == 'Buffers'
        execute 'buffer ' . item
    else
        execute 'edit ' . item
    endif
endfunction

function! finder#DeleteBuffer()
    " only work for buffer mode
    if g:finder_mode != 'Buffers'
        return
    endif

    let line = getline('.')
    let buf = s:get_fname_or_bufnr(line)
    let bufnr = s:formt_to_buf_nr(buf)

    if winnr('$') == 2
        let finder_window = bufwinnr(s:finder_buf)
        let ret = filter([1,2], 'v:val != ' . finder_window)
        let primary_window = ret[0]
        let primary_buf = winbufnr(win_getid(primary_window))

        if bufnr == primary_buf
            let nextline = getline(line('.')+1)
            if empty(nextline)
                let nextline = getline(line('.')-1)
            endif

            silent! execute primary_window . 'wincmd w'

            if empty(nextline)
                silent! execute 'new'
            else
                let next_buf = s:get_fname_or_bufnr(nextline)
                silent! execute 'buffer' next_buf
            endif

            silent! execute finder_window . 'wincmd w'
        endif
    endif

    try
        execute 'bd' bufnr
    catch
        echo v:exception
        return
    endtry

    if line('$') == 1
        call finder#HideFinderWindow()
    else
        setlocal modifiable
        normal dd
        setlocal nomodifiable
    endif
endfunction

function! finder#HideFinderWindow()
    if s:finder_buf == 0
        return
    endif

    if s:finder_job != v:null && job_status(s:finder_job) == 'run'
        call job_stop(s:finder_job)
        let s:finder_job = v:null
    endif

    execute 'bd' s:finder_buf
    let s:finder_buf = 0
endfunction

" private functions
 
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

function! s:get_fname_or_bufnr(line)
    " parse buffer number from line
    let buf = matchstr(a:line,'Buffer#\zs\d\+')
    if !empty(buf)
        return str2nr(buf)
    endif

    let items = split(a:line)
    return items[1]

endfunction


function! s:prepare_finder_window() 
    let s:last_win_num = winnr()
    if s:finder_buf != 0
        let winnr = bufwinnr(s:finder_buf)
        silent! execute winnr . 'wincmd w'

        setlocal modifiable
        silent execute '%delete'
        silent execute 'resize 1'
    else
        silent botright 1 split *Finder*
        let s:finder_buf = bufnr()

        redraw

        setlocal buftype=nofile
        setlocal bufhidden=hide
        setlocal noswapfile
        setlocal nobuflisted
        setlocal nonu
        setlocal nowrap

        syntax match Comment "\t.*$"

        nnoremap <buffer> <silent> <CR> :call finder#OpenSelected(0)<CR>
        nnoremap <buffer> <silent> v :call finder#OpenSelected(1)<CR>
        nnoremap <buffer> <silent> s :call finder#OpenSelected(2)<CR>
        nnoremap <buffer> <silent> <ESC> :call finder#HideFinderWindow()<CR>
        nnoremap <buffer> <silent> q :call finder#HideFinderWindow()<CR>
        nnoremap <buffer> <silent> x :call finder#DeleteBuffer()<CR>

        autocmd BufLeave \*Finder\* :call finder#HideFinderWindow()
    endif

    let g:finder_mode_subtitle = g:finder_mode == 'Files' ? ' ' . g:finder_last_pattern : ''
    setlocal statusline=%#Normal#%=[%{g:finder_mode}]%{g:finder_mode_subtitle}\ %l/%L
endfunction

function! s:send_matched_filepath(filepath)
    let fname = fnamemodify(a:filepath, ":t")
    call s:append_matched_result(fname, a:filepath)
endfunction

function! s:append_matched_result(fname, filepath)
    if s:finder_buf == 0
        return
    endif

    if empty(a:filepath)
        return
    endif

    let text = printf(" %-30s\t%s", a:fname, a:filepath)
    let lines = line('$')
    if getline(1) == ''
        silent! call setbufline(s:finder_buf, 1, text)
    else
        silent! call appendbufline(s:finder_buf, lines, text)
        if lines < g:finder_window_height
            execute 'resize +1'
        endif
    endif
endfunction

function! s:after_display_result()
    if s:finder_buf == 0
        return
    endif

    let lines = line('$')
    if lines == 1 && getline(1) == ''
        call setbufline(s:finder_buf, 1, '--Not result found--')
    else
        normal gg
    endif

    setlocal nomodifiable
endfunction

function! s:on_finder_job_output(job, message)
    call s:send_matched_filepath(a:message)
endfunction

function! s:on_finder_job_stop(job, status)
    call s:after_display_result()
endfunction

function! s:filter_buffer(b)
    if getbufvar(a:b, "&buflisted") == 0
        return 0
    endif 

    let type = getbufvar(a:b, "&buftype")
    if  type == 'quickfix' || type == 'terminal'
        return 0
    endif

    return 1
endfunction


function! s:formt_to_buf_nr(buf)
    if type(0) == type(a:buf)
        return a:buf
    else
        return bufnr(a:buf)
    endif
endfunction
