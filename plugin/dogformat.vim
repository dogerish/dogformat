vim9script
var dflags = 'aBLl'
var dops = {
    '\%([-+*/%&^|]\|\*\*\|<<\|>>>\?\|&&\|||\|??\)\?=>\?': { z: 21  },
    '\[':                                                 { z: 20, end:   '\]' },
    '\.':                                                 { z: 19, flags: 'bL' },
    '(':                                                  { z: 18, end:   ')'  },
    '{':                                                  { z: 17, end:   '}', flags: 'b' .. dflags },
    '\*\*':                                               { z: 13  },
    '*\|\/\|%':                                           { z: 12  },
    '+\|-':                                               { z: 11  },
    '<<\|>>\|>>>':                                        { z: 10  },
    '<\@!<=\?\|>\@!>=\?':                                 { z: 9   },
    '[!=]==\?':                                           { z: 8   },
    '&':                                                  { z: 7   },
    '\^':                                                 { z: 6   },
    '|':                                                  { z: 5   },
    '&&':                                                 { z: 4   },
    '||\|??':                                             { z: 3   },
    ',':                                                  { z: 1   },
    ';':                                                  { z: 0   }
}

# script vars that are generated
var ops = {}
var opkeys = []
var groups = []
var slow = 0
var long = 20

var skip_expr = 'InStringlike() || InGroup()'
# returns the name of the syntax at the cursor
def GetSynName(): string
    return synID(line('.'), col('.'), 0)->synIDattr("name")
enddef
# returns 1 if position line, col is in a string-like (string or comment)
def InStringlike(): bool
    return GetSynName() =~? 'string\|comment'
