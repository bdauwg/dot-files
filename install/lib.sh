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

# PROFILE: "wsl" (headless) or "desktop" (has X/i3). Override with DOTFILES_PROFILE.
detect_profile() {
  if [ -n "${DOTFILES_PROFILE:-}" ]; then
    printf '%s' "$DOTFILES_PROFILE"; return
  fi
  if is_wsl; then printf 'wsl'; else printf 'desktop'; fi
}

ubuntu_codename() { . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-unknown}"; }

# ---- apt -------------------------------------------------------------------
APT_UPDATED=0
apt_update_once() {
  [ "$APT_UPDATED" = 1 ] && return 0
  info "apt update"; sudo apt-get update -qq && APT_UPDATED=1
}

# apt_install_missing <pkg>...   — only touches apt for packages not present.
apt_install_missing() {
  local want=() p
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || want+=("$p")
  done
  [ ${#want[@]} -eq 0 ] && { ok "apt: nothing to install"; return 0; }
  apt_update_once
  info "apt install: ${want[*]}"
  sudo apt-get install -y -qq "${want[@]}"
}

# read a package-list file (ignore blank lines and # comments) into stdout
read_pkglist() { sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$1"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
