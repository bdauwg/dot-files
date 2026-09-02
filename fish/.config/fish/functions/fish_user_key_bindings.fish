function fish_user_key_bindings
    # Defining this function at all makes fish re-run fish_vi_key_bindings (or
    # whichever $fish_key_bindings names) right before the first prompt, which
    # wipes every binding set so far — including the ctrl-r/ctrl-t/etc. that
    # conf.d/fzf.fish's fzf_configure_bindings installed during config
    # sourcing. PatrickF1/fzf.fish's own README calls this out: re-call
    # fzf_configure_bindings here to put those bindings back. Guarded, so a
    # machine where the plugin isn't installed yet doesn't error on every prompt.
    functions -q fzf_configure_bindings; and fzf_configure_bindings
end
