let g:doggroups = ['\[', '(', '{']
" flags:
"	b - break before this operator
"	a - break after this operator (always on for groups)
"	B - break before the ending operator
let s:dflags = 'aB'
let g:dogops = {
			\ '\[':                                                 { 'z': 20, 'end':   '\]' },
			\ '\.':                                                 { 'z': 19, 'flags': 'b'  },
			\ '(':                                                  { 'z': 18, 'end':   ')'  },
			\ '{':                                                  { 'z': 17, 'end':   '}', 'flags': 'baB' },
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

let s:skip_expr = 's:SkipFunc()'

" skip if in a string-like
function s:IgnoreStringy()
	return synIDattr(synID(line('.'), col('.'), 0), "name") =~? "string\\|comment"
endfunction

function s:SkipFunc()
	if s:IgnoreStringy() | return 1 | endif
	" skip if in a group
	for l:group in g:doggroups
		let l:flags = 'nbz'
		" if on the group opener, don't include the group opener in the search 
		" - avoid false positive where it thinks a group is inside itself
		if getline('.')[col('.') - 1:] =~ '^\%(' . g:dogops[l:group]['end'] . '\)'
			let l:flags .= 'c'
		endif
		if searchpair(l:group, '', g:dogops[l:group]['end'], l:flags, "s:IgnoreStringy()", line('.')) != 0
			return 1
		endif
	endfor
endfunction

" TODO: reorganize functions to be in a logical order

" finds pattern on the line
function s:FindOnLine(pat, flags)
	return search(a:pat, a:flags, line('.'), 0, s:skip_expr)
endfunction
" finds operator if unexpanded on the line. returns 0 if not found
function s:FindOper(oper, flags)
	" match has to not be followed by only whitespace
	if s:OperHasFlag(a:oper, 'a') && s:FindOnLine(a:oper, a:flags) &&
				\ getline('.')[s:MatchEnd(a:oper):] !~ '^\s*$'
		return 1
	endif
	if s:OperHasFlag(a:oper, 'b')
		" match has to not be prepended by only whitespace. if it was, there 
		" must be another match after it
		let l:noc = substitute(a:flags, 'c', '', '')
		if (s:FindOnLine(a:oper, a:flags) &&
					\ getline('.')[:col('.') - 2] !~ '^\s*$') ||
					\ s:FindOnLine(a:oper, l:noc)
			return 1
		endif
	endif
	" found no match
	return 0
endfunction

" finds pair on the line using searchpair
function s:FindPairOnLine(start, mid, end, flags)
	return searchpair(a:start, a:mid, a:end, a:flags, s:skip_expr, line('.'))
endfunction

function s:OperHasFlag(oper, flag, end = 0)
	let l:flags = g:dogops[a:oper]->has_key('flags') ? g:dogops[a:oper]['flags'] : s:dflags
	if g:doggroups->index(a:oper) >= 0
		let l:flags .= 'a'
	endif
	return l:flags =~# (a:end ? toupper(a:flag) : a:flag)
endfunction

" move cursor to end of match, so an insert command would insert directly after
function s:MatchEnd(pat)
	let l:len = getline('.')->matchstr(a:pat, col('.') - 1)->strlen()
	return col('.') + l:len
endfunction

" inserts a line break for an operator, handling the flags as needed. assumes 
" that the cursor is positioned at the start of the pattern match. if end is 
" non-zero, the g:dogops[a:oper]['end'] is used instead of a:oper. returns new 
" number of lines
function s:OperBreak(oper, end = 0)
	let l:count = 1
	let l:ln = line('.')
	let l:realpat = a:end ? g:dogops[a:oper]['end'] : a:oper
	if s:OperHasFlag(a:oper, 'b', a:end)
		call s:InsertBreak()
		call cursor(line('.'), col('.') + 1)
		let l:count += 1
	endif
	if s:OperHasFlag(a:oper, 'a', a:end)
		call cursor(line('.'), s:MatchEnd(l:realpat) - 1)
		" append in case it's the end of the line
		call s:InsertBreak('a')
		let l:count += 1
	endif
	" has neither of the flags
	if !s:OperHasFlag(a:oper, 'b\|a', a:end)
		throw 'Operator needs at least one of the b or a flags'
	endif
	call cursor(l:ln, 1)
	return l:count
endfunction

function s:InsertBreak(mode = 'i')
	exe "norm! " . a:mode . "\<CR>"
endfunction

function s:ComparePrecedence(i1, i2)
	let [l:z1, l:z2] = [g:dogops[a:i1]['z'], g:dogops[a:i2]['z']]
	if l:z1 == l:z2 | return 0 | endif
	return l:z1 - l:z2
endfunction

" expands the group (key of doggroups) in line lnum. otherwise the same as 
" s:ExpandLine
function s:ExpandGroup(lnum, group)
	let l:count = 0
	call cursor(a:lnum, 1)
	call s:FindOnLine(a:group, '')
	let l:count += s:OperBreak(a:group) - 1
	let l:expandcount = s:ExpandLine(a:lnum) - 1
	let l:count += l:expandcount
	call cursor(a:lnum + l:count, 1)
	" fix indentation if the opening line was expanded
	if l:expandcount > 0
		exe (a:lnum + l:expandcount) . ',' . (a:lnum + l:count - 1) . 'norm! =='
	endif
	call s:FindPairOnLine(a:group, '', g:dogops[a:group]['end'], '')
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

" expands the operator sequence on line lnum into multiple lines. like 
" s:ExpandLine
function s:ExpandOpers(lnum, oper)
	let l:count = 0
	call cursor(a:lnum, 1)
	while s:FindOper(a:oper, '')
		let l:count += s:OperBreak(a:oper) - 2
		let l:count += s:ExpandLine(a:lnum + l:count)
		" proceed to after the expanded line
		call cursor(a:lnum + l:count, 1)
	endwhile
	let l:count += s:ExpandLine(a:lnum + l:count) - 1
	call cursor(a:lnum, 1)
	return l:count + 1
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
		" if the operator isn't found, skip it
		if s:FindOper(l:operator, '') == 0
			call cursor(a:lnum, 1)
			if s:FindOper(l:operator, 'c') == 0
				continue
			endif
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
	" TODO: support autoformatting while inserting
	if mode() =~? 'R\|i'
		return 1
	endif
	let l:lnum = a:lnum
	for l:i in range(a:count)
		let l:lnum += s:ExpandLine(l:lnum)
	endfor
endfunction
