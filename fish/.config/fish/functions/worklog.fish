function worklog
set -l tempdir (pwd)
cd ~/Documents/note
nvim log.md
cd $tempdir
end
