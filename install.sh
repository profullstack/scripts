#!/usr/bin/env sh
# install.sh — put profullstack/scripts on PATH, at a released version.
#
#   sh install.sh                 # latest release tag
#   sh install.sh --edge          # track main instead
#   sh install.sh --ref v0.2.0    # a specific tag or branch
#   sh install.sh --dry-run       # say what would happen, change nothing
#
# The repo is private, so there is no anonymous curl one-liner: this clones
# over SSH and relies on the key that is already on the box. On a fresh
# machine that means provisioning a key first — bin/provision-ssh-keys is the
# tool for that, which is a chicken-and-egg only the very first time.
#
#   ssh -T git@github.com          # must not say "Permission denied"
#   git clone git@github.com:profullstack/scripts.git ~/scripts
#   sh ~/scripts/install.sh
#
# POSIX sh on purpose. This is the one file that runs before anything is
# installed, possibly on a box whose only shell is dash, so it may not assume
# bash the way the tools in bin/ do.
#
# There is no CI. The gate that used to be a GitHub Actions workflow is now
# bin/scripts-check, run by .githooks/pre-push, because this repo is private
# under a free-plan org and every workflow minute was billed -- and in the end
# refused for billing before the job started. This script wires the hook up.
#
# WHY A TAG BY DEFAULT. Because `~/.local/bin/*` are symlinks into the working
# tree, the command on PATH is whatever the checkout happens to be at. Tracking
# main means a half-finished edit made at a prompt is instantly the installed
# tool on that box. Pinning to the newest release makes an upgrade a decision.
# The development box is the exception, and it takes care of itself: an
# existing checkout with local commits or uncommitted work is never moved.

set -eu

REPO_SSH="git@github.com:profullstack/scripts.git"
DIR="${SCRIPTS_DIR:-$HOME/scripts}"
BINDIR="${SCRIPTS_BIN:-$HOME/.local/bin}"
REF="${SCRIPTS_REF:-}"
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --edge)     REF=main ;;
    --ref)      REF="${2:?--ref needs a tag or branch}"; shift ;;
    --ref=*)    REF="${1#--ref=}" ;;
    --dir)      DIR="${2:?--dir needs a path}"; shift ;;
    --bin)      BINDIR="${2:?--bin needs a path}"; shift ;;
    --dry-run|-n) DRY=1 ;;
    -h|--help)  sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  git ls-remote --tags --refs "$REPO_SSH" 'v*' 2>/dev/null \
    | awk '{print $2}' | sed 's#refs/tags/##' \
    | sort -V | tail -1
}

# ---------------------------------------------------------------- fetch

if [ ! -d "$DIR/.git" ]; then
  [ -e "$DIR" ] && die "$DIR exists but is not a git checkout; move it aside"
  if [ -z "$REF" ]; then REF="$(latest_tag)"; [ -n "$REF" ] || REF=main; fi
  say "cloning $REPO_SSH -> $DIR at $REF"
  run git clone --quiet "$REPO_SSH" "$DIR"
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
