#!/usr/bin/env bash
# Install the tools that don't come from apt (or whose apt version is too old).
# Idempotent: every installer skips if the tool is already present.
# Prebuilt binaries are preferred so a fresh machine needs no Rust/Go toolchain.
#
#   ./install/tools.sh            # install the common CLI tools
#   ./install/tools.sh --desktop  # also install kitty + Nerd Fonts (GUI)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ARCH="$(uname -m)"                       # x86_64 | aarch64
LOCAL_BIN="$PREFIX/bin"                  # PREFIX comes from lib.sh (~/.local)
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
  # Check our own managed copy, not `have nvim` — a stray system nvim (an old
  # apt package, or one baked into the base image) satisfies `have` without
  # ever being upgraded, which left this step skipping itself on machines
  # that already had a too-old /usr/bin/nvim.
  [ -x "$LOCAL_BIN/nvim" ] && { ok "neovim present ($("$LOCAL_BIN/nvim" --version | head -1))"; return; }
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
  # The tarball is relocatable, so unpack it under $PREFIX rather than /opt —
  # that's the whole difference between needing root here and not.
  rm -rf "$PREFIX/nvim"; mkdir -p "$PREFIX/nvim"
  tar -xzf "$tmp/nvim.tgz" -C "$PREFIX/nvim" --strip-components=1
  ln -sf "$PREFIX/nvim/bin/nvim" "$LOCAL_BIN/nvim"
  rm -rf "$tmp"; ok "neovim -> $LOCAL_BIN/nvim"
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
  # $PREFIX/golang, not $PREFIX/go: go infers GOROOT from the binary's own path
  # so the name is free, and "go" would collide with GOPATH if PREFIX is $HOME.
  local dest="$PREFIX/golang"
  rm -rf "$dest"; mkdir -p "$dest"
  tar -C "$dest" --strip-components=1 -xzf "$tmp/go.tgz"
  rm -rf "$tmp"
  export PATH="$dest/bin:$PATH"
  ok "go ($ver) -> $dest"
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

install_jrnl() {
  have jrnl && { ok "jrnl present"; return; }
  info "installing jrnl (pipx)"
  have pipx || die "pipx missing — run the apt step first"
  pipx install jrnl >/dev/null
  ok "jrnl"
}

# Give tools their upstream names when the distro renamed them, or when the
# only available build is a compatible reimplementation. Runs twice in main():
# before the package lists, so an apt-provided fdfind counts as `fd` and cargo
# doesn't rebuild it from source; and after, to catch gojq.
install_shims() {
  if have fdfind && ! have fd; then
    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"; ok "fd -> fdfind shim"
  fi
  if have batcat && ! have bat; then
    ln -sf "$(command -v batcat)" "$LOCAL_BIN/bat"; ok "bat -> batcat shim"
  fi
  # gojq is the no-apt route to jq. Near-drop-in, not identical — it differs on
  # some edge cases — so it only ever fills in for a jq that isn't there.
  if have gojq && ! have jq; then
    ln -sf "$(command -v gojq)" "$LOCAL_BIN/jq"; ok "jq -> gojq shim"
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
  run_step install_jrnl
  run_step install_shims          # before: apt's fdfind/batcat satisfy fd/bat
  run_step install_cargo_packages
  run_step install_go_packages
  run_step install_shims          # after: pick up gojq

  if [ "$desktop" = 1 ]; then
    run_step install_kitty
    run_step install_fonts
  fi

  if [ ${#FAILED[@]} -gt 0 ]; then
    warn "finished with failures: ${FAILED[*]}"
    warn "re-run ./install/tools.sh once the cause is fixed; everything is idempotent."
  fi
  ok "tools done. Ensure $LOCAL_BIN is on PATH (the fish config adds it)."
}
main "$@"
