" when 1, it redraws and pauses for this amount of milliseconds after each 
" insert. nice for debugging or demo'ing
if !exists("g:dogslow") | let g:dogslow = 0 | endif
" Add or override operators
if !exists("g:dogops") | let g:dogops = {} | endif
" flags:
"	b - break before this operator
"	a - break after this operator (always on for groups)
"	B - break before the ending operator
let s:dflags = 'aB'
let s:dops = {
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

" script vars that are generated
let s:ops = {}
let s:opkeys = []
let s:groups = []

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

" returns 1 if the operator has the flag. if end is nonzero, the ending flags 
" are considered instead. in reality, this just makes it convert the flag 
" argument to upper case before checking comparison. when end = 0, the flag 
" argument is not touched
" preconditions: script vars are generated
function s:OperHasFlag(oper, flag, end = 0)
	let l:flags = s:ops[a:oper]->has_key('flags')
				\ ? s:ops[a:oper]['flags'] : s:dflags
	" force 'a' flag for groups
	if !a:end && l:flags !~# 'a' && s:groups->index(a:oper) >= 0
		let l:flags ..= 'a'
	endif
	return l:flags =~# (a:end ? toupper(a:flag) : a:flag)
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
"	when pat =      'the'
"	return that column ^
function s:MatchEnd(pat)
	return getline('.')->matchstrpos(a:pat, col('.') - 1)[2]
endfunction
" returns true if the match is either preceded or followed by only spaces.
" preconditions: cursor is on the start of the match if before is 1
function s:MatchIsSpaced(pat, before)
	return a:before && (col('.') <= 1 || getline('.')[:col('.')-2] =~# '^\s*$')
				\ || !a:before && getline('.')[s:MatchEnd(a:pat):] =~# '^\s*$'
endfunction

" finds operator if unexpanded on the line. returns 0 if not found
function s:FindOper(oper, flags = '')
	" match has to not be followed by only whitespace
	if s:OperHasFlag(a:oper, 'a') && s:FindOnLine(a:oper, a:flags) &&
				\ !s:MatchIsSpaced(a:oper, 0)
		return 1
	endif
	if s:OperHasFlag(a:oper, 'b')
		" match has to not be prepended by only whitespace. if it was, there 
		" must be another match after it
		let l:noc = substitute(a:flags, 'c', '', '')
		if s:FindOnLine(a:oper, a:flags) && !s:MatchIsSpaced(a:oper, 1) ||
					\ s:FindOnLine(a:oper, l:noc)
			return 1
		endif
	endif
	" found no match
	return 0
endfunction

" insert a line break with optional mode instead of insert
function s:InsertBreak(mode = 'i')
	exe "norm! " . a:mode . "\<CR>"
	if g:dogslow
		redraw
		exe 'sleep '..g:dogslow..'m'
	endif
endfunction
" return byte column where the break for the operator would be inserted and a 
" value that says whether it could have more to insert (1) or not (0). [col, 
" more]
function s:BreakCol(oper, end = 0)
	let l:realpat = a:end ? s:ops[a:oper]['end'] : a:oper
	if s:OperHasFlag(a:oper, 'b', a:end) && !s:MatchIsSpaced(l:realpat, 1)
		return [col('.'), s:OperHasFlag(a:oper, 'a', a:end)]
	endif
	if s:OperHasFlag(a:oper, 'a', a:end) && !s:MatchIsSpaced(l:realpat, 0)
		return [s:MatchEnd(l:realpat) + 1, 0]
	endif
	" has neither of the flags
	return [-1, 0]
endfunction
" inserts a line break for an operator, handling the flags as needed. assumes 
" that the cursor is positioned at the start of the pattern match. if end is 
" non-zero, the s:ops[a:oper]['end'] is used instead of a:oper. returns new 
" number of lines
function s:OperBreak(oper, end = 0)
	let l:count = 1
	let l:ln = line('.')
	let l:more = 1
	while l:more
		let [l:col, l:more] = s:BreakCol(a:oper, a:end)
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

" expands the group (key of doggroups) in line lnum. otherwise the same as 
" s:ExpandLine
function s:ExpandGroup(lnum, group)
	let l:count = 0
	call cursor(a:lnum, 1)
	call s:FindOnLine(a:group)
	let l:count += s:OperBreak(a:group) - 1
	let l:expandcount = s:ExpandLine(a:lnum) - 1
	let l:count += l:expandcount
	call cursor(a:lnum + l:count, 1)
	" fix indentation if the opening line was expanded
	if l:expandcount > 0
		exe (a:lnum + l:expandcount) . ',' . (a:lnum + l:count - 1) . 'norm! =='
	endif
	call s:FindPairOnLine(a:group)
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
		if s:BreakCol(l:operator)[0] - 1 > &textwidth
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

function DogFormat(lnum = v:lnum, count = v:count)
	" TODO: support autoformatting while inserting
	if mode() =~? 'R\|i'
		return 1
	endif
	" generate script vars
	let s:ops = extendnew(s:dops, g:dogops, "force")
	let s:opkeys = keys(s:ops)->sort("s:ComparePrecedence")
	let s:groups = s:opkeys->copy()->filter("s:ops[v:val]->has_key('end')")
	" expand the lines
	let l:lnum = a:lnum
	for l:i in range(a:count)
		let l:lnum += s:ExpandLine(l:lnum)
	endfor
endfunction
