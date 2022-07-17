let g:dogscopes = ['(']
let g:dogops = {
			\ '(': { 'z': 0, 'end': ')' },
			\ ',': { 'z': 10 }
		\ }

let s:skip_expr = 's:SkipFunc()'

" skip if in a string-like
function s:IgnoreStringy()
	return synIDattr(synID(line('.'), col('.'), 0), "name") =~? "string\\|comment"
endfunction

function s:SkipFunc()
	if s:IgnoreStringy() | return 1 | endif
	" skip if in a scope
	for l:scope in g:dogscopes
		let l:flags = 'nz'
		" if on the scope opener, include the scope opener in the search - 
		" avoid false positive where it thinks a scope is inside itself
		if getline('.')[col('.') - 1:] =~ l:scope
			let l:flags .= 'c'
		endif
		if searchpair(l:scope, '', g:dogops[scope]['end'], l:flags, "s:IgnoreStringy()", line('.')) != 0
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

function s:AppendBreak()
	norm a
endfunction
function s:InsertBreak()
	norm i
endfunction

function s:ComparePrecedence(i1, i2)
	let [l:z1, l:z2] = [g:dogops[a:i1]['z'], g:dogops[a:i2]['z']]
	if l:z1 == l:z2 | return 0 | endif
	return (l:z1 > l:z2) ? -1 : 1
endfunction

" expands the scope (key of dogscopes) in line lnum. otherwise the same as 
" s:ExpandLine
function s:ExpandScope(lnum, scope)
	call cursor(a:lnum, 1)
	let l:count = 1
	call s:FindOnLine(a:scope, 'c')
	call s:AppendBreak()
	let l:count += 1
	call s:FindPairOnLine(a:scope, '', g:dogops[a:scope]['end'], '')
	call s:InsertBreak()
	let l:count += s:ExpandLine(a:lnum + 1)
	" restore cursor
	call cursor(a:lnum, 1)
	return l:count
endfunction

" expands the operator sequence on line lnum into multiple lines. like 
" s:ExpandLine
function s:ExpandOpers(lnum, oper)
	call cursor(a:lnum, 1)
	let l:count = 1
	while s:FindOnLine(a:oper, '')
		call s:AppendBreak()
		let l:count += s:ExpandLine(a:lnum + l:count - 1)
		" proceed to after the expanded line
		call cursor(a:lnum + l:count - 1, 1)
	endwhile
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
		if s:FindOnLine(l:operator, '') == 0 || getline('.')[col('.')-1:] =~ '^' . l:operator . '\s*$'
			call cursor(a:lnum, 1)
			continue
		endif
		" expand it as a scope if it's a scope operator
		if g:dogscopes->index(l:operator) >= 0
			return s:ExpandScope(a:lnum, l:operator)
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
	for l:offset in range(a:count)
		let l:lnum += s:ExpandLine(l:lnum + l:offset) - 1
	endfor
endfunction
