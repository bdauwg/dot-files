# dotfiles

Personal config for Ubuntu (desktop with i3) and Ubuntu on WSL, deployed with
[GNU Stow](https://www.gnu.org/software/stow/). One command sets up a fresh box.

## Quick start (fresh machine)

```sh
sudo apt-get update && sudo apt-get install -y git
git clone <this-repo-url> ~/git/dotfiles
cd ~/git/dotfiles
./bootstrap.sh
```

`bootstrap.sh` auto-detects whether it's on a **desktop** (installs i3 & GUI
tools) or **WSL** (skips all GUI packages), then:

1. installs apt packages (`install/packages-apt*.txt`),
2. installs non-apt tools with prebuilt binaries (`install/tools.sh`),
3. symlinks configs into `$HOME` with stow,
4. sets `fish` as the login shell.

It is **idempotent** — safe to run again after pulling updates.

### Options

```sh
./bootstrap.sh --profile wsl     # force WSL profile (no GUI)
./bootstrap.sh --profile desktop # force desktop profile
./bootstrap.sh --link-only       # just refresh symlinks
./bootstrap.sh --no-tools        # skip binary installs
./bootstrap.sh --no-chsh         # keep current login shell
./bootstrap.sh --help
```

## Layout

Each top-level dir is a stow "package" mirroring `$HOME`:

| Package     | Links to                    | Profile  |
|-------------|-----------------------------|----------|
| `fish/`     | `~/.config/fish/`           | all      |
| `nvim/`     | `~/.config/nvim/`           | all      |
| `tmux/`     | `~/.tmux.conf`              | all      |
| `starship/` | `~/.config/starship.toml`   | all      |
| `sesh/`     | `~/.config/sesh/`           | all      |
| `jrnl/`     | `~/.config/jrnl/`           | all      |
| `git/`      | `~/.gitconfig`, `~/.config/git/ignore` | all |
| `jj/`       | `~/.config/jj/config.toml`  | all      |
| `i3/`       | `~/.config/i3/`             | desktop  |
| `i3status/` | `~/.config/i3status/`       | desktop  |
| `display/`  | `~/.config/autorandr/`, `~/.local/bin/display-*` | desktop |

`install/` holds the bootstrap machinery and is never stowed.

