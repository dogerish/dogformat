let g:dogbreakon = { '(': { 'end': ')' } }

let s:skip_expr = 's:SkipFunc()'
function s:SkipFunc()
	return synIDattr(synID(line('.'), col('.'), 0), "name") =~? "string\\|comment"
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

" expands the line under the cursor as much as needed to try and meet the 
" textwidth criteria. Returns the number of lines that the original line now 
" takes up. If no changes are made, 1 will be returned (still 1 line of 
" occupancy). Cursor is placed at the beginning of the expanded line (col 0)
function s:ExpandLine(lnum)
	call cursor(lnum, 0)
	let count = 1
	" TODO: check for commas existing after the closing parenthesis
	if s:FindOnLine('(', 'cp') == 0
		return count
	endif
	call s:AppendBreak()
	let count += 1
	if s:FindPairOnLine('(', '', ')', 'cW') <= 0
		return count
	endif
	call s:InsertBreak()
	let count += 1
	call cursor(lnum, 0)
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
