if expand('%') == ""
    silent edit test.js
endif
set fex=DogFormat()
autocmd BufWritePost ../plugin/dogformat.vim source ../plugin/dogformat.vim
autocmd VimEnter * ++once ++nested {
    silent vertical rightbelow split ../plugin/dogformat.vim
    setlocal fex=
    }
