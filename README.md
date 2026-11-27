# dotfiles

The terminal side of my setup, the same on macOS and Linux: kitty, zsh, tmux, nvim and Claude Code.
Every colour comes from one image or one hex colour. The Linux desktop lives in
[linux-dotfiles](https://github.com/m-queszel/linux-dotfiles), which installs this repo too.

| | |
|---|---|
| Terminal | kitty, zsh with autosuggestions and syntax highlighting, starship, animated pixel prompt, title screen |
| tmux | Riso status strip, window-switch glitch, lava lamp, Claude cockpit (which agent needs you, per pane) |
| Editor | nvim (lazy.nvim) |
| Claude Code | shared settings, rules, status line, tmux hooks |

## Install

macOS (needs [Homebrew](https://brew.sh) and Rust's `cargo`, which builds matugen):

```bash
git clone https://github.com/m-queszel/dotfiles.git ~/dotfiles
~/dotfiles/install   # brew packages, matugen, zsh as login shell, links, Claude setup, default colours
```

Linux: clone to `~/dotfiles`, then run `install.sh` from linux-dotfiles. It installs the packages and calls `./install` here.

`install` is safe to re-run. A file of yours that is in the way is renamed to `<name>.bak-<time>`, never overwritten.

## Commands

| Command | Does |
|---|---|
| `theme <image>` or `theme '#b86b4f'` | recolours kitty, tmux and the prompt (`--light` for a light scheme). On the Linux desktop use `wallpaper` instead |
| `t` | pick a project, open or create its worktree session: Claude on the left, a shell on the right |
| prefix `a` / `u` | pick an agent pane / jump to the next one that needs you |
| `claude-setup` | rebuild `~/.claude/settings.json` from `claude/settings.shared.json` plus this machine's `~/.claude/settings.private.json` |

## Layout

Each top-level directory is one package, linked file by file with GNU Stow by `./link`:
`kitty/kitty.conf` → `~/.config/kitty/kitty.conf`. The exceptions are `home/` → `~` (`dot-` becomes `.`),
`bin/` → `~/.local/bin` and `claude/` → `~/.claude`. `tests/` and `fish/` are not linked.

```bash
./link kitty            # relink after adding a file
./link --check          # what isn't linked yet
./link --unlink kitty   # remove the links
```

Colours: `matugen/terminal.toml` renders `matugen/templates/*` into each app's config. Generated files are
not tracked; add a template instead of hardcoding a colour. `kitty/macos.conf` holds the macOS-only kitty settings.

Scripts must run on macOS's bash 3.2 and BSD tools as well as on Linux.

## Development

`.githooks/pre-commit` runs the link check, the privacy check, shellcheck, `zsh -n` and a Python compile.

```bash
tests/cockpit-test.sh         # tmux cockpit, on a scratch tmux server
tests/claude-config-test.sh   # Claude setup and the linker, in a temp home
```
