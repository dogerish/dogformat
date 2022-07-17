let g:doggroups = ['\[', '(', '{']
" flags:
"	b - break before this operator
"	B - break before the ending operator
"	a - break after this operator
"	A - break after the ending operator
let s:dflags = 'aB'
let g:dogops = {
			\ '\[':                                                  { 'z': 20, 'end': '\]' },
			\ '\.':                                                  { 'z': 19, 'flags': 'b' },
			\ '(':                                                   { 'z': 18, 'end': ')'  },
			\ '{':                                                   { 'z': 17, 'end': '}'  },
			\ '\*\*':                                                { 'z': 13  },
			\ '*\|\/\|%':                                            { 'z': 12  },
			\ '+\|-':                                                { 'z': 11  },
			\ '<<\|>>\|>>>':                                         { 'z': 10  },
			\ '<=\?\|>=\?':                                          { 'z': 9   },
			\ '[!=]==\?':                                            { 'z': 8   },
			\ '&':                                                   { 'z': 7   },
			\ '\^':                                                  { 'z': 6   },
			\ '|':                                                   { 'z': 5   },
			\ '&&':                                                  { 'z': 4   },
			\ '||\|??':                                              { 'z': 3   },
			\ '\%([-+*/%&^|]\|\*\*\|<<\|>>>\?\|&&\|||\|??\)\?=\|=>': { 'z': 2   },
			\ ',':                                                   { 'z': 1   }
		\ }

let s:skip_expr = 's:SkipFunc()'

" skip if in a string-like
function s:IgnoreStringy()
	return synIDattr(synID(line('.'), col('.'), 0), "name") =~? "string\\|comment"
endfunction

function s:SkipFunc()
	if s:IgnoreStringy() | return 1 | endif
	" skip if in a group
	for l:group in g:doggroups
		let l:flags = 'nz'
		" if on the group opener, include the group opener in the search - 
		" avoid false positive where it thinks a group is inside itself
		if getline('.')[col('.') - 1:] =~ '^\%(' . l:group . '\)'
			let l:flags .= 'c'
		endif
		if searchpair(l:group, '', g:dogops[l:group]['end'], l:flags, "s:IgnoreStringy()", line('.')) != 0
			return 1
		endif
	endfor
endfunction

" finds pattern on the line
function s:FindOnLine(pat, flags)
	return search(a:pat, a:flags, line('.'), 0, s:skip_expr)
endfunction
" finds operator if unexpanded on the line. returns 0 if not found
function s:FindOper(oper, flags)
	if s:OperHasFlag(a:oper, 'a')
		" match has to not be followed by only whitespace
		return s:FindOnLine(a:oper, a:flags) &&
					\ getline('.')[s:MatchEnd(a:oper):] !~ '^\s*$'
	elseif s:OperHasFlag(a:oper, 'b')
		" no matches at all
		if s:FindOnLine(a:oper, a:flags) == 0
			return 0
		endif
		let l:noc = substitute(a:flags, 'c', '', '')
		" match has to not be prepended by only whitespace. if it was, there 
		" must be another match after it
		if getline('.')[:col('.') - 2] =~ '^\s*$' &&
					\ s:FindOnLine(a:oper, l:noc) == 0
			return 0
		endif
		" found the match
		return 1
	endif
endfunction

" finds pair on the line using searchpair
function s:FindPairOnLine(start, mid, end, flags)
	return searchpair(a:start, a:mid, a:end, a:flags, s:skip_expr, line('.'))
endfunction

function s:OperHasFlag(oper, flag, end = 0)
	let l:flags = g:dogops[a:oper]->has_key('flags') ? g:dogops[a:oper]['flags'] : s:dflags
	return l:flags =~# (a:end ? toupper(a:flag) : a:flag)
endfunction

" move cursor to end of match, so an insert command would insert directly after
function s:MatchEnd(pat)
	let l:len = getline('.')->matchstr(a:pat, col('.') - 1)->strlen()
	return col('.') + l:len
endfunction

" inserts a line break for an operator, handling the flags as needed. assumes 
" that the cursor is positioned at the start of the pattern match. if end is 
" non-zero, the g:dogops[a:oper]['end'] is used instead of a:oper
function s:OperBreak(oper, end = 0)
	let l:realpat = a:end ? g:dogops[a:oper]['end'] : a:oper
	if s:OperHasFlag(a:oper, 'b', a:end)
		call s:InsertBreak()
		call cursor(line('.'), 1 + s:MatchEnd(l:realpat))
	endif
	if s:OperHasFlag(a:oper, 'a', a:end)
		call cursor(line('.'), s:MatchEnd(l:realpat))
		call s:InsertBreak()
	endif
	" has neither of the flags
	if !s:OperHasFlag(a:oper, 'b\|a', a:end)
		throw 'Operator needs at least one of the b or a flags'
	endif
endfunction

function s:InsertBreak()
	exe "norm! i\<CR>"
endfunction

function s:ComparePrecedence(i1, i2)
	let [l:z1, l:z2] = [g:dogops[a:i1]['z'], g:dogops[a:i2]['z']]
	if l:z1 == l:z2 | return 0 | endif
	return (l:z1 < l:z2) ? -1 : 1
endfunction

" expands the group (key of doggroups) in line lnum. otherwise the same as 
" s:ExpandLine
function s:ExpandGroup(lnum, group)
	let l:count = 0
	call s:FindOnLine(a:group, 'c')
	call s:OperBreak(a:group)
	let l:count += s:ExpandLine(a:lnum)
	call cursor(a:lnum + l:count, 1)
	" fix indentation if the opening line was expanded
	if l:count > 1
		norm! ==
	endif
	call s:FindPairOnLine(a:group, '', g:dogops[a:group]['end'], '')
	call s:OperBreak(a:group, 1)
	let l:count += s:ExpandLine(a:lnum + l:count)
	let l:count += s:ExpandLine(a:lnum + l:count)
	" restore cursor
	call cursor(a:lnum, 1)
	return l:count
endfunction

" expands the operator sequence on line lnum into multiple lines. like 
" s:ExpandLine
function s:ExpandOpers(lnum, oper)
	let l:count = 0
	while s:FindOper(a:oper, '')
		call s:OperBreak(a:oper)
		let l:count += s:ExpandLine(a:lnum + l:count)
		" proceed to after the expanded line
		call cursor(a:lnum + l:count, 1)
	endwhile
	let l:count += s:ExpandLine(a:lnum + l:count)
	call cursor(a:lnum, 1)
	return l:count
endfunction

" expands the line lnum as much as needed to try and meet the textwidth 
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
	for l:operator in keys(g:dogops)->sort("s:ComparePrecedence")
		call cursor(a:lnum, 1)
		" if the operator isn't found or it's at the end of the line, skip it
		if s:FindOper(l:operator, 'c') == 0
			continue
		endif
		" check if it's suboptimal (leaves the line overflowing, so keep 
		" searching for an optimal choice)
		if virtcol('.') > &textwidth
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
	if g:doggroups->index(l:chosen) >= 0
		return s:ExpandGroup(a:lnum, l:chosen)
	else
		return s:ExpandOpers(a:lnum, l:chosen)
	endif
endfunction

function DogFormat(lnum = v:lnum, count = v:count, char = v:char)
	if mode() =~? 'R\|i'
		return 1
	endif
	let l:lnum = a:lnum
	for l:i in range(a:count)
		let l:lnum += s:ExpandLine(l:lnum)
	endfor
endfunction
