#!/usr/bin/env bash
# Laptop-only system config: lid behaviour and display hotplug.
#
# These are the bits that can't be stow symlinks because they live outside $HOME
# and have to be root-owned. Called by bootstrap.sh on a desktop-profile machine
# that actually has a lid; safe to run directly and safe to re-run.
#
#   ./install/laptop.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

is_laptop || { ok "no lid switch here; skipping laptop display config"; exit 0; }

have autorandr || die "autorandr missing — run bootstrap.sh (or apt install autorandr)"
have acpid     || warn "acpid missing — lid open/close won't retrigger the layout"

# install_root <src> <dest>  — copy only when it differs, and report what it did.
install_root() {
  local src="$1" dest="$2" mode="${3:-0644}"
  if sudo cmp -s "$src" "$dest" 2>/dev/null; then
    ok "$dest (unchanged)"
    return 1
  fi
  sudo install -D -m "$mode" "$src" "$dest"
  ok "$dest"
  return 0
}

changed=0

# ---- 1. lid: suspend on battery, keep running when docked/on AC ------------
if install_root "$HERE/system/systemd/10-dotfiles-lid.conf" \
                /etc/systemd/logind.conf.d/10-dotfiles-lid.conf; then changed=1; fi

# The stock logind.conf may already carry hand-edited Handle* lines; a drop-in
# only wins if the main file leaves them at their defaults.
if grep -qE '^\s*HandleLidSwitch' /etc/systemd/logind.conf 2>/dev/null; then
  warn "/etc/systemd/logind.conf sets HandleLidSwitch* directly — comment those"
  warn "out so the drop-in in logind.conf.d/ takes effect."
fi

# ---- 2. autorandr's boot/hotplug fallback ----------------------------------
if install_root "$HERE/system/systemd/10-dotfiles-default.conf" \
                /etc/systemd/system/autorandr.service.d/10-dotfiles-default.conf; then changed=1; fi

# ---- 3. lid switch -> re-run the layout ------------------------------------
if have acpid; then
  if install_root "$HERE/system/acpi/dotfiles-lid.sh" /etc/acpi/dotfiles-lid.sh 0755; then changed=1; fi
  if install_root "$HERE/system/acpi/dotfiles-lid.events" /etc/acpi/events/dotfiles-lid; then
    changed=1
    sudo systemctl restart acpid
    ok "acpid reloaded"
  fi
fi

if [ "$changed" = 1 ]; then sudo systemctl daemon-reload; fi

echo
ok "laptop display config installed."
cat <<'MSG'

Reload the lid policy without a reboot:
  sudo systemctl restart systemd-logind    # NB: ends the current graphical session

Record a layout once you're happy with it (arandr is a handy GUI for this):
  autorandr --save dock            # lid open, panel + externals
  autorandr --save dock-closed     # same monitors, lid shut, panel off

display-fixup prefers a "<profile>-closed" variant when the lid is down, so the
externals get laid out properly instead of leaving a hole where the panel was.
MSG
