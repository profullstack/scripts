#!/usr/bin/env sh
# install.sh — put profullstack/scripts on PATH, at a released version.
#
#   sh install.sh                 # latest release tag
#   sh install.sh --edge          # track main instead
#   sh install.sh --ref v0.2.0    # a specific tag or branch
#   sh install.sh --ssh           # clone over SSH, for a checkout you push from
#   sh install.sh --dry-run       # say what would happen, change nothing
#
# The repo is public, so a fresh box needs no key and no account:
#
#   curl -fsSL https://raw.githubusercontent.com/profullstack/scripts/main/install.sh | sh
#
# That is the whole install. Cloning over HTTPS also ends the chicken-and-egg
# this file used to carry: provision-ssh-keys lives in this repo, so getting it
# onto a new machine used to need the very key it exists to install.
#
# Use --ssh (or SCRIPTS_REPO) for a checkout you intend to push from. An HTTPS
# clone reads fine and upgrades fine; it is just not set up to write.
#
# POSIX sh on purpose. This is the one file that runs before anything is
# installed, possibly on a box whose only shell is dash, so it may not assume
# bash the way the tools in bin/ do.
#
# THE GATE RUNS TWICE, ON PURPOSE. bin/scripts-check is the rule. This script
# points core.hooksPath at .githooks so it runs before every push, and
# .github/workflows/release.yml runs that same file on the runner.
#
# CI is back because the repo is public. An unpaid balance on the org suspends
# Actions compute on PRIVATE repos -- not this repo's minutes, which are free;
# storage and Code Quality credits elsewhere -- and while this repo was private
# the job was refused before it ever started. The balance is still owed; public
# repos are simply not subject to it.
#
# WHY A TAG BY DEFAULT. Because `~/.local/bin/*` are symlinks into the working
# tree, the command on PATH is whatever the checkout happens to be at. Tracking
# main means a half-finished edit made at a prompt is instantly the installed
# tool on that box. Pinning to the newest release makes an upgrade a decision.
# The development box is the exception, and it takes care of itself: an
# existing checkout with local commits or uncommitted work is never moved.

set -eu

# HTTPS by default: the repo is public, so this works with no key, no account
# and no prior setup, which is the whole point of the curl one-liner above.
# SSH stays a flag away for the boxes that push.
REPO_HTTPS="https://github.com/profullstack/scripts.git"
REPO_SSH="git@github.com:profullstack/scripts.git"
REPO="${SCRIPTS_REPO:-$REPO_HTTPS}"
DIR="${SCRIPTS_DIR:-$HOME/scripts}"
BINDIR="${SCRIPTS_BIN:-$HOME/.local/bin}"
REF="${SCRIPTS_REF:-}"
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --edge)     REF=main ;;
    --ssh)      REPO="$REPO_SSH" ;;
    --https)    REPO="$REPO_HTTPS" ;;
    --ref)      REF="${2:?--ref needs a tag or branch}"; shift ;;
    --ref=*)    REF="${1#--ref=}" ;;
    --dir)      DIR="${2:?--dir needs a path}"; shift ;;
    --bin)      BINDIR="${2:?--bin needs a path}"; shift ;;
    --dry-run|-n) DRY=1 ;;
    -h|--help)  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "install.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

say()  { echo "$@"; }
run()  { if [ "$DRY" = 1 ]; then echo "  would: $*"; else "$@"; fi; }
die()  { echo "install.sh: $*" >&2; exit 1; }

# The newest v-tag on the remote, by version sort. Read from the remote rather
# than a local tag list so a stale checkout cannot report an old "latest".
latest_tag() {
  git ls-remote --tags --refs "$REPO" 'v*' 2>/dev/null \
    | awk '{print $2}' | sed 's#refs/tags/##' \
    | sort -V | tail -1
}

# ---------------------------------------------------------------- fetch

if [ ! -d "$DIR/.git" ]; then
  [ -e "$DIR" ] && die "$DIR exists but is not a git checkout; move it aside"
  if [ -z "$REF" ]; then REF="$(latest_tag)"; [ -n "$REF" ] || REF=main; fi
  say "cloning $REPO -> $DIR at $REF"
  run git clone --quiet "$REPO" "$DIR"
  [ "$DRY" = 1 ] || git -C "$DIR" -c advice.detachedHead=false checkout --quiet "$REF"
else
  say "checkout exists at $DIR"

  # Refuse to move a tree someone is working in. On the development box this
  # is the normal state, and silently detaching it onto a tag would strand
  # unpushed work in a way that only surfaces later.
  dirty=$(git -C "$DIR" status --porcelain 2>/dev/null | head -1)
  branch=$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
  ahead=0
  if [ "$branch" != HEAD ] && git -C "$DIR" rev-parse --verify --quiet "@{u}" >/dev/null 2>&1; then
    ahead=$(git -C "$DIR" rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
  fi

  if [ -n "$dirty" ] || [ "$ahead" != 0 ]; then
    say "  leaving the tree alone: $( [ -n "$dirty" ] && echo 'uncommitted changes' || echo "$ahead unpushed commit(s)" )"
    say "  (symlinks below still refresh, so a new tool in bin/ lands on PATH)"
  else
    run git -C "$DIR" fetch --quiet --tags origin
    if [ -z "$REF" ]; then REF="$(latest_tag)"; [ -n "$REF" ] || REF=main; fi
    say "  moving to $REF"
    if [ "$REF" = main ]; then
      run git -C "$DIR" checkout --quiet main
      run git -C "$DIR" merge --quiet --ff-only origin/main
    else
      run git -C "$DIR" -c advice.detachedHead=false checkout --quiet "$REF"
    fi
  fi
fi

# ---------------------------------------------------------------- hooks

# The release gate is a pre-push hook rather than CI. Hooks are not carried by
# a clone, so every checkout has to be pointed at the tracked directory; it is
# a local config setting, which is why it is done here and not once in the repo.
if [ "$DRY" = 1 ]; then
  echo "  would: git -C $DIR config core.hooksPath .githooks"
elif [ -d "$DIR/.githooks" ]; then
  git -C "$DIR" config core.hooksPath .githooks
  say "  pre-push gate enabled (scripts-check)"
fi

# ---------------------------------------------------------------- link

run mkdir -p "$BINDIR"
linked=0; skipped=0
for f in "$DIR"/bin/*; do
  [ -f "$f" ] && [ -x "$f" ] || continue
  name=$(basename "$f")
  target="$BINDIR/$name"
  # Replace our own symlink freely; never overwrite a real file someone else
  # put there. A silent clobber of another tool of the same name is the kind
  # of thing found weeks later.
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    say "  skip $name (a real file, not our symlink)"
    skipped=$((skipped + 1))
    continue
  fi
  run ln -sfn "$f" "$target"
  linked=$((linked + 1))
done
say "linked $linked tool(s) into $BINDIR${skipped:+, skipped $skipped}"

# ---------------------------------------------------------------- report

case ":${PATH}:" in
  *":$BINDIR:"*) ;;
  *) say ""
     say "NOTE: $BINDIR is not on PATH. Add it:"
     say "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshenv" ;;
esac

if [ "$DRY" = 0 ]; then
  at=$(git -C "$DIR" describe --tags --always 2>/dev/null || echo unknown)
  say ""
  say "installed at $at — \`scripts-upgrade\` to move to the next release"
fi
