e plugin/dogformat.vim
vsplit test.js | setlocal fex=DogFormat()
au BufWritePost *dogformat.vim so %
