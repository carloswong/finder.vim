let s:finder_buf = 0
let s:last_win_num = -1
let s:finder_job = v:null
let g:finder_last_pattern = ''

let g:finder_window_height = get(g:, 'finder_window_height', 10)
let g:finder_window_ignore_patterns = ['NERD_tree', '__Tagbar__']

" public functions

function! finder#FindFile()
    let remain_pattern = ''
    if s:finder_buf && bufwinnr(s:finder_buf) != -1
        let remain_pattern = g:finder_last_pattern
    endif

    call inputsave()
    let pattern = input('Find: ', remain_pattern)
    call inputrestore()
    
    let g:finder_last_pattern = pattern
    if !len(pattern)
        return
    endif

    let default_command = 'fd  --strip-cwd-prefix -c never -t f {PATTERN}' 
    let g:finder_find_command = get(g:, 'finder_find_command', default_command)
    let command = substitute(g:finder_find_command, '{PATTERN}' , pattern, '')
    let keymap = #{
        \ Enter: 'finder#OpenFile(0)', 
        \ s: 'finder#OpenFile(1)',
        \ v: 'finder#OpenFile(2)'}

    if has('job')
        call finder#ShowFinderWindowAsync('Files', command, function("s:on_files_job_output"), keymap)
    "It seems has bug on neovim to receive job std_output, so async mode is
    "not working yet
    "elseif has('nvim')
    "    call finder#ShowFinderWindowAsync('Files', command, function("s:on_files_job_output_nvim"), keymap)
    else
        let filelist = []
        let output = systemlist(command)
        for fpath in output
            let fname = fnamemodify(fpath, ":t")
            call add(filelist, [fname, fpath])
        endfor

        call finder#ShowFinderWindow('Files', filelist, keymap)
        call s:did_all_matched_result_added()
    endif
endfunction

function! s:on_files_job_output(job, message)
    call s:send_matched_filepath(a:message)
endfunction

function! s:on_files_job_output_nvim(job_id, data, event) 
    let output = a:data[0][:-1]
    if len(output)
        call s:send_matched_filepath(output)
    endif
endfunction

function! finder#PickBuffer()
    let list = []
    let buffers = filter(range(1, bufnr('$')), 's:filter_buffer(v:val)')
    let buffers = sort(buffers,'s:sort_buffer_by_lastused')

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
        call add(list, [fname, filepath]) 
    endfor

    call finder#ShowFinderWindow('Buffers', list, #{
                \ Enter: 'finder#OpenBuffer(0)',
                \ s: 'finder#OpenBuffer(1)',
                \ v: 'finder#OpenBuffer(2)',
                \ x: 'finder#DeleteBuffer()',
                \ })
endfunction

function! finder#OpenBuffer(type)
    call s:open_selected(a:type, 'buffer')
endfunction

function! finder#OpenFile(type)
    call s:open_selected(a:type, 'edit')
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

" call finder#ShowFinderWindow('mode_name', [['title','subtitle']], {'key', 'fuctionname'})
function! finder#ShowFinderWindow(mode, list, keymap)
    call s:show_finder_window(a:mode, a:list, '', a:keymap)
endfunction

function! finder#ShowFinderWindowAsync(mode, command, on_output, keymap)
    call s:show_finder_window(a:mode, a:command, a:on_output, a:keymap)
endfunction

function! finder#HideFinderWindow()
    if s:finder_buf == 0
        return
    endif

    if s:finder_job != v:null 
        if has('job') && job_status(s:finder_job) == 'run'
            call job_stop(s:finder_job)
        elseif has('nvim') 
            call jobstop(s:finder_job)
        endif

        let s:finder_job = v:null
    endif

    execute 'bd' s:finder_buf
    let s:finder_buf = 0
endfunction

" private functions