enddef
# returns 1 if the cursor is in a group that starts on the current line
# preconditions: script vars are generated
def InGroup(): bool
    var l = line('.')
    var c = col('.')
    for g in groups
        # if on the group opener, don't include the group opener in the search 
        # - avoid false positive where it thinks a group is inside itself
        var f = (getline(l)[c - 1 : ] =~# '^\%(' .. ops[g]['end'] .. '\)')
            ? 'c' : ''
        if searchpair(g, '', ops[g]['end'], 'nbz' .. f, "InStringlike()", l) !=
            0
            return 1
        endif
    endfor
    return 0
enddef

# returns true if the whole line is a comment or empty, excluding indentation
def LineIsComment(): bool
    return search('\S', 'c', line('.')) == 0 || 
        search('.', 'c', line('.'), 0, 'GetSynName() =~? "comment"') == 0
enddef

def OpIsGroup(op: dict<any>): bool
    return op->has_key('end')
enddef
def OpKeyIsGroup(opkey: string): bool
    return OpIsGroup(ops[opkey])
enddef
# cleans up flags, adding implicit or required flags
def CleanFlags(op: dict<any>)
    var fl = op->has_key('flags') ? op['flags'] : dflags
    # remove L flag for groups
    if fl =~# 'L' && OpIsGroup(op)
        fl = substitute(fl, '\CL', '', '')
    endif
    # force 'l' flag when the 'L' flag is present
    if fl =~# 'L' && fl !~# 'l'
        fl ..= 'l'
    endif
    # force 'a' flag for groups
    if fl !~# 'a' && OpIsGroup(op)
        fl ..= 'a'
    endif
    op['flags'] = fl
enddef

# Returns 1 if the operator has the flag. If end is nonzero, the ending flags 
# are considered instead. In reality, this just makes it convert the flag 
# argument to upper case before checking comparison. When end = 0, the flag 
# argument is not touched.
# preconditions: script vars are generated
def GetFlag(oper: string, flag: string, end = 0): bool
    return ops[oper]['flags'] =~# (end ? toupper(flag) : flag)
enddef

# finds pattern on the line. true if found
def FindOnLine(pat: string, flags = ''): bool
    return search(pat, flags, line('.'), 0, skip_expr) != 0
enddef
# finds pair on the line using searchpair. true if found
def FindPairOnLine(group: string, flags = ''): bool
    return searchpair(
        group, '', ops[group]['end'], flags, skip_expr, line('.')
    ) != 0
enddef
# return byte column at the end of the first match of {pat} on the cursor line 
# (-1 if not found):
#   when pat =      'the'
#   return that column ^
def MatchEnd(pat: string): number
    return getline('.')->matchstrpos(pat, col('.') - 1)[2]
enddef
# returns true if the match is either preceded or followed by only spaces.
# preconditions: cursor is on the start of the match if before is 1
def MatchIsSpaced(pat: string, before: bool): bool
    return before && (col('.') < 2 || getline('.')[: col('.') - 2] =~# '^\s*$')
        || !before && getline('.')[MatchEnd(pat) : ] =~# '^\s*$'
enddef

def ByteToVirtCol(col: number): number
    return getline('.')[: col - 1]->strdisplaywidth()
enddef

# Finds operator if unexpanded on the line. Returns true if found
def FindOper(oper: string, flags = ''): bool
    # match has to not be followed by only white-space
    if GetFlag(oper, 'a') && (FindOnLine(oper, flags) &&
        !MatchIsSpaced(oper, 0) || flags =~# 'b' &&
        FindOnLine(oper, flags))
        return 1
    endif
    if GetFlag(oper, 'b')
        # match has to not be prepended by only white-space. if it was, there 
        # must be another match after it
        var noc = substitute(flags, 'c', '', '')
        if FindOnLine(oper, flags) && !MatchIsSpaced(oper, 1) ||
            flags !~# 'b' && FindOnLine(oper, noc)
            return 1
        endif
    endif
    # found no match
    return 0
enddef

# insert a line break with optional mode instead of insert
def InsertBreak(mode = 'i')
    exe "norm! " .. mode .. "\<CR>"
    if slow > 0
        redraw
        exe 'sleep ' .. slow .. 'm'
    endif
enddef

def GetSectLength(startcol: number, endcol: number): number
    return getline('.')[startcol - 1 : endcol - 1]->trim()->strdisplaywidth()
enddef
def SectNeedsSplit(startcol: number, endcol: number): bool
    return GetSectLength(startcol, endcol) > long ||
        ByteToVirtCol(endcol) > &textwidth
enddef

# Return byte column where the break for the operator would be inserted and a 
# value that says whether it could have more to insert (1) or not (0) for the 
# current match: [col, more]. The more parameter should be the same as what was 
# returned on the last one. If it is 0, BreakCol will try to find the next 
# match instead of operating on the match under the cursor.
def BreakCol(oper: string, end = 0, more = 0): list<number>
    var realpat = end ? ops[oper]['end'] : oper
    if !more
        # find next match
        # operator wants last occurrence
        if GetFlag(oper, 'l') && !end
            # operator wants to break on long sections
            if GetFlag(oper, 'L')
                # try to find one that needs its own line first
                var last = col('.')
                var last_end = col('.')
                var iter_count = 0
                var found = 0
                while FindOper(oper)
                    if SectNeedsSplit(last_end + 1, col('.') - 1)
                        # this section needs to be on its own line
                        # go to the last match if this section isn't the first 
                        # of the line
                        if iter_count > 0 | cursor(0, last) | endif
                        found = 1
                        break
                    endif
                    last = col('.')
                    last_end = MatchEnd(oper)
                    iter_count += 1
                endwhile
                # nothing found if no section was long enough or went past 
                # textwidth, and the remaining section doesn't need to be 
                # split, or there is no matching operator on the line, even 
                # starting from the cursor.
                if !found && !(iter_count > 0 && 
                    SectNeedsSplit(last_end + 1, col('$') - 1))
                    return [-1, 0]
                endif
            else
                # line too short for it to make sense
                if virtcol('$') - 1 <= &textwidth
                    return [-1, 0]
                endif
                # search backwards from textwidth
                # TODO: do i need to account for 'a' and 'b' operator flags?
                cursor(0, &textwidth + 1)
                if !FindOper(oper, 'b')
                    # backward didn't work; try searching forward instead
                    cursor(0, &textwidth)
                    if !FindOper(oper) | return [-1, 0] | endif
                endif
            endif
        else
            # break on the first one
            if !(end ? FindPairOnLine(oper) : FindOper(oper, 'c'))
                return [-1, 0]
            endif
        endif
    endif
    if GetFlag(oper, 'b', end) && !MatchIsSpaced(realpat, 1)
        return [col('.'), GetFlag(oper, 'a', end) ? 1 : 0]
    endif
    if GetFlag(oper, 'a', end) && !MatchIsSpaced(realpat, 0)
        return [MatchEnd(realpat) + 1, 0]
    endif
    # nothing to do
    return [-1, 0]
enddef

# Inserts a line break for an operator, handling the flags as needed. If end is 
# non-zero, the ops[oper]['end'] is used instead of oper. Returns new 
# number of lines.
def OperBreak(oper: string, end = 0): number
    var count = 1
    var ln = line('.')
    cursor(0, 1)
    var more = 1
    while more != 0
        var retv = BreakCol(oper, end, more && count > 1 ? 1 : 0)
        more = retv[1]
        if retv[0] < 0 | break | endif
        cursor(0, retv[0])
        InsertBreak(retv[0] == col('$') ? 'a' : 'i')
        count += 1
    endwhile
    cursor(ln, 1)
    return count
enddef

def ComparePrecedence(i1: string, i2: string): number
    return ops[i1]['z'] - ops[i2]['z']
enddef

# Expands the group (key of doggroups) in line lnum.
def ExpandGroup(lnum: number, group: string): number
    var count = 0
    cursor(lnum, 1)
    count += OperBreak(group) - 1
    var expandcount = ExpandLine(lnum) - 1
    count += expandcount
    cursor(lnum + count, 1)
    # fix indentation if the opening line was expanded
    if expandcount > 0
        exe (lnum + expandcount) .. ',' .. (lnum + count - 1) .. 'norm! =='
    endif
    var opercount = OperBreak(group, 1) - 1
    # expand the contents
    count += ExpandLine(lnum + count) - 1
    # expand the part after the group
    count += opercount
    count += ExpandLine(lnum + count) - 1
    # restore cursor
    cursor(lnum, 1)
    return count + 1
enddef

# Expands the operator sequence on line lnum into multiple lines.
def ExpandOpers(lnum: number, oper: string): number
    var count = 0
    cursor(lnum, 1)
    var opc = OperBreak(oper)
    while opc > 1
        count += opc - 2
        count += ExpandLine(lnum + count)
        # proceed to after the expanded line
        cursor(lnum + count, 1)
        opc = OperBreak(oper)
    endwhile
    count += ExpandLine(lnum + count) - 1
    cursor(lnum, 1)
    return count + 1
enddef

# Expands the line lnum as much as needed to try and meet the textwidth 
# criteria. Returns the number of lines that the original line now takes up. If 
# no changes are made, 1 will be returned (still 1 line of occupancy). Cursor 
# is placed at the beginning of the expanded line and in column 1
def ExpandLine(lnum: number): number
    cursor(lnum, 1)
    # don't reformat if it doesn't overflow
    if &textwidth <= 0 || strdisplaywidth(getline('.')) <= &textwidth
        return 1
    endif
    var chosen = ''
    for operator in opkeys
        cursor(lnum, 1)
        # if the operator isn't found, skip it
        if !FindOper(operator)
            cursor(lnum, 1)
            # make sure it's not just under the cursor. this has to be done 
            # separately because for some reason the 'c' flag makes search() 
            # stop searching after the first skipped match
            if !FindOper(operator, 'c')
                continue
            endif
        endif
        # check if it's suboptimal (leaves the line overflowing, so keep 
        # searching for an optimal choice)
        if BreakCol(operator, 0, 1)[0] - 1 > &textwidth
            # don't override existing suboptimal choice
            if chosen == '' | chosen = operator | endif
            continue
        endif
        # optimal choice found
        chosen = operator
        break
    endfor
    if chosen == '' | return 1 | endif
    cursor(lnum, 1)
    # expand it as a group if it's a group operator
    if groups->index(chosen) >= 0
        return ExpandGroup(lnum, chosen)
    else
        return ExpandOpers(lnum, chosen)
    endif
enddef

def GetOption(option: string, default: any, scopes = 'bwtg'): any
    for scope in scopes->split('\zs')
        if exists(scope .. ':' .. option)
            return eval(scope .. ':' .. option)
        endif
    endfor
    return default
enddef

# formats with the default formatter instead of DogFormat. returns the line 
# number after the formatted section
def DefaultFormat(lnum: number, count: number): number
    var old_fex = &fex
    setlocal fex=
    try
        execute 'norm! ' .. lnum .. 'GV' .. (lnum + count - 1) .. 'Ggq'
    finally
        &fex = old_fex
    endtry
    return line('.') + 1
enddef

def g:DogFormat(lnum = v:lnum, count = v:count): number
    # auto-formatting while inserting isn't possible because the ending 
    # position of the cursor can't be set and doesn't move automatically. use 
    # default formatting for comments
    if mode() =~# 'R\|i'
        return LineIsComment() ? 1 : 0
    endif

    # generate script vars
    ops = extendnew(dops, deepcopy(GetOption('dogops', {})), "force")
    opkeys = keys(ops)->sort("ComparePrecedence")
    groups = opkeys->copy()->filter("OpKeyIsGroup(v:val)")
    slow = GetOption('dogslow', 0)
    long = GetOption('doglong', 20)
    # clean up flags
    for op in opkeys
        CleanFlags(ops[op])
    endfor

    var l = lnum
    # start of a comment section
    var com_start = 0
    # expand the lines
    for i in range(count)
        cursor(l, 1)
        # skip comment lines
        if LineIsComment()
            if com_start == 0
                com_start = l
            endif
            l += 1
            continue
        endif
        # use default formatting on comment section
        if com_start != 0
            l = DefaultFormat(com_start, l - com_start)
            com_start = 0
        endif
        l += ExpandLine(l)
    endfor
    if com_start != 0
        l = DefaultFormat(com_start, l - com_start)
    endif
    cursor(l - 1, 1)
    return 0
enddef
