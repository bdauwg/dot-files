#!/usr/bin/env bash
# Bootstrap these dotfiles on a fresh Ubuntu machine (desktop or WSL).
#
#   ./bootstrap.sh                 # auto-detect profile, do everything
#   ./bootstrap.sh --profile wsl   # force WSL profile (no GUI packages)
#   ./bootstrap.sh --profile headless   # server / work box: no GUI packages
#   ./bootstrap.sh --no-tools      # skip non-apt tool installs
#   ./bootstrap.sh --no-chsh       # don't change the login shell to fish
#   ./bootstrap.sh --link-only     # only (re)create the stow symlinks
#
# On a laptop the desktop profile also installs lid/dock display handling
# (install/laptop.sh) — see the `display` package.
#
# Safe to re-run: apt installs skip present packages, tool installers skip
# present binaries, and `stow --restow` just refreshes symlinks.
#
# Runs without root. Anything apt would have supplied is reported and skipped
# (DOTFILES_NO_SUDO=1 forces this path); the cargo and go lists in
# install/tools.sh cover most of it. See "Machines without sudo" in the README.
set -euo pipefail
cd "$(dirname "$0")"
source install/lib.sh

# ---- args ------------------------------------------------------------------
PROFILE="$(detect_profile)"
DO_APT=1; DO_TOOLS=1; DO_LINK=1; DO_CHSH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --profile=*) PROFILE="${1#*=}"; shift ;;
    --no-apt)   DO_APT=0; shift ;;
    --no-tools) DO_TOOLS=0; shift ;;
    --no-chsh)  DO_CHSH=0; shift ;;
    --link-only) DO_APT=0; DO_TOOLS=0; DO_CHSH=0; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
case "$PROFILE" in desktop|wsl|headless) ;;
  *) die "profile must be 'desktop', 'wsl' or 'headless'";; esac
can_sudo || info "no sudo: apt steps will be skipped, tools go under $PREFIX"

info "profile: $PROFILE   ($(. /etc/os-release; echo "$PRETTY_NAME"))"

# stow packages that apply everywhere, and the desktop-only extras.
COMMON_PKGS=(fish nvim tmux starship sesh jrnl git jj)
DESKTOP_PKGS=(i3 i3status display)

