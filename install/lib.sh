# shellcheck shell=bash
# Shared helpers for the dotfiles bootstrap. Source, don't execute.

# ---- output ----------------------------------------------------------------
if [ -t 1 ]; then
  _c_reset=$'\e[0m'; _c_blue=$'\e[34m'; _c_green=$'\e[32m'; _c_yellow=$'\e[33m'; _c_red=$'\e[31m'
else
  _c_reset=; _c_blue=; _c_green=; _c_yellow=; _c_red=
fi
info()  { printf '%s==>%s %s\n' "$_c_blue"   "$_c_reset" "$*"; }
ok()    { printf '%s ok%s %s\n'  "$_c_green"  "$_c_reset" "$*"; }
warn()  { printf '%swarn%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
err()   { printf '%serr%s %s\n'  "$_c_red"    "$_c_reset" "$*" >&2; }
die()   { err "$*"; exit 1; }

# ---- environment detection -------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

is_wsl() {
  # WSL exposes "microsoft" in the kernel version / osrelease.
  grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null
}

# Laptops need lid handling and display hotplug on top of the desktop profile.
# The lid button is the thing we actually care about, so test for it directly
# rather than trusting the DMI chassis type.
is_laptop() { [ -d /proc/acpi/button/lid ]; }

# PROFILE: "desktop" (has X/i3), "wsl", or "headless" (a server / work box with
# no GUI). Override with DOTFILES_PROFILE or --profile.
detect_profile() {
  if [ -n "${DOTFILES_PROFILE:-}" ]; then
    printf '%s' "$DOTFILES_PROFILE"; return
  fi
  if is_wsl; then printf 'wsl'; return; fi
  # A remote session with no display is a server: don't drag in i3 and rofi.
  # Deliberately narrow — a fresh desktop bootstrapped from a TTY has no DISPLAY
  # either, so SSH is the signal, not the missing display on its own.
  if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    printf 'headless'; return
  fi
  printf 'desktop'
}

# ---- privilege -------------------------------------------------------------
# Root-owned installs are optional. Where a tool can land in $HOME instead, it
# does; where it genuinely can't (apt), we skip and say so rather than failing.
# DOTFILES_NO_SUDO=1 forces the unprivileged path even on a box that has sudo.
can_sudo() {
  [ -n "${DOTFILES_NO_SUDO:-}" ] && return 1
  [ "$(id -u)" = 0 ] && return 0
  # Deliberately does NOT test whether sudo would succeed. `sudo -n true` fails
  # on any normal machine that simply wants a password, and calling that "no
  # sudo" would skip apt on exactly the boxes that have it. So: optimistic here,
  # and every caller treats a failed privileged command as a skip rather than an
  # error. Force the unprivileged path with DOTFILES_NO_SUDO=1.
  have sudo
}

# Everything that isn't a distro package installs under here.
PREFIX="${DOTFILES_PREFIX:-$HOME/.local}"

ubuntu_codename() { . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-unknown}"; }

# ---- apt -------------------------------------------------------------------
APT_UPDATED=0
apt_update_once() {
  [ "$APT_UPDATED" = 1 ] && return 0
  info "apt update"
  if sudo apt-get update -qq; then APT_UPDATED=1; return 0; fi
  return 1
}

# Packages apt could not supply this run. Callers report on it; the cargo/go
# lists in tools.sh cover most of them, so this is information, not an error.
APT_SKIPPED=()

# apt_install_missing <pkg>...   — only touches apt for packages not present.
# Never fatal: with no apt or no sudo it records what was wanted and returns 0,
# so bootstrap still reaches the stow step instead of dying with nothing linked.
apt_install_missing() {
  local want=() p
  if ! have apt-get || ! have dpkg; then
    APT_SKIPPED+=("$@")
    warn "no apt here; skipping: $*"
    return 0
  fi
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || want+=("$p")
  done
  [ ${#want[@]} -eq 0 ] && { ok "apt: nothing to install"; return 0; }
  if ! can_sudo; then
    APT_SKIPPED+=("${want[@]}")
    warn "no sudo; skipping apt install: ${want[*]}"
    return 0
  fi
  apt_update_once || warn "apt update failed; trying the install anyway"
  info "apt install: ${want[*]}"
  if sudo apt-get install -y -qq "${want[@]}"; then return 0; fi
  # A declined password prompt or a user with no rights lands here. Record and
  # carry on: losing apt must not cost the run its stow step.
  APT_SKIPPED+=("${want[@]}")
  warn "apt install failed; skipping: ${want[*]}"
  return 0
}

# read a package-list file (ignore blank lines and # comments) into stdout
read_pkglist() { sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$1"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
