#!/usr/bin/env bash
# Install this Claude Code config into ~/.claude (or $CLAUDE_CONFIG_DIR).
# File components are symlinked (edits stay live in the repo).
# settings.json is merged (Claude Code rewrites it at runtime, so it can't be a symlink).
# `deps` opens an fzf multi-select to install the external tools the hooks need.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP="$(date +%s)"

PERSONAL=0
DRY=0
COMPONENTS=()

# --- pretty output (ANSI only; disabled when not a TTY or NO_COLOR is set) ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _B=$'\e[1m' _D=$'\e[2m' _R=$'\e[0m'
  _G=$'\e[32m' _Y=$'\e[33m' _E=$'\e[31m' _C=$'\e[36m' _U=$'\e[34m'
else
  _B='' _D='' _R='' _G='' _Y='' _E='' _C='' _U=''
fi
head() { printf '\n%s%s❯ %s%s\n' "$_B" "$_C" "$*" "$_R"; }
step() { printf '  %s▸%s %s\n' "$_U" "$_R" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$_G" "$_R" "$*"; }
warn() { printf '  %s!%s %s\n' "$_Y" "$_R" "$*"; }
err()  { printf '  %s✗%s %s\n' "$_E" "$_R" "$*"; }
info() { printf '  %s·%s %s\n' "$_D" "$_R" "$_D$*$_R"; }

usage() {
  cat <<EOF
Usage: ./install.sh [--personal] [--dry-run] [components...]

Components (default: all):
  settings   merge settings/settings.base.json into \$CLAUDE_DIR/settings.json
  rules      symlink rules/*
  hooks      symlink hooks/*
  deps       report packaging toolchains (uv, cargo, npm, ... — links only,
             never installed for you), then an fzf multi-select to install
             the external tools (cavemem, fable, waggle, ...)

Flags:
  --personal  also merge settings/settings.personal.json (private-tool hooks +
              cavemem MCP). Requires the tools from the deps menu.
  --dry-run   print actions without touching the filesystem (skips the deps menu).
  --help      show this.

Plugin control: edit settings/settings.base.json (enabledPlugins /
extraKnownMarketplaces) BEFORE running to choose what gets installed.
EOF
}

for arg in "$@"; do
  case "$arg" in
  --personal) PERSONAL=1 ;;
  --dry-run) DRY=1 ;;
  --help | -h)
    usage
    exit 0
    ;;
  --*)
    err "unknown flag: $arg" >&2
    usage
    exit 1
    ;;
  *) COMPONENTS+=("$arg") ;;
  esac
done
[ ${#COMPONENTS[@]} -eq 0 ] && COMPONENTS=(settings rules hooks deps)

has() {
  for c in "${COMPONENTS[@]}"; do [ "$c" = "$1" ] && return 0; done
  return 1
}
run() { if [ "$DRY" = 1 ]; then echo "DRY  $*"; else eval "$@"; fi; }

link() { # link <repo-relative-src> <abs-dest>
  local src="$REPO/$1" dest="$2"
  [ -e "$src" ] || {
    echo "skip (missing): $1"
    return
  }
  run "mkdir -p \"$(dirname "$dest")\""
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "ok   $dest"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "back $dest -> $dest.bak-$STAMP"
    run "mv \"$dest\" \"$dest.bak-$STAMP\""
  fi
  run "ln -s \"$src\" \"$dest\""
  echo "link $dest"
}

merge_settings() {
  local dest="$CLAUDE_DIR/settings.json"
  local base="$REPO/settings/settings.base.json"
  local personal=""
  [ "$PERSONAL" = 1 ] && personal="$REPO/settings/settings.personal.json"
  [ -f "$dest" ] && {
    info "backup ${dest/#$HOME/\~} -> …bak-$STAMP"
    run "cp \"$dest\" \"$dest.bak-$STAMP\""
  }
  run "mkdir -p \"$CLAUDE_DIR\""
  if [ "$DRY" = 1 ]; then
    printf '  %sdry%s merge base%s into %s\n' "$_D" "$_R" "${personal:+ + personal}" "${dest/#$HOME/\~}"
    return
  fi
  if python3 - "$dest" "$base" "$personal" <<'PY'
import json, sys, os
dest, base, personal = sys.argv[1], sys.argv[2], sys.argv[3]

def load(p):
    if p and os.path.isfile(p):
        with open(p) as f: return json.load(f)
    return {}

def strip(v):  # recursively drop _comment keys
    if isinstance(v, dict):
        return {k: strip(x) for k, x in v.items() if not k.startswith("_")}
    if isinstance(v, list):
        return [strip(x) for x in v]
    return v

def merge(a, b, keep_scalar):
    # dicts: recurse, adding keys present only in b.
    # lists: union — append b's items that a doesn't already have (no duplicates).
    # scalars: keep_scalar True keeps a (the existing value); else b wins.
    if isinstance(a, dict) and isinstance(b, dict):
        out = dict(a)
        for k, v in b.items():
            if k.startswith("_"):
                continue
            out[k] = merge(out[k], v, keep_scalar) if k in out else strip(v)
        return out
    if isinstance(a, list) and isinstance(b, list):
        out = list(a)
        for item in b:
            si = strip(item)
            if si not in out:
                out.append(si)
        return out
    return a if keep_scalar else strip(b)

ours = load(base)
if personal:
    ours = merge(ours, load(personal), keep_scalar=False)  # personal wins; hooks unioned
existing = load(dest)
# non-destructive: keep your existing values, add what's missing, union hooks, no dupes
final = merge(existing, ours, keep_scalar=True)
with open(dest, "w") as f:
    json.dump(final, f, indent=2); f.write("\n")
PY
  then ok "settings.json merged${personal:+ (base + personal)}"
  else err "settings.json merge failed"; fi
}

# --- dependency software (external tools the hooks / skills need) ---
CLAUDETELL_DIR="${CLAUDETELL_DIR:-$HOME/repo/claudetell}"

install_claudetell() { # present a destination, clone (or pull if present), then let claudetell register its OWN hooks
  local dir
  dir=$(printf '%s\n' "$CLAUDETELL_DIR" "$HOME/repo/claudetell" "$HOME/projects/claudetell" \
    "$HOME/src/claudetell" "$HOME/code/claudetell" "$PWD/claudetell" |
    awk 'NF && !seen[$0]++' |
    fzf --print-query --prompt='clone claudetell to> ' \
      --header='pick a destination or type a path, ENTER to confirm' | tail -1)
  [ -z "$dir" ] && {
    warn "claudetell: no destination chosen"
    return 1
  }
  dir="${dir/#\~/$HOME}"
  if [ -d "$dir/.git" ]; then
    step "claudetell: updating existing clone in ${dir/#$HOME/\~}"
    git -C "$dir" pull --ff-only || return 1
  elif [ -e "$dir" ]; then
    err "claudetell: ${dir/#$HOME/\~} exists but is not a git clone — aborting"
    return 1
  else
    step "claudetell: cloning into ${dir/#$HOME/\~}"
    git clone https://github.com/FoamScience/claudetell.git "$dir" || return 1
  fi
  (cd "$dir" && uv run claudetell.py install)
}

# Records are ~-delimited: key~label~check~prereq~install  (checks may contain pipes)
DEPS=(
  "cavemem~cavemem (caveman memory MCP + hooks)~command -v cavemem~command -v npm~npm install -g cavemem"
  "fable~fable-recall (recall/indexing hooks)~command -v fable~command -v uv~uv tool install fable-recall"
  "flue~flue (desktop-app scripting bridge skill)~command -v flue~command -v uv~uv tool install flue"
  "claudetell~claudetell (session traffic-light overlay)~test -f '$CLAUDETELL_DIR/claudetell.py'~command -v git && command -v uv~install_claudetell~presents destinations to pick (or type a path), clones FoamScience/claudetell there (or git pull if already present), then runs its own installer (uv run claudetell.py install) which registers claudetell's hooks in settings.json"
  "waggle~waggle~command -v waggle~command -v cargo~cargo install waggle-cli"
)

# Packaging toolchains the deps rely on. We never install these — only report
# what's missing and where to get it. Records: name~check~install-url
TOOLCHAINS=(
  "git~command -v git~https://git-scm.com/downloads"
  "node~command -v node~https://github.com/nvm-sh/nvm (nvm), then: nvm install --lts"
  "npm~command -v npm~ships with Node.js — https://nodejs.org"
  "uv~command -v uv~https://docs.astral.sh/uv/getting-started/installation/"
  "cargo~command -v cargo~https://rustup.rs"
  "fzf~command -v fzf~https://github.com/junegunn/fzf#installation (needed for the deps menu)"
)

check_toolchains() {
  echo "toolchains (install any missing one yourself — links below):"
  local rec name check url miss=0
  for rec in "${TOOLCHAINS[@]}"; do
    IFS='~' read -r name check url <<<"$rec"
    if eval "$check" >/dev/null 2>&1; then
      printf '  ✓ %-7s\n' "$name"
    else
      printf '  ✗ %-7s → %s\n' "$name" "$url"
      miss=1
    fi
  done
  [ "$miss" = 1 ] && echo "  (install the ✗ ones above, then re-run — nothing is installed for you here)"
  echo
}

deps_menu() {
  if [ "$DRY" = 1 ]; then
    echo "DRY  skip deps menu (interactive)"
    return
  fi
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "deps: skipped (no TTY). Run ./install.sh deps interactively."
    return
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    echo "deps: fzf not found (the menu needs it). Install fzf first:"
    echo "        apt install fzf   |   brew install fzf   |   https://github.com/junegunn/fzf"
    return
  fi

  # build menu lines: "key<TAB>label<TAB>[installed|available]"
  local lines="" rec key label check
  for rec in "${DEPS[@]}"; do
    IFS='~' read -r key label check _ _ <<<"$rec"
    if eval "$check" >/dev/null 2>&1; then
      lines+="$key\t$label\t✓ installed\n"
    else lines+="$key\t$label\t· available\n"; fi
  done

  local picks
  picks=$(printf "%b" "$lines" | fzf --multi --with-nth=2,3 --delimiter='\t' \
    --header=$'TAB to select multiple, ENTER to confirm, ESC to skip\ninstall external tools:' \
    --prompt='deps> ' | cut -f1) || true
  [ -z "$picks" ] && {
    info "deps: nothing selected"
    return
  }

  local p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    for rec in "${DEPS[@]}"; do
      IFS='~' read -r key label check prereq install consent <<<"$rec"
      [ "$key" = "$p" ] || continue
      if ! eval "$prereq" >/dev/null 2>&1; then
        warn "$key skipped: prereq missing ($prereq)"
        break
      fi
      if [ -n "$consent" ]; then
        printf '\n  %s%s%s %s\n  proceed? [y/N] ' "$_B" "$key" "$_R" "$consent"
        read -r ans </dev/tty || ans=""
        case "$ans" in [Yy]*) ;; *)
          warn "$key declined"
          break
          ;;
        esac
      fi
      step "installing $key"
      if eval "$install"; then ok "$key installed"; else err "$key failed"; fi
      break
    done
  done <<<"$picks"
}

SUFFIX=""
[ "$PERSONAL" = 1 ] && SUFFIX=" +personal"
[ "$DRY" = 1 ] && SUFFIX="$SUFFIX (dry-run)"
printf '\n%s%s  Claude Code config installer  %s\n' "$_B" "$_C" "$_R"
info "repo    ${REPO/#$HOME/\~}"
info "target  ${CLAUDE_DIR/#$HOME/\~}"
info "steps   ${COMPONENTS[*]}$SUFFIX"

has settings && {
  head "settings"
  merge_settings
}
has rules && {
  head "rules"
  for f in "$REPO"/home/rules/*; do link "home/rules/$(basename "$f")" "$CLAUDE_DIR/rules/$(basename "$f")"; done
}
has hooks && {
  head "hooks"
  for f in "$REPO"/home/hooks/*; do link "home/hooks/$(basename "$f")" "$CLAUDE_DIR/hooks/$(basename "$f")"; done
}
has deps && {
  check_toolchains
  head "dependency tools"
  deps_menu
}

head "done"
ok "restart Claude Code so it picks up settings + plugins"
[ "$PERSONAL" = 0 ] && info "personal hooks not installed — re-run with --personal once deps are in place"
