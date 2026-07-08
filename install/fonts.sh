#!/usr/bin/env bash
# Install the Nerd Fonts used by the terminal / starship / nvim.
# Downloads per-family zips from the ryanoasis/nerd-fonts release (the fonts
# themselves are ~80MB, too heavy to track in git). Idempotent.
#
# On WSL this installs the fonts on the Linux side (useful for WSLg GUI apps),
# but the Windows Terminal font must be set on the Windows side separately.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Nerd Fonts release asset names (the .zip base name in the release).
FAMILIES=(CodeNewRoman Inconsolata Go-Mono Tinos)

FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# a family counts as installed if any of its Nerd Font files are present.
# Capture fc-list first: `fc-list | grep -q` lets grep close the pipe on the
# first match, so fc-list dies with SIGPIPE and pipefail makes this always
# report "not present". A here-string avoids that.
family_present() {
  local fonts; fonts="$(fc-list 2>/dev/null)" || true
  grep -qi "$1.*Nerd Font" <<<"$fonts"
}

# latest nerd-fonts release tag. Fetch fully into a var, then grep from a
# here-string: piping curl into `grep -m1` closes the pipe early and kills curl
# with a write error (exit 23) / SIGPIPE under pipefail. A here-string has no
# upstream process to signal, so grep's early exit is harmless.
github_tag() {
  local json
  json="$(curl -fsSL "https://api.github.com/repos/$1/releases/latest")" || return 1
  grep -m1 '"tag_name"' <<<"$json" | cut -d'"' -f4
}

install_family() {
  local fam="$1" tag="$2" name
  name="${fam//-/}"            # "Go-Mono" -> "GoMono" for the fc-list check
  if family_present "$name"; then ok "font present: $fam"; return; fi
  info "installing Nerd Font: $fam"
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${tag}/${fam}.zip" \
       -o "$tmp/$fam.zip"; then
    unzip -qo "$tmp/$fam.zip" -d "$FONT_DIR/$fam" -x '*.md' 'LICENSE*' '*.txt'
    ok "font: $fam ($tag)"
  else
    warn "could not download $fam.zip — check the family name in fonts.sh"
  fi
  rm -rf "$tmp"
}

main() {
  have unzip || apt_install_missing unzip fontconfig
  # Skip the API call entirely if every family is already installed.
  local need=0 fam
  for fam in "${FAMILIES[@]}"; do family_present "${fam//-/}" || need=1; done
  if [ "$need" = 0 ]; then ok "all Nerd Fonts present"; return; fi
  local tag; tag="$(github_tag ryanoasis/nerd-fonts)" || die "could not fetch nerd-fonts release tag"
  for fam in "${FAMILIES[@]}"; do install_family "$fam" "$tag"; done
  info "rebuilding font cache"
  fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
  ok "fonts done"
}
main "$@"
