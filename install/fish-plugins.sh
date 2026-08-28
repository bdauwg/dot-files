#!/usr/bin/env bash
# Install fisher and sync the plugins listed in ~/.config/fish/fish_plugins.
#
# The plugins are where fzf.fish, nvm.fish and bass come from — several dozen
# functions and completions that are theirs to generate, not ours to track. So
# the repo carries the *list* and this script reproduces the files from it.
#
# Must run AFTER stow has linked the fish package: fisher reads fish_plugins
# out of $HOME, not out of the repo.
#
#   ./install/fish-plugins.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

have fish || { warn "fish not installed; skipping fish plugins"; exit 0; }
PLUGINS="$HOME/.config/fish/fish_plugins"
[ -f "$PLUGINS" ] || { warn "no $PLUGINS — run the stow step first"; exit 0; }

if ! fish -c 'functions -q fisher' 2>/dev/null; then
  info "installing fisher"
  fish -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
           and fisher install jorgebucaran/fisher' >/dev/null
fi

# `fisher update` installs everything in the list and removes anything that
# isn't — the list is the source of truth, which is the point of tracking it.
info "syncing fish plugins: $(tr '\n' ' ' < "$PLUGINS")"
fish -c 'fisher update'
ok "fish plugins synced"
