" Author: diegoholiveira <https://github.com/diegoholiveira>, haginaga <https://github.com/haginaga>
" Description: static analyzer for PHP

" Define the minimum severity
let g:ale_php_phan_minimum_severity = get(g:, 'ale_php_phan_minimum_severity', 0)

let g:ale_php_phan_executable = get(g:, 'ale_php_phan_executable', 'phan')
let g:ale_php_phan_use_client = get(g:, 'ale_php_phan_use_client', 0)

function! ale_linters#php#phan#GetExecutable(buffer) abort
    let l:executable = ale#Var(a:buffer, 'php_phan_executable')

    if ale#Var(a:buffer, 'php_phan_use_client') == 1 && l:executable is# 'phan'
        let l:executable = 'phan_client'
    endif

    return l:executable
endfunction

function! ale_linters#php#phan#GetCommand(buffer) abort
    if ale#Var(a:buffer, 'php_phan_use_client') == 1
        let l:args = '-l '
        \   . ' %s'
    else
        let l:args = ''
        \   . '--no-progress-bar '
        \   . '--output-mode=json '
        \   . '-y ' . ale#Var(a:buffer, 'php_phan_minimum_severity') . ' '
        \   . '%s'
    endif

    let l:executable = ale_linters#php#phan#GetExecutable(a:buffer)

    return ale#Escape(l:executable) . ' ' . l:args
endfunction

function! ale_linters#php#phan#Handle(buffer, lines) abort
    if ale#Var(a:buffer, 'php_phan_use_client') == 1
        return ale_linters#php#phan#HandleText(a:buffer, a:lines)
    else
        return ale_linters#php#phan#HandleJSON(a:buffer, a:lines)
    endif
endfunction

function! ale_linters#php#phan#HandleText(buffer, lines) abort
    " Matches against lines like the following:
    if ale#Var(a:buffer, 'php_phan_use_client') == 1
        " Phan error: ERRORTYPE: message in /path/to/some-filename.php on line nnn
        let l:pattern = '^Phan error: \(\w\+\): \(.\+\) in \(.\+\) on line \(\d\+\)$'
    else
        " /path/to/some-filename.php:18 ERRORTYPE message
        let l:pattern = '^\(.*\):\(\d\+\)\s\(\w\+\)\s\(.\+\)$'
    endif

    let l:output = []

    for l:match in ale#util#GetMatches(a:lines, l:pattern)
        if ale#Var(a:buffer, 'php_phan_use_client') == 1
            let l:dict = {
            \   'lnum': l:match[4] + 0,
            \   'text': l:match[2],
            \   'filename': l:match[3],
            \   'type': 'W',
            \}
        else
            let l:dict = {
            \   'lnum': l:match[2] + 0,
            \   'text': l:match[4],
            \   'type': 'W',
            \   'filename': l:match[1],
            \}
        endif

        call add(l:output, l:dict)
    endfor

    return l:output
endfunction

function! ale_linters#php#phan#HandleJSON(buffer, lines) abort
    return s:parseJSON(a:buffer, a:lines)
endfunction

function! s:parseJSON(buffer, lines) abort
    let l:errors = []

    for l:line in a:lines
        try
            let l:errors = extend(l:errors, json_decode(l:line))
        catch
        endtry
    endfor

    if empty(l:errors)
        return []
    endif

    let l:output = []

    for l:error in l:errors
        let l:obj = ({
        \   'type': 'W',
        \})

        if has_key(l:error, 'description')
            let l:description = get(l:error, 'description', '')
            " IssueCategory IssueType Message goes like this.
            let l:matches = matchlist(l:description, '\(\w\+\) \(\w\+\) \(.*\)')
            if empty(l:matches)
                let l:obj.text = l:description
            else
                let l:obj.text = l:matches[3]
            endif

            if has_key(l:error, 'suggestion')
                let l:obj.text = l:obj.text . ' (' . get(l:error, 'suggestion', '') . ')'
            endif
        endif

        if get(l:error, 'severity', 5) == 0
            let l:obj.type = 'I'
        elseif get(l:error, 'severity', 5) > 5
            let l:obj.type = 'E'
        endif

        if has_key(l:error, 'location')
            let l:location = get(l:error, 'location')

            if has_key(l:location, 'lines')
                let l:lines = get(l:location, 'lines')
                let l:obj.lnum = get(l:lines, 'begin', 0)
                let l:obj.end_lnum = get(l:lines, 'end', 0)
            endif

            if has_key(l:location, 'path')
                let l:obj.filename = get(l:location, 'path', '')
            endif
        endif

        call add(l:output, l:obj)
    endfor

    return l:output
endfunction

call ale#linter#Define('php', {
\   'name': 'phan',
\   'executable': function('ale_linters#php#phan#GetExecutable'),
\   'command': function('ale_linters#php#phan#GetCommand'),
\   'callback': 'ale_linters#php#phan#Handle',
\})
