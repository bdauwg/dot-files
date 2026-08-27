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

# ---- toolchains ------------------------------------------------------------
# Installed on demand: only when a package list actually needs them, so a box
# that just wants the prebuilt binaries never pays for a compiler.

install_rust() {
  have cargo && { ok "cargo present ($(cargo --version | awk '{print $2}'))"; return; }
  info "installing rust (rustup, minimal profile)"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal >/dev/null
  export PATH="$HOME/.cargo/bin:$PATH"
  ok "rust -> $HOME/.cargo/bin"
}

install_golang() {
  have go && { ok "go present ($(go version | awk '{print $3}'))"; return; }
  info "installing go"
  local goarch; case "$ARCH" in
    x86_64)  goarch="amd64" ;;
    aarch64) goarch="arm64" ;;
    *) warn "no go binary for $ARCH"; return 1 ;;
  esac
  # go.dev/VERSION is the canonical "what is current" endpoint; first line only.
  local ver; ver="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
  [ -n "$ver" ] || { warn "could not determine the current go version"; return 1; }
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "https://go.dev/dl/${ver}.linux-${goarch}.tar.gz" -o "$tmp/go.tgz"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$tmp/go.tgz"
  rm -rf "$tmp"
  export PATH="/usr/local/go/bin:$PATH"
  ok "go ($ver) -> /usr/local/go"
}

# ---- package lists ---------------------------------------------------------
# Both lists use  spec[:binary]  — the binary name is the "is it already here?"
# check, so nothing gets rebuilt just because the crate and command differ.
# split_spec sets $SPEC and $BIN.
split_spec() {
  SPEC="${1%%:*}"
  BIN="${1#*:}"
  # No colon in the spec means the parameter expansion returned it unchanged.
  # NB: explicit return — a bare `[ ... ] && BIN=...` leaves the function's exit
  # status at the failed test, which set -e turns into an abort at the call site.
  if [ "$BIN" = "$1" ]; then BIN="$SPEC"; fi
  return 0
}

install_cargo_packages() {
  local list="$DOTFILES_DIR/install/packages-cargo.txt"
  [ -f "$list" ] || return 0
  # Work out what's actually missing before dragging in a Rust toolchain.
  local entry todo=()
  while read -r entry; do
    split_spec "$entry"
    have "$BIN" && { ok "cargo: $SPEC present"; continue; }
    todo+=("$entry")
  done < <(read_pkglist "$list")
  [ ${#todo[@]} -eq 0 ] && return 0

  install_rust
  have cargo || { warn "cargo unavailable; skipping: ${todo[*]}"; return 1; }
  local rc=0
  for entry in "${todo[@]}"; do
    split_spec "$entry"
    info "cargo install $SPEC (builds from source, this can take several minutes)"
    if cargo install --locked "$SPEC"; then ok "$BIN"; else warn "cargo install $SPEC failed"; rc=1; fi
  done
  return $rc
}

install_go_packages() {
  local list="$DOTFILES_DIR/install/packages-go.txt"
  [ -f "$list" ] || return 0
  local entry todo=()
  while read -r entry; do
    split_spec "$entry"
    have "$BIN" && { ok "go: $BIN present"; continue; }
    todo+=("$entry")
  done < <(read_pkglist "$list")
  [ ${#todo[@]} -eq 0 ] && return 0

  install_golang
  have go || { warn "go unavailable; skipping: ${todo[*]}"; return 1; }
  local rc=0
  for entry in "${todo[@]}"; do
    split_spec "$entry"
    info "go install $SPEC"
    # GOBIN keeps these with every other tool here instead of ~/go/bin.
    if GOBIN="$LOCAL_BIN" GOTOOLCHAIN="${GOTOOLCHAIN:-auto}" go install "$SPEC"; then
      ok "$BIN -> $LOCAL_BIN/$BIN"
    else
      warn "go install $SPEC failed"; rc=1
    fi
  done
  return $rc
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

install_fonts() { "$DOTFILES_DIR/install/fonts.sh"; }   # Nerd Fonts for the GUI terminal

# ---------------------------------------------------------------------------
# Run one installer in a subshell that keeps its own errexit, so a dead download
# aborts *that* tool and nothing else. Without this a single 404 (sesh's renamed
# release asset, for one) killed tools.sh, which killed bootstrap.sh — before it
# ever got to the stow step, leaving a machine with neither tools nor configs.
FAILED=()
run_step() {
  local fn="$1" rc=0
  set +e; ( set -e; "$fn" ); rc=$?; set -e
  if [ $rc -ne 0 ]; then
    warn "${fn#install_} failed (exit $rc) — continuing"
    FAILED+=("${fn#install_}")
  fi
  return 0
}

main() {
  local desktop=0
  [ "${1:-}" = "--desktop" ] && desktop=1

  run_step install_neovim
  run_step install_starship
  run_step install_jj
  run_step install_lazygit
  run_step install_lsd
  run_step install_jrnl
  run_step install_cargo_packages
  run_step install_go_packages
  run_step install_shims

  if [ "$desktop" = 1 ]; then
    run_step install_kitty
    run_step install_spicetify
    run_step install_fonts
  fi

  if [ ${#FAILED[@]} -gt 0 ]; then
    warn "finished with failures: ${FAILED[*]}"
    warn "re-run ./install/tools.sh once the cause is fixed; everything is idempotent."
  fi
  ok "tools done. Ensure $LOCAL_BIN is on PATH (the fish config adds it)."
}
main "$@"
