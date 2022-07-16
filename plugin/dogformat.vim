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
	for scope in g:dogscopes
		let flags = 'nz'
		" if on the scope opener, include the scope opener in the search - 
		" avoid false positive where it thinks a scope is inside itself
		if getline('.')[col('.') - 1:] =~# scope
			let flags .= 'c'
		endif
		if searchpair(scope, '', g:dogops[scope]['end'], flags, "s:IgnoreStringy()", line('.')) != 0
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
	let [z1, z2] = [g:dogops[a:i1]['z'], g:dogops[a:i2]['z']]
	if z1 == z2 | return 0 | endif
	return (z1 > z2) ? -1 : 1
endfunction

" expands the scope (key of dogscopes) in line lnum. otherwise the same as 
" s:ExpandLine
function s:ExpandScope(lnum, scope)
	call cursor(a:lnum, 1)
	let count = 1
	call s:FindOnLine(a:scope, 'c')
	call s:AppendBreak()
	let count += 1
	call s:FindPairOnLine(a:scope, '', g:dogops[a:scope]['end'], '')
	call s:InsertBreak()
	let count += 1
	call cursor(a:lnum, 1)
	return count
endfunction

" expands the operator sequence on line lnum into multiple lines. like 
" s:ExpandLine
function s:ExpandOpers(lnum, oper)
	call cursor(a:lnum, 1)
	let count = 1
	while s:FindOnLine(a:oper, '')
		call s:AppendBreak()
		let count += 1
	endwhile
	call cursor(a:lnum, 1)
	return count
endfunction

" expands the line lnum as much as needed to try and meet the textwidth 
" criteria. Returns the number of lines that the original line now takes up. If 
" no changes are made, 1 will be returned (still 1 line of occupancy). Cursor 
" is placed at the beginning of the expanded line (col 0)
function s:ExpandLine(lnum)
	call cursor(a:lnum, 1)
	let count = 1
	for operator in keys(g:dogops)->sort("s:ComparePrecedence")
		" if the scope opener isn't found, skip it
		if s:FindOnLine(operator, 'c') == 0
			continue
		endif
		if g:dogscopes->index(operator) >= 0
			let count = s:ExpandScope(a:lnum, operator)
			break
		endif
		let count = s:ExpandOpers(a:lnum, operator)
		break
	endfor
	return count
endfunction

function DogFormat(lnum = v:lnum, count = v:count, char = v:char)
	if mode() =~? 'R\|i'
		return 1
	endif
	let lnum = a:lnum
	for offset in range(a:count)
		let lnum += s:ExpandLine(lnum + offset)
	endfor
endfunction