# ---- 1. apt packages -------------------------------------------------------
if [ "$DO_APT" = 1 ]; then
  info "installing common apt packages"
  # shellcheck disable=SC2046
  apt_install_missing $(read_pkglist install/packages-apt.txt)
  if [ "$PROFILE" = desktop ]; then
    info "installing desktop apt packages"
    # shellcheck disable=SC2046
    apt_install_missing $(read_pkglist install/packages-apt-desktop.txt)
  fi
  # apt_install_missing never fails the run — losing apt must not cost you the
  # stow step, which is the part that actually needs to happen everywhere.
  if [ ${#APT_SKIPPED[@]} -gt 0 ]; then
    warn "apt supplied none of: ${APT_SKIPPED[*]}"
    warn "the cargo/go lists cover most of these; fish and tmux they do not."
  fi
fi

# ---- 2. non-apt tools ------------------------------------------------------
if [ "$DO_TOOLS" = 1 ]; then
  if [ "$PROFILE" = desktop ]; then
    ./install/tools.sh --desktop
  else
    ./install/tools.sh
  fi
fi

# ---- 3. link configs with stow --------------------------------------------
if [ "$DO_LINK" = 1 ]; then
  have stow || apt_install_missing stow
  have stow || die "stow is required to link the configs and could not be installed"
  local_pkgs=("${COMMON_PKGS[@]}")
  [ "$PROFILE" = desktop ] && local_pkgs+=("${DESKTOP_PKGS[@]}")
  info "linking: ${local_pkgs[*]}"
  BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

  # stow aborts the *entire* package the moment one real file is in its way, and
  # on any machine that has already run fish/nvim/tmux once, that's guaranteed —
  # which is how you end up with a fresh box where nothing got linked. So: read
  # the paths out of stow's complaint, move them into a timestamped backup, and
  # retry. The repo wins; nothing is deleted.
  stow_pkg() {
    local pkg="$1" out conflicts f n
    # --restow clears stale links first; --no-folding keeps real dirs where apps
    # write their own state (nvim plugins, autorandr profiles) instead of a symlink.
    if out="$(stow --restow --target="$HOME" --no-folding "$pkg" 2>&1)"; then
      ok "stow $pkg"; return 0
    fi
    conflicts="$(printf '%s\n' "$out" | sed -n \
      -e 's/^ *\* existing target is neither a link nor a directory: //p' \
      -e 's/^ *\* existing target is not owned by stow: //p' | sort -u)"
    if [ -z "$conflicts" ]; then
      err "stow $pkg failed:"; printf '%s\n' "$out" >&2; return 1
    fi
    n=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      mkdir -p "$BACKUP_DIR/$(dirname "$f")"
      mv "$HOME/$f" "$BACKUP_DIR/$f"
      n=$((n + 1))
    done <<<"$conflicts"
    if out="$(stow --restow --target="$HOME" --no-folding "$pkg" 2>&1)"; then
      ok "stow $pkg ($n pre-existing file(s) moved to $BACKUP_DIR)"
    else
      err "stow $pkg still failing after backup:"; printf '%s\n' "$out" >&2; return 1
    fi
  }

  link_failed=0
  for pkg in "${local_pkgs[@]}"; do
    stow_pkg "$pkg" || link_failed=1
  done
  [ -d "${BACKUP_DIR:-}" ] && warn "pre-existing configs backed up in $BACKUP_DIR"
  [ "$link_failed" = 1 ] && warn "some packages did not link — see the errors above"
fi

# ---- 3b. laptop-only system config -----------------------------------------
# Lid policy, the autorandr hotplug fallback and the acpid lid hook live outside
# $HOME and must be root-owned, so stow can't place them. Runs after linking
# because the acpid hook calls ~/.local/bin/display-apply.
if [ "$DO_LINK" = 1 ] && [ "$PROFILE" = desktop ] && is_laptop; then
  ./install/laptop.sh
fi

# ---- 4. default shell ------------------------------------------------------
if [ "$DO_CHSH" = 1 ]; then
  fish_path="$(command -v fish || true)"
  if [ -z "$fish_path" ]; then
    warn "fish not found; skipping chsh"
  elif [ "${SHELL:-}" = "$fish_path" ]; then
    ok "login shell already fish"
  else
    # chsh refuses a shell that isn't in /etc/shells, and only root can put it
    # there — so on an unprivileged box this step is simply not available.
    if ! grep -qx "$fish_path" /etc/shells 2>/dev/null; then
      if can_sudo && echo "$fish_path" | sudo tee -a /etc/shells >/dev/null; then
        ok "$fish_path added to /etc/shells"
      else
        warn "cannot add $fish_path to /etc/shells; leaving the login shell alone."
        warn "exec fish from your login shell's rc instead — see the README."
        DO_CHSH=0
      fi
    fi
    if [ "$DO_CHSH" = 1 ]; then
      if chsh -s "$fish_path"; then
        ok "login shell -> fish (re-login to take effect)"
      else
        warn "chsh failed; set manually: chsh -s $fish_path"
      fi
    fi
  fi
fi

echo
ok "bootstrap complete."
cat <<EOF

Next steps:
  - Restart your shell (or re-login) to pick up fish.
  - Open nvim once; lazy.nvim will sync plugins on first launch.
  - jrnl: journals point at ~/Documents/note/*.md — create that dir or edit
    ~/.config/jrnl/jrnl.yaml (paths there are absolute; see README caveats).
EOF
[ "$PROFILE" = desktop ] && echo "  - i3: set your wallpaper at ~/Pictures/uw-background.jpg (not tracked)."
exit 0
