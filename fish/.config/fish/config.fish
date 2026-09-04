if status is-interactive
    # Commands to run in interactive sessions can go here
    starship init fish | source

    # vi mode, and the [N]/[I] indicator that comes with it. Universal, so
    # fish persists it, and only assigned when it's actually wrong -- a blind
    # re-assign on every startup retriggers fish's key-binding reload mid-config
    # and has been seen to break fzf.fish's ctrl-r taking effect.
    #
    # Compare the value rather than using `set -q`: fish's own
    # __fish_config_interactive runs `__init_uvar fish_key_bindings
    # fish_default_key_bindings` before the first prompt, i.e. *after* this file
    # is sourced. On a machine whose fish_variables got wiped, fish therefore
    # claims the variable first, and an existence check stays satisfied forever
    # by the wrong value, silently leaving the shell in emacs mode.
    if test "$fish_key_bindings" != fish_vi_key_bindings
        set -U fish_key_bindings fish_vi_key_bindings
    end
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
