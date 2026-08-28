# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if test -f /home/bramos/miniconda3/bin/conda
    eval /home/bramos/miniconda3/bin/conda "shell.fish" "hook" $argv | source
else
    # if test -f "/home/bramos/miniconda3/etc/fish/conf.d/conda.fish"
    #     . "/home/bramos/miniconda3/etc/fish/conf.d/conda.fish"
    # else
    #     set -x PATH "/home/bramos/miniconda3/bin" $PATH
    # end
    if test -nf "/home/bramos/miniconda3/etc/fish/conf.d/conda.fish"
        set -x PATH "/home/bramos/miniconda3/bin" $PATH
    end
end

# <<< conda initialize <<<
if status is-interactive
    # Commands to run in interactive sessions can go here
    starship init fish | source
end

# user-local binaries (jj, sesh, lazygit, jrnl, fd/bat shims land here)
fish_add_path $HOME/.local/bin
fish_add_path $HOME/go/bin

# rust
fish_add_path $HOME/.cargo/bin

# go toolchain: /usr/local/go on machines bootstrapped before the unprivileged
# refactor, ~/.local/golang on the ones after it. `go install` output goes to
# ~/.local/bin via GOBIN, but ~/go/bin stays on PATH for anything installed by hand
test -d /usr/local/go/bin; and fish_add_path /usr/local/go/bin
test -d $HOME/.local/golang/bin; and fish_add_path $HOME/.local/golang/bin

# NVM setup
# set -Ux NVM_DIR "$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

alias l "lsd"
alias la "lsd -a"
alias ll "lsd -l"
alias lla "lsd -la"
alias lll "lsd -la"

alias lt "lsd --tree"

alias nv "nvim"
alias nvi "nvim"

if not test -d /tmp/ard_log
    mkdir /tmp/ard_log
end

abbr --add jrnl " jrnl"


fish_add_path $HOME/.local/kitty.app/bin

zoxide init fish | source
