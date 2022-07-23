                                  " dogslow "
" When non-zero, the formatter redraws and pauses for this amount of 
" milliseconds after each insert. Helpful for debugging or demoing. Default 0.

                                  " dogops "
" Add or override operators. This is put on top of the default operators and 
" follows the same format. Default {}.

                                  " doglong "
" The maximum length that a section can be in-line for operators with the 'L' 
" flag. Leading and trailing white-space is ignored in the length calculation, 
" and the section length must be greater than doglong to invoke separation. A 
" value of '0' would allow blank sections to accumulate on a line, and a value 
" of '-1' would allow nothing to accumulate, exactly like if the operator had 
" the 'l' flag instead of the 'L' flag. Default 20.


" flags:
"   b - break before this operator
"   a - break after this operator (always on for groups)
"   B - break before the ending operator
"   l - break at the last occurrence before textwidth
"   L - put long sections defined by doglong on a separate line (implies l). 
"       Only available for non-groups.
let s:dflags = 'aBLl'
let s:dops = {
            \ '\[':                                                 { 'z': 20, 'end':   '\]' },
            \ '\.':                                                 { 'z': 19, 'flags': 'bL' },
            \ '(':                                                  { 'z': 18, 'end':   ')'  },
            \ '{':                                                  { 'z': 17, 'end':   '}', 'flags': 'b'..s:dflags },
            \ '\*\*':                                               { 'z': 13  },
            \ '*\|\/\|%':                                           { 'z': 12  },
            \ '+\|-':                                               { 'z': 11  },
            \ '<<\|>>\|>>>':                                        { 'z': 10  },
            \ '<=\?\|>=\?':                                         { 'z': 9   },
            \ '[!=]==\?':                                           { 'z': 8   },
            \ '&':                                                  { 'z': 7   },
            \ '\^':                                                 { 'z': 6   },
            \ '|':                                                  { 'z': 5   },
            \ '&&':                                                 { 'z': 4   },
            \ '||\|??':                                             { 'z': 3   },
            \ '\%([-+*/%&^|]\|\*\*\|<<\|>>>\?\|&&\|||\|??\)\?=>\?': { 'z': 2   },
            \ ',':                                                  { 'z': 1   }
        \ }

" script vars that are generated
let s:ops = {}
let s:opkeys = []
let s:groups = []
let s:slow = 0
let s:long = 20

let s:skip_expr = 's:InStringlike() || s:InGroup()'
" returns 1 if position line, col is in a string-like (string or comment)
function s:InStringlike()
    return synID(line('.'),col('.'),0)->synIDattr("name") =~? 'string\|comment'
