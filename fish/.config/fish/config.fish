if status is-interactive
    # Commands to run in interactive sessions can go here
    starship init fish | source

    # vi mode, and the [N]/[I] indicator that comes with it. Set once, as
    # universal (persisted by fish itself), not re-set on every startup: a
    # plain `set -g` here re-assigns fish_key_bindings fresh on every single
    # session, mid-config-sourcing, which retriggers fish's key-binding
    # reload at a point in the startup sequence that isn't equivalent to a
    # pre-existing persisted value — confirmed to break fzf.fish's ctrl-r
    # (and friends) taking effect, even though `bind` reports them correctly.
    set -q fish_key_bindings; or set -U fish_key_bindings fish_vi_key_bindings
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