On a machine with a lid, the desktop profile additionally runs
`install/laptop.sh`, which drops root-owned files (lid policy, the acpid hook)
into `/etc` — see [Docking and monitors](#docking-and-monitors).

## Docking and monitors

The `display/` package handles plugging into a dock, including with the lid
shut. Two commands, both in `~/.local/bin`:

| Command | What it does |
|---------|--------------|
| `display-apply [--force]` | match a saved layout against what's plugged in, then fix it up |
| `display-fixup [--dry-run]` | just the rules: lid, `primary`, wallpaper, i3 |

`display-apply` is the single entry point — i3 startup, the drm hotplug rule,
the acpid lid event and `$mod+F7` all call it. `--dry-run` on `display-fixup`
prints what it would change without touching anything, which is the fastest way
to debug a dock that comes up wrong.

### Saving a layout

Layouts are [autorandr](https://github.com/phillipberndt/autorandr) profiles,
matched by the EDIDs of the connected monitors:

```sh
arandr                      # arrange it by hand (or just use xrandr)
autorandr --save dock       # remember this arrangement
autorandr                   # list profiles; the live one is marked (detected)
```

If nothing matches, `display-apply` falls back to autorandr's built-in
`horizontal` layout rather than leaving the new monitor dark.

### Why there's a lid workaround

autorandr already knows to treat a closed lid as an unplugged display — but only
for outputs *named* `eDP*` or `LVDS*` (`is_closed_lid()` in `/usr/bin/autorandr`).
Under the NVIDIA driver the ThinkPad's internal panel is called **`DP-4`**, so
that check never fires: dock with the lid shut and the panel stays lit behind a
closed screen, holding a workspace nobody can see.

`display-fixup` does the check itself. It finds the panel by comparing xrandr's
EDIDs against the kernel's real `eDP` connector under `/sys/class/drm`, so it
keeps working if the output gets renumbered. Override it if the guess is wrong:

```sh
echo DP-4 > ~/.config/display/internal-output
```

Because the EDIDs don't change when the lid moves, autorandr can't tell
lid-open from lid-closed and will match the same profile for both. So:

- by default, the panel is simply switched off while the lid is down;
- if a profile named `<profile>-closed` exists, that gets loaded instead — save
  one when you want the externals repositioned rather than left with a gap
  where the panel used to be:

  ```sh
  autorandr --save dock          # lid open
  # shut the lid, arrange the externals, then:
  autorandr --save dock-closed
  ```

### Suspend on lid close

`install/laptop.sh` installs `/etc/systemd/logind.conf.d/10-dotfiles-lid.conf`:
suspend on battery, **ignore** the lid on external power or docked. The
external-power rule is what keeps the machine awake at the GDM greeter, so a
docked boot with the lid shut reaches the login screen instead of suspending.

It also overrides `autorandr.service` to fall back to `horizontal` instead of a
profile named `default`, which doesn't exist and errors on every hotplug.

If `/etc/systemd/logind.conf` still sets `HandleLidSwitch*` directly, comment
those lines out — the main file beats the drop-in. The script warns when it
spots this.

### Stowing over an existing ~/.config/autorandr

autorandr writes into that directory itself, so a machine with saved profiles
will collide on first stow. Let stow pull them into the repo:

```sh
stow --restow --adopt --target="$HOME" --no-folding display
git diff        # confirm nothing unexpected moved
```

New profiles saved later land as real directories inside the stowed one; copy
them into `display/.config/autorandr/` to track them.

## Day-to-day

Because configs are **symlinks back into this repo**, editing e.g.
`~/.config/nvim/init.lua` edits the repo file directly. Commit as usual (this
repo is jj-colocated, so `jj` or plain `git` both work):

```sh
cd ~/git/dotfiles
jj st          # or: git status
```

Add a new config:

```sh
mkdir -p newtool/.config/newtool
cp ~/.config/newtool/config newtool/.config/newtool/config
stow --target="$HOME" --no-folding newtool
```

## Migrating a machine that already has these configs

On a box where the real files already exist (not symlinks yet), let stow pull
them into the repo instead of erroring on conflict:

```sh
stow --adopt --target="$HOME" --no-folding fish nvim tmux starship sesh jrnl git jj
git diff        # review what --adopt changed, revert anything unwanted
```

`--adopt` moves the existing file into the repo and replaces it with a symlink.

## Caveats / not tracked here

- **jrnl** journals live in `~/Documents/note/*.md` and the paths in
  `jrnl.yaml` are absolute (`/home/bramos/...`). If your username differs on a
  new machine, edit `~/.config/jrnl/jrnl.yaml` after linking.
- **i3 wallpaper** `~/Pictures/uw-background.jpg` is not tracked — drop one in.
- **monitor layouts** in `display/.config/autorandr/` are tied to specific
  monitors' EDIDs; they're useless on another machine, but harmless (they just
  never match).
- **conda** block in `config.fish` is guarded; it's a no-op until you install
  miniconda. Toolchains (rust/go/node/conda) are intentionally not installed by
  bootstrap — add them per-machine as needed.
- **kitty** and **spicetify** (desktop) install to `~/.local/` via their own
  installers, invoked by `install/tools.sh --desktop`.

## What gets installed

- **apt (all):** fish, tmux, ripgrep, fd-find, bat, fzf, zoxide, jq, stow, git,
  build-essential, python3/pipx.
- **apt (desktop):** i3, i3status, i3lock, xss-lock, dex, rofi, dmenu, feh,
  flameshot, autorandr, arandr, acpid, network-manager-gnome, blueman,
  brightnessctl, pulseaudio-utils.
- **binaries (all):** neovim (latest stable), starship, jj, sesh, lazygit, lsd,
  jrnl, plus `fd`/`bat` shims for Ubuntu's `fdfind`/`batcat`.
- **binaries (desktop):** kitty, spicetify, and Nerd Fonts (CodeNewRoman,
  Inconsolata, Go-Mono, Tinos) via `install/fonts.sh`.

### Fonts on WSL

`install/fonts.sh` installs the Nerd Fonts on the **Linux** side (for WSLg GUI
apps). If you run WSL inside Windows Terminal, also install a Nerd Font on the
**Windows** side and set it as the terminal font — the Linux-side fonts don't
apply to the Windows-rendered console.