endfunction
" returns 1 if the cursor is in a group that starts on the current line
" preconditions: script vars are generated
function s:InGroup()
    let [l:l, l:c] = [line('.'), col('.')]
    for l:g in s:groups
        " if on the group opener, don't include the group opener in the search 
        " - avoid false positive where it thinks a group is inside itself
        let l:f = (getline(l:l)[l:c-1:] =~# '^\%('..s:ops[l:g]['end']..'\)')
                    \ ? 'c' : ''
        if searchpair(
                    \ l:g, '', s:ops[l:g]['end'],
                    \ 'nbz'..l:f, "s:InStringlike()", l:l)
            return 1
        endif
    endfor
endfunction

function s:OpIsGroup(op)
    return a:op->has_key('end')
endfunction
function s:OpKeyIsGroup(opkey)
    return s:OpIsGroup(s:ops[a:opkey])
endfunction
" cleans up flags, adding implicit or required flags
function s:CleanFlags(op)
    let l:fl = a:op->has_key('flags') ? a:op['flags'] : s:dflags
    " remove L flag for groups
    if l:fl =~# 'L' && s:OpIsGroup(a:op)
        let l:fl = substitute(l:fl, '\CL', '', '')
    endif
    " force 'l' flag when the 'L' flag is present
    if l:fl =~# 'L' && l:fl !~# 'l'
        let l:fl ..= 'l'
    endif
    " force 'a' flag for groups
    if l:fl !~# 'a' && s:OpIsGroup(a:op)
        let l:fl ..= 'a'
    endif
    let a:op['flags'] = l:fl
endfunction

" Returns 1 if the operator has the flag. If end is nonzero, the ending flags 
" are considered instead. In reality, this just makes it convert the flag 
" argument to upper case before checking comparison. When end = 0, the flag 
" argument is not touched.
" preconditions: script vars are generated
function s:GetFlag(oper, flag, end = 0)
    return s:ops[a:oper]['flags'] =~# (a:end ? toupper(a:flag) : a:flag)
endfunction

" finds pattern on the line
function s:FindOnLine(pat, flags = '')
    return search(a:pat, a:flags, line('.'), 0, s:skip_expr)
endfunction
" finds pair on the line using searchpair
function s:FindPairOnLine(group, flags = '')
    return searchpair(
                \ a:group, '', s:ops[a:group]['end'],
                \ a:flags, s:skip_expr, line('.'))
endfunction
" return byte column at the end of the first match of {pat} on the cursor line 
" (-1 if not found):
"   when pat =      'the'
"   return that column ^
function s:MatchEnd(pat)
    return getline('.')->matchstrpos(a:pat, col('.') - 1)[2]
endfunction
" returns true if the match is either preceded or followed by only spaces.
" preconditions: cursor is on the start of the match if before is 1
function s:MatchIsSpaced(pat, before)
    return a:before && (col('.') <= 1 || getline('.')[:col('.')-2] =~# '^\s*$')
                \ || !a:before && getline('.')[s:MatchEnd(a:pat):] =~# '^\s*$'
endfunction

function s:ByteToVirtCol(col)
    return getline('.')[: a:col-1]->strdisplaywidth()
endfunction

" Finds operator if unexpanded on the line. Returns 0 if not found
function s:FindOper(oper, flags = '')
    " match has to not be followed by only white-space
    if s:GetFlag(a:oper, 'a') && (s:FindOnLine(a:oper, a:flags) &&
                \ !s:MatchIsSpaced(a:oper, 0) || a:flags =~# 'b' &&
                \ s:FindOnLine(a:oper, a:flags))
        return 1
    endif
    if s:GetFlag(a:oper, 'b')
        " match has to not be prepended by only white-space. if it was, there 
        " must be another match after it
        let l:noc = substitute(a:flags, 'c', '', '')
        if s:FindOnLine(a:oper, a:flags) && !s:MatchIsSpaced(a:oper, 1) ||
                    \ a:flags !~# 'b' && s:FindOnLine(a:oper, l:noc)
            return 1
        endif
    endif
    " found no match
    return 0
endfunction

" insert a line break with optional mode instead of insert
function s:InsertBreak(mode = 'i')
    exe "norm! "..a:mode.."\<CR>"
    if s:slow
        redraw
        exe 'sleep '..s:slow..'m'
    endif
endfunction

function s:GetSectLength(startcol, endcol)
    return getline('.')[a:startcol-1 : a:endcol-1]->trim()->strdisplaywidth()
endfunction
function s:SectNeedsSplit(startcol, endcol)
    return s:GetSectLength(a:startcol, a:endcol) > s:long ||
                \ s:ByteToVirtCol(a:endcol) > &textwidth
endfunction

" Return byte column where the break for the operator would be inserted and a 
" value that says whether it could have more to insert (1) or not (0) for the 
" current match: [col, more]. The more parameter should be the same as what was 
" returned on the last one. If it is 0, s:BreakCol will try to find the next 
" match instead of operating on the match under the cursor.
function s:BreakCol(oper, end = 0, more = 0)
    let l:realpat = a:end ? s:ops[a:oper]['end'] : a:oper
    if !a:more
        " find next match
        " operator wants last occurrence
        if s:GetFlag(a:oper, 'l') && !a:end
            " operator wants to break on long sections
            if s:GetFlag(a:oper, 'L')
                " try to find one that needs its own line first
                let l:last = col('.')
                let l:last_end = col('.')
                let l:iter_count = 0
                let l:found = 0
                while s:FindOper(a:oper)
                    if s:SectNeedsSplit(l:last_end + 1, col('.') - 1)
                        " this section needs to be on its own line
                        " go to the last match if this section isn't the first 
                        " of the line
                        if l:iter_count | call cursor(0, l:last) | endif
                        let l:found = 1
                        break
                    endif
                    let l:last = col('.')
                    let l:last_end = s:MatchEnd(a:oper)
                    let l:iter_count += 1
                endwhile
                " nothing found if no section was long enough or went past 
                " textwidth, and the remaining section doesn't need to be 
                " split, or there is no matching operator on the line, even 
                " starting from the cursor.
                if !l:found && !(l:iter_count && 
                            \ s:SectNeedsSplit(l:last_end+1, col('$')-1))
                    return [-1, 0]
                endif
            else
                " line too short for it to make sense
                if virtcol('$')-1 <= &textwidth
                    return [-1, 0]
                endif
                " search backwards from textwidth
                " TODO: do i need to account for 'a' and 'b' operator flags?
                call cursor(0, &textwidth + 1)
                if !s:FindOper(a:oper, 'b')
                    " backward didn't work; try searching forward instead
                    call cursor(0, &textwidth)
                    if !s:FindOper(a:oper) | return [-1, 0] | endif
                endif
            endif
        else
            " break on the first one
            if !(a:end ? s:FindPairOnLine(a:oper) : s:FindOper(a:oper, 'c'))
                return [-1, 0]
            endif
        endif
    endif
    if s:GetFlag(a:oper, 'b', a:end) && !s:MatchIsSpaced(l:realpat, 1)
        return [col('.'), s:GetFlag(a:oper, 'a', a:end)]
    endif
    if s:GetFlag(a:oper, 'a', a:end) && !s:MatchIsSpaced(l:realpat, 0)
        return [s:MatchEnd(l:realpat) + 1, 0]
    endif
    " nothing to do
    return [-1, 0]
endfunction

" Inserts a line break for an operator, handling the flags as needed. If end is 
" non-zero, the s:ops[a:oper]['end'] is used instead of a:oper. Returns new 
" number of lines.
function s:OperBreak(oper, end = 0)
    let l:count = 1
    let l:ln = line('.')
    call cursor(0, 1)
    let l:more = 1
    while l:more
        let [l:col, l:more] = s:BreakCol(a:oper, a:end, l:more && l:count > 1)
        if l:col < 0 | break | endif
        call cursor(0, l:col)
        call s:InsertBreak(l:col == col('$') ? 'a' : 'i')
        let l:count += 1
    endwhile
    call cursor(l:ln, 1)
    return l:count
endfunction

function s:ComparePrecedence(i1, i2)
    return s:ops[a:i1]['z'] - s:ops[a:i2]['z']
endfunction

" Expands the group (key of doggroups) in line lnum.
function s:ExpandGroup(lnum, group)
    let l:count = 0
    call cursor(a:lnum, 1)
    let l:count += s:OperBreak(a:group) - 1
    let l:expandcount = s:ExpandLine(a:lnum) - 1
    let l:count += l:expandcount
    call cursor(a:lnum + l:count, 1)
    " fix indentation if the opening line was expanded
    if l:expandcount > 0
        exe (a:lnum + l:expandcount)..','..(a:lnum + l:count - 1)..'norm! =='
    endif
    let l:opercount = s:OperBreak(a:group, 1) - 1
    " expand the contents
    let l:count += s:ExpandLine(a:lnum + l:count) - 1
    " expand the part after the group
    let l:count += l:opercount
    let l:count += s:ExpandLine(a:lnum + l:count) - 1
    " restore cursor
    call cursor(a:lnum, 1)
    return l:count + 1
endfunction

" Expands the operator sequence on line lnum into multiple lines.
function s:ExpandOpers(lnum, oper)
    let l:count = 0
    call cursor(a:lnum, 1)
    let l:opc = s:OperBreak(a:oper)
    while l:opc > 1
        let l:count += l:opc - 2
        let l:count += s:ExpandLine(a:lnum + l:count)
        " proceed to after the expanded line
        call cursor(a:lnum + l:count, 1)
        let l:opc = s:OperBreak(a:oper)
    endwhile
    let l:count += s:ExpandLine(a:lnum + l:count) - 1
    call cursor(a:lnum, 1)
    return l:count + 1
endfunction

" Expands the line lnum as much as needed to try and meet the textwidth 
" criteria. Returns the number of lines that the original line now takes up. If 
" no changes are made, 1 will be returned (still 1 line of occupancy). Cursor 
" is placed at the beginning of the expanded line and in column 1
function s:ExpandLine(lnum)
    call cursor(a:lnum, 1)
    " don't reformat if it doesn't overflow
    if &textwidth <= 0 || strdisplaywidth(getline('.')) <= &textwidth
        return 1
    endif
    let l:chosen = ''
    for l:operator in s:opkeys
        call cursor(a:lnum, 1)
        " if the operator isn't found, skip it
        if !s:FindOper(l:operator)
            call cursor(a:lnum, 1)
            " make sure it's not just under the cursor. this has to be done 
            " separately because for some reason the 'c' flag makes search() 
            " stop searching after the first skipped match
            if !s:FindOper(l:operator, 'c')
                continue
            endif
        endif
        " check if it's suboptimal (leaves the line overflowing, so keep 
        " searching for an optimal choice)
        if s:BreakCol(l:operator, 0, 1)[0] - 1 > &textwidth
            " don't override existing suboptimal choice
            if l:chosen == '' | let l:chosen = l:operator | endif
            continue
        endif
        " optimal choice found
        let l:chosen = l:operator
        break
    endfor
    if l:chosen == '' | return 1 | endif
    call cursor(a:lnum, 1)
    " expand it as a group if it's a group operator
    if s:groups->index(l:chosen) >= 0
        return s:ExpandGroup(a:lnum, l:chosen)
    else
        return s:ExpandOpers(a:lnum, l:chosen)
    endif
endfunction

function s:GetOption(option, default, scopes = 'bg')
    for l:scope in a:scopes->split('\zs')
        if exists(l:scope .. ':' .. a:option)
            return eval(l:scope .. ':' .. a:option)
        endif
    endfor
    return a:default
endfunction

function DogFormat(lnum = v:lnum, count = v:count)
    " TODO: support auto-formatting while inserting
    if mode() =~? 'R\|i'
        return 1
    endif

    " generate script vars
    let s:ops = extendnew(s:dops, deepcopy(s:GetOption('dogops', {})), "force")
    let s:opkeys = keys(s:ops)->sort("s:ComparePrecedence")
    let s:groups = s:opkeys->copy()->filter("s:OpKeyIsGroup(v:val)")
    let s:slow = s:GetOption('dogslow', 0)
    let s:long = s:GetOption('doglong', 20)
    " clean up flags
    for l:op in s:opkeys
        call s:CleanFlags(s:ops[l:op])
    endfor

    " expand the lines
    let l:lnum = a:lnum
    for l:i in range(a:count)
        let l:lnum += s:ExpandLine(l:lnum)
    endfor
endfunction
