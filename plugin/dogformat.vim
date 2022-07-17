let g:doggroups = ['\[', '(', '{']
let g:dogops = {
			\ '\[':                                                 { 'z': 20, 'end': '\]' },
			\ '\.':                                                 { 'z': 19  },
			\ '(':                                                  { 'z': 18, 'end': ')'  },
			\ '{':                                                  { 'z': 17, 'end': '}'  },
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
			\ '\%([-+*/%&^|]\|\*\*\|<<\|>>>\?\|&&\|||\|??\)\?=\|=>': { 'z': 2   },
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

" finds pair on the line using searchpair
function s:FindPairOnLine(start, mid, end, flags)
	return searchpair(a:start, a:mid, a:end, a:flags, s:skip_expr, line('.'))
endfunction

" inserts a line break after a pattern match
function s:PatternBreak(pat)
	let l:len = getline('.')->matchstr(a:pat, col('.') - 1)->strlen()
	call cursor(line('.'), col('.') + l:len)
	call s:InsertBreak()
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
	call cursor(a:lnum, 1)
	let l:count = 0
	call s:FindOnLine(a:group, 'c')
	call s:PatternBreak(a:group)
	let l:count += s:ExpandLine(a:lnum)
	call cursor(a:lnum + l:count, 1)
	" fix indentation if the opening line was expanded
	if l:count > 1
		norm! ==
	endif
	call s:FindPairOnLine(a:group, '', g:dogops[a:group]['end'], '')
	call s:InsertBreak()
	let l:count += s:ExpandLine(a:lnum + l:count)
	let l:count += s:ExpandLine(a:lnum + l:count)
	" restore cursor
	call cursor(a:lnum, 1)
	return l:count
endfunction

" expands the operator sequence on line lnum into multiple lines. like 
" s:ExpandLine
function s:ExpandOpers(lnum, oper)
	call cursor(a:lnum, 1)
	let l:count = 0
	while s:FindOnLine(a:oper, '')
		call s:PatternBreak(a:oper)
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
" is placed at the beginning of the expanded line (col 0)
function s:ExpandLine(lnum)
	call cursor(a:lnum, 1)
	" don't reformat if it doesn't overflow
	if &textwidth <= 0 || strdisplaywidth(getline('.')) <= &textwidth
		return 1
	endif
	for l:operator in keys(g:dogops)->sort("s:ComparePrecedence")
		" if the operator isn't found or it's at the end of the line, skip it
		if s:FindOnLine(l:operator, '') == 0 || getline('.')[col('.')-1:] =~ '^\%(' . l:operator . '\)\s*$'
			call cursor(a:lnum, 1)
			continue
		endif
		" expand it as a group if it's a group operator
		if g:doggroups->index(l:operator) >= 0
			return s:ExpandGroup(a:lnum, l:operator)
		else
			return s:ExpandOpers(a:lnum, l:operator)
		endif
	endfor
	return 1
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
