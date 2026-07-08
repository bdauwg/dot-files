#!/usr/bin/env bash
# Install the tools that don't come from apt (or whose apt version is too old).
# Idempotent: every installer skips if the tool is already present.
# Prebuilt binaries are preferred so a fresh machine needs no Rust/Go toolchain.
#
#   ./install/tools.sh            # install the common CLI tools
#   ./install/tools.sh --desktop  # also install kitty + spicetify (GUI)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ARCH="$(uname -m)"                       # x86_64 | aarch64
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# github_tag OWNER/REPO -> latest release tag (e.g. v1.2.3)
# Fetch fully into a var, then grep from a here-string. Piping curl straight into
# `grep -m1` makes grep close the pipe early — curl (or printf) then dies with a
# write error / SIGPIPE, which pipefail turns fatal. A here-string has no upstream
# process to signal, so the early exit is harmless.
github_tag() {
  local json
  json="$(curl -fsSL "https://api.github.com/repos/$1/releases/latest")" || return 1
  grep -m1 '"tag_name"' <<<"$json" | cut -d'"' -f4
}

# ---------------------------------------------------------------------------
install_neovim() {
  have nvim && { ok "neovim present ($(nvim --version | head -1))"; return; }
  info "installing neovim (latest stable)"
  local base="https://github.com/neovim/neovim/releases/latest/download"
  local asset tmp; tmp="$(mktemp -d)"
  case "$ARCH" in
    x86_64)  asset="nvim-linux-x86_64.tar.gz" ;;
    aarch64) asset="nvim-linux-arm64.tar.gz" ;;
    *) warn "no neovim binary for $ARCH; install manually"; return ;;
  esac
  # asset names changed across versions; fall back to the older name.
  curl -fsSL "$base/$asset" -o "$tmp/nvim.tgz" \
    || curl -fsSL "$base/nvim-linux64.tar.gz" -o "$tmp/nvim.tgz"
  sudo rm -rf /opt/nvim
  sudo mkdir -p /opt/nvim
  sudo tar -xzf "$tmp/nvim.tgz" -C /opt/nvim --strip-components=1
  sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -rf "$tmp"; ok "neovim -> /usr/local/bin/nvim"
}

install_starship() {
  have starship && { ok "starship present"; return; }
  info "installing starship"
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes >/dev/null
  ok "starship"
}

install_jj() {
  have jj && { ok "jj present"; return; }
  info "installing jujutsu (jj)"
  local tag; tag="$(github_tag jj-vcs/jj)"
  local triple; case "$ARCH" in
    x86_64)  triple="x86_64-unknown-linux-musl" ;;
    aarch64) triple="aarch64-unknown-linux-musl" ;;
    *) warn "no jj binary for $ARCH"; return ;;
  esac
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/jj-vcs/jj/releases/download/${tag}/jj-${tag}-${triple}.tar.gz" \
    -o "$tmp/jj.tgz"
  tar -xzf "$tmp/jj.tgz" -C "$tmp"
  install -m755 "$tmp/jj" "$LOCAL_BIN/jj"
  rm -rf "$tmp"; ok "jj -> $LOCAL_BIN/jj"
}

install_sesh() {
  have sesh && { ok "sesh present"; return; }
  info "installing sesh"
  local tag ver; tag="$(github_tag joshmedeski/sesh)"; ver="${tag#v}"
  local arch; case "$ARCH" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) warn "no sesh binary for $ARCH"; return ;;
  esac
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/joshmedeski/sesh/releases/download/${tag}/sesh_Linux_${arch}.tar.gz" \
    -o "$tmp/sesh.tgz"
  tar -xzf "$tmp/sesh.tgz" -C "$tmp"
  install -m755 "$tmp/sesh" "$LOCAL_BIN/sesh"
  rm -rf "$tmp"; ok "sesh -> $LOCAL_BIN/sesh"
}

install_lazygit() {
  have lazygit && { ok "lazygit present"; return; }
  info "installing lazygit"
  local tag ver; tag="$(github_tag jesseduffield/lazygit)"; ver="${tag#v}"
  local arch; case "$ARCH" in
    x86_64)  arch="x86_64" ;;
    aarch64) arch="arm64" ;;
    *) warn "no lazygit binary for $ARCH"; return ;;
  esac
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_Linux_${arch}.tar.gz" \
    -o "$tmp/lg.tgz"
  tar -xzf "$tmp/lg.tgz" -C "$tmp" lazygit
  install -m755 "$tmp/lazygit" "$LOCAL_BIN/lazygit"
  rm -rf "$tmp"; ok "lazygit -> $LOCAL_BIN/lazygit"
}

install_lsd() {
  have lsd && { ok "lsd present"; return; }
  # lsd is in apt on 24.04 (universe); use it if available, else GitHub .deb.
  if apt-cache show lsd >/dev/null 2>&1; then
    apt_install_missing lsd; return
  fi
  info "installing lsd (.deb from GitHub)"
  local tag ver; tag="$(github_tag lsd-rs/lsd)"; ver="${tag#v}"
  local arch; case "$ARCH" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) warn "no lsd binary for $ARCH"; return ;;
  esac
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/lsd-rs/lsd/releases/download/${tag}/lsd_${ver}_${arch}.deb" \
    -o "$tmp/lsd.deb"
  sudo dpkg -i "$tmp/lsd.deb" || sudo apt-get -f install -y
  rm -rf "$tmp"; ok "lsd"
}

install_jrnl() {
  have jrnl && { ok "jrnl present"; return; }
  info "installing jrnl (pipx)"
  have pipx || die "pipx missing — run the apt step first"
  pipx install jrnl >/dev/null
  ok "jrnl"
}

# fd/bat ship on Ubuntu as fdfind/batcat; add friendly `fd`/`bat` shims.
install_shims() {
  if have fdfind && ! have fd; then
    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"; ok "fd -> fdfind shim"
  fi
  if have batcat && ! have bat; then
    ln -sf "$(command -v batcat)" "$LOCAL_BIN/bat"; ok "bat -> batcat shim"
  fi
}

# ---- desktop-only ----------------------------------------------------------
install_kitty() {
  have kitty && { ok "kitty present"; return; }
  info "installing kitty"
  curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
  # kitty installs to ~/.local/kitty.app; expose launcher + terminfo
  ln -sf "$HOME/.local/kitty.app/bin/kitty" "$LOCAL_BIN/kitty"
  ln -sf "$HOME/.local/kitty.app/bin/kitten" "$LOCAL_BIN/kitten"
  ok "kitty"
}

install_spicetify() {
  have spicetify && { ok "spicetify present"; return; }
  info "installing spicetify"
  curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh
  ok "spicetify"
}

# ---------------------------------------------------------------------------
main() {
  local desktop=0
  [ "${1:-}" = "--desktop" ] && desktop=1

  install_neovim
  install_starship
  install_jj
  install_sesh
  install_lazygit
  install_lsd
  install_jrnl
  install_shims

  if [ "$desktop" = 1 ]; then
    install_kitty
    install_spicetify
    "$(dirname "${BASH_SOURCE[0]}")/fonts.sh"   # Nerd Fonts for the GUI terminal
  fi

  ok "tools done. Ensure $LOCAL_BIN is on PATH (the fish config adds it)."
}
main "$@"