function! s:show_finder_window(mode, command_or_list, on_output, keymap)
    let g:finder_mode = a:mode
    let need_remap = s:prepare_finder_window()

    if type(a:command_or_list) == type([])
        let list = a:command_or_list
        for line in list
            call finder#AppendMatchedResult(line[0], line[1])
        endfor
    elseif type(a:command_or_list) == type("")
        let command = a:command_or_list
        " async mode
        if has('job')
            if s:finder_job != v:null
                call job_stop(s:finder_job)
            endif
            let s:finder_job = job_start([command], {
                        \"out_cb" : a:on_output,
                        \"exit_cb": function("s:on_finder_job_stop")})
        elseif has('nvim')
            if s:finder_job != v:null
                call jobstop(s:finder_job)
            endif

            let s:finder_job = jobstart(command, {
                        \ "on_stdout": on_stdout,
                        \ "on_exit": function("s:on_finder_job_stop_nvim")})
        endif
    else
        call finder#HideFinderWindow()
        return
    endif

    if need_remap
        for item in items(a:keymap)
            let key = item[0] == 'Enter' ? '<CR>' : item[0]
            execute 'nnoremap <buffer> <silent> ' . key . ' :call ' . item[1] . '<CR>'
        endfor
    endif
    
    call s:did_all_matched_result_added()
endfunction

function! s:open_selected(type, cmd)
    if s:finder_buf == 0
        return
    endif

    let line = getline('.')
    "call finder#HideFinderWindow()

    let win_num = s:select_appreciated_window()
    silent! execute win_num . 'wincmd w'

    if a:type == 1
        split
    elseif a:type == 2
        vsplit
    endif

    let item = s:get_fname_or_bufnr(line)
    execute a:cmd . ' ' . item
endfunction


function! s:swap_to_target_window()
    let win_num = s:select_appreciated_window()
    silent! execute win_num . 'wincmd w'
endfunction

function! s:get_selected_line()
    if s:finder_buf == 0
        return ''
    endif
    let line = getline('.')

    return line
endfunction

function! s:sort_buffer_by_lastused(b1, b2)
    let buf1 = getbufinfo(a:b1)
    let buf2 = getbufinfo(a:b2)
    return buf1[0].lastused > buf2[0].lastused ? -1 : 1
endfunction
 
function! s:is_finder_window(win_num)
    let win_id = win_getid(a:win_num)
    let bufnr = winbufnr(win_id)

    return bufnr == s:finder_buf
endfunction

function! s:is_ignore_window(win_num)
    let bufname = bufname(winbufnr(a:win_num))
    for pattern in g:finder_window_ignore_patterns
        if s:starts_with(bufname, pattern)
            return v:true
        endif 
    endfor

    return v:false
endfunction

" find appreciated window to open file
function! s:select_appreciated_window()
    if !s:is_finder_window(s:last_win_num) && !s:is_ignore_window(s:last_win_num)
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

        if s:is_ignore_window(win_nr)
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
    let s:need_remap = s:finder_buf == 0

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
        
        " keymap
        nnoremap <buffer> <silent> <ESC> :call finder#HideFinderWindow()<CR>
        nnoremap <buffer> <silent> q :call finder#HideFinderWindow()<CR>

        autocmd BufLeave \*Finder\* :call finder#HideFinderWindow()
    endif

    let g:finder_mode_subtitle = g:finder_mode == 'Files' ? ' ' . g:finder_last_pattern : ''
    setlocal statusline=%#Normal#%=[%{g:finder_mode}]%{g:finder_mode_subtitle}\ %l/%L
    return s:need_remap
endfunction

function! s:send_matched_filepath(filepath)
    let fname = fnamemodify(a:filepath, ":t")
    call finder#AppendMatchedResult(fname, a:filepath)
endfunction

function! finder#AppendMatchedResult(fname, filepath)
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

function! s:did_all_matched_result_added()
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


function! s:on_finder_job_stop(job, status)
    call s:did_all_matched_result_added()
endfunction

function! s:on_finder_job_stop_nvim(job_id, _data, event)
    call s:did_all_matched_result_added()
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

function! s:starts_with(string, pattern)
    return a:string[0:len(a:pattern)-1] ==# a:pattern
endfunction
