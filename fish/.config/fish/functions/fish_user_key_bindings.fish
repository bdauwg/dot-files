function fish_user_key_bindings
    # PatrickF1/fzf.fish installs its own bindings from conf.d; this is the
    # older junegunn-style hook. Guarded, so a machine where the plugin isn't
    # installed yet doesn't throw an error on every single prompt.
    functions -q fzf_key_bindings; and fzf_key_bindings
end
