# My Claude Code config

Portable [Claude Code](https://claude.com/claude-code) config — plugins, MCPs,
skills, hooks, rules, and global instructions — that you can install on any
machine. Everything is **opt-in**: you choose what lands in your `~/.claude`.

## Layout

```
settings/
  settings.base.json      portable config: prefs, plugins, marketplaces, self-contained hooks
  settings.personal.json  opt-in: hooks that need private tools + cavemem MCP
home/                     mirrors ~/.claude/ — symlinked in by the installer
  rules/context7.md
  hooks/                  caveman-ultra.txt, context-mode-cache-heal.mjs
install.sh                symlinks components + merges settings.json + deps menu
```

## Install

```bash
git clone <this-repo> ~/repo/claude-config && cd ~/repo/claude-config
./install.sh                 # settings + file components + deps menu
./install.sh --dry-run       # preview, touch nothing (skips the deps menu)
./install.sh settings rules  # only these components
./install.sh deps            # just the dependency-software menu
./install.sh --personal      # also merge the personal-tools fragment (see below)
```

Restart Claude Code afterward. On first launch it will offer to install the
plugins listed in `enabledPlugins`.

## How it works

- **File components** (CLAUDE.md, rules, commands, hooks) are **symlinked** into
  `~/.claude` — edit them in this repo and changes are live everywhere. Any
  pre-existing file at a target is backed up to `*.bak-<timestamp>` first.
- **settings.json is merged, not symlinked** — Claude Code rewrites it at
  runtime (plugin toggles, timestamps), and you may already have one. The
  installer deep-merges: **this repo's values win**, your other keys are kept,
  and the previous file is backed up. Re-running is idempotent.
- Set `CLAUDE_CONFIG_DIR` to target a config dir other than `~/.claude`.

## Choosing what to install (full control)

- **Plugins / marketplaces** — edit `settings/settings.base.json`
  (`enabledPlugins`, `extraKnownMarketplaces`) *before* running. It's a plain
  declarative manifest; delete anything you don't want. `true`/`false` per
  plugin toggles it on/off.
- **File components** — pass only the ones you want as arguments, or `rm` a
  symlink later.
- **Dependency software** — the `deps` step opens an `fzf` multi-select; nothing
  installs unless you tick it. Already-installed tools are marked `✓`.
- **Personal hooks** — off unless you pass `--personal`.

## Dependency software (`deps`)

The `deps` component first prints a **toolchain preflight** — `git`, `node`,
`npm`, `uv`, `cargo`, `fzf` — marking each `✓` present or `✗` missing
with an install link. These packaging managers are **never installed for you**;
you install any missing one yourself, then re-run.

It then opens an `fzf` menu to install the external tools the hooks and skills
rely on. Each tool is installed only if you select it and its toolchain is present:

| Tool | Installs via | Prereq |
|------|--------------|--------|
| `cavemem` | `npm install -g cavemem` | npm |
| `fable` | `uv tool install fable-recall` | uv |
| `flue` | `uv tool install flue` | uv |
| `claudetell` | `git clone …/claudetell.git → $CLAUDETELL_DIR` (asks first) | git |
| `waggle` | `cargo install waggle` | cargo |

`claudetell` ([FoamScience/claudetell](https://github.com/FoamScience/claudetell))
is a local session traffic-light overlay. Because selecting it clones a
third-party repo onto your machine, the menu shows the URL and asks for explicit
`[y/N]` confirmation before cloning.


### Bundled marketplaces

`claude-context-mode`, `superpowers-marketplace`, `plannotator`,
`claude-code-workflows`, `caveman`, `claude-hud`, `diagram-design`,
`claude-paper`, `yoonho-plugins`, `ponytail`, `ai-research-skills`, `ecc`,
`hivemind` (plus the built-in `claude-plugins-official`).

## The `--personal` fragment

`settings/settings.personal.json` holds hooks that call **private tools not in
this repo**. It's excluded by default because it will error on a machine that
lacks them. It assumes:

| Tool | Expected location | Purpose |
|------|-------------------|---------|
| `cavemem` | npm global bin on `PATH` | memory MCP + session hooks |
| `fable` | bin on `PATH` | recall/indexing hooks |
| `claudetell` | `$CLAUDETELL_DIR` or `$HOME/repo/claudetell/claudetell.py` | session traffic-light overlay hooks |

Install these from the `deps` menu, then edit the paths above if yours differ
before using `--personal`. This fragment also re-adds the
`skip*` permission-prompt flags that the base config deliberately leaves out
(see below).
