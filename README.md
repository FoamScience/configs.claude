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
  installer merges **non-destructively**: it adds what's missing, unions hook
  arrays without duplicating, and **keeps your existing values on any conflict**
  (your model, your disabled plugins, your own hooks all survive). The previous
  file is backed up, and re-running is idempotent (no duplicate growth).
- Set `CLAUDE_CONFIG_DIR` to target a config dir other than `~/.claude`.

## Choosing what to install

- **Plugins / marketplaces** — edit `settings/settings.base.json`
  (`enabledPlugins`, `extraKnownMarketplaces`) *before* running. It's a plain
  declarative manifest; delete anything you don't want. `true`/`false` per
  plugin toggles it on/off.
- **File components** — pass only the ones you want as arguments, or `rm` a
  symlink later.
- **Dependency software** — the `deps` step opens an `fzf` multi-select; nothing
  installs unless you tick it. Already-installed tools are marked `✓` and skipped
  (an existence check precedes every install).
- **Personal skip-flags** — off unless you pass `--personal`.

## Dependency software (`deps`)

The `deps` component first prints a **toolchain preflight** — `git`, `node`,
`npm`, `uv`, `cargo`, `fzf` — marking each `✓` present or `✗` missing
with an install link. These packaging managers are **never installed for you**;
you install any missing one yourself, then re-run.

It then opens an `fzf` menu to install the external tools the hooks and skills
rely on. Each is installed the way **its own README suggests** (no `apt`/system
package managers; `uv tool` for Python, the tool's own script otherwise), and
only if you select it, its toolchain is present, and it isn't already installed
(each install is preceded by an existence check):

| Tool | Installs via | Prereq |
|------|--------------|--------|
| `cavemem` | `npm install -g cavemem && cavemem install` | npm |
| `fable` | `uv tool install fable-recall && fable install` | uv |
| `caveman` | `curl -fsSL …/caveman/main/install.sh \| bash` (asks first) | node |
| `flue` | `uv tool install flue` | uv |
| `claudetell` | clone + its own installer (asks first) | git, uv |
| `waggle` | `cargo install waggle-cli` | cargo |
| `styleseed` | `npx skills add bitjaru/styleseed` (asks first) | npx (node) |
| `fablize` | its own `setup/setup.sh` (asks first) | fablize plugin installed |

`cavemem`, `fable`, and `claudetell` each **register their own hooks + MCP** into
`settings.json` via their installer (`cavemem install`, `fable install`,
`uv run claudetell.py install`) with machine-correct paths — so this repo ships
**no** tool hooks in the `--personal` fragment.

`claudetell` ([FoamScience/claudetell](https://github.com/FoamScience/claudetell))
is a local session traffic-light overlay. Selecting it asks for `[y/N]`
confirmation, then **presents an fzf picker of destinations** (or type your own
path); it **clones** the repo there — or **`git pull`s** it if that directory
already exists — and runs `uv run claudetell.py install`. **claudetell
registers its own hooks** in `settings.json` (with machine-correct paths); this
repo does **not** ship claudetell hooks in the `--personal` fragment.

`styleseed` ([bitjaru/styleseed](https://github.com/bitjaru/styleseed)) is the
StyleSeed UI design gate — a set of skills that flag "looks AI-generated" UI and
enforce a quality score. Installed the original way, via its own `skills` CLI:
`npx skills add bitjaru/styleseed` (consent-gated, since it writes skills + rules
files into your agent config). After install, run `/ss-setup` in Claude Code.

`caveman` ([JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)) is
the caveman-speak skill (fewer output tokens, code kept byte-exact). Installed
its original way, the curl one-liner (consent-gated): `curl -fsSL
https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash`.
It's also available as the bundled `caveman@caveman` marketplace plugin.

`fablize` ([fivetaku/fablize](https://github.com/fivetaku/fablize)) is an
always-on operating harness (evidence gates, investigation protocol, per-task
routing). The plugin is enabled in `settings.base.json`; to turn on **global
mode**, pick `fablize` in the deps menu and answer `g` at its prompt — its
`setup.sh` injects the operating block into your global `~/.claude/CLAUDE.md`
(backing it up first) and records `~/.fablize/progress.json`.


### Bundled marketplaces

`claude-context-mode`, `superpowers-marketplace`, `plannotator`,
`claude-code-workflows`, `caveman`, `claude-hud`, `diagram-design`,
`claude-paper`, `yoonho-plugins`, `ponytail`, `ai-research-skills`, `ecc`,
`hivemind`, `fablize` (plus the built-in `claude-plugins-official`).

## The `--personal` fragment

`settings/settings.personal.json` now holds **only** the `skip*` permission-prompt
flags that the base config deliberately leaves out (`skipDangerousModePermissionPrompt`,
`skipWorkflowUsageWarning`, `skipAutoPermissionPrompt`) — see below. It ships **no
tool hooks or MCP servers**: cavemem, fable, and claudetell each register their
own from the `deps` menu, so there are no hardcoded machine paths to break.
