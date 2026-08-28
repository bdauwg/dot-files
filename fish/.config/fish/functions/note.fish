function note
set -l tempcd (pwd) 
cd ~/Documents/note
nvim a.md
cd $tempcd
end
