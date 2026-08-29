# scripts

Hand-written command-line tools. Everything in `bin/` is meant to sit on `PATH`.

## Install

```sh
git clone git@github.com:profullstack/scripts.git ~/scripts
sh ~/scripts/install.sh
```

The repo is private, so there is no anonymous `curl | sh`: the clone needs a key
GitHub already knows. On a brand-new box that has to come first, which is the one
chicken-and-egg here, since `provision-ssh-keys` is itself in this repo.

`install.sh` clones (or updates) the checkout, moves it to the newest release
tag, and symlinks every executable in `bin/` into `~/.local/bin`. Symlinking
rather than copying keeps `~/.local/bin` and this repo from drifting apart.

```sh
sh install.sh                 # newest release
sh install.sh --edge          # track main instead
sh install.sh --ref v0.2.0    # a specific tag
sh install.sh --dry-run       # say what would happen, change nothing
```

## Upgrading

```sh
scripts-upgrade               # move to the newest release
scripts-upgrade --status      # where this box is, and what is newest
scripts-upgrade --edge        # switch to tracking main
```

`scripts-upgrade` is a front for the same `install.sh`, so a fresh machine and
an existing one run identical code.

**Releases are the point of the tag, not a tarball.** Nothing downloads an
archive from this repo; `install.sh` resolves the newest `v*` tag on the remote
and checks the tree out at it. Cutting a release is therefore exactly:

```sh
git tag -a v0.2.0 -m "..." && git push origin v0.2.0
```

The gate runs before the push, not after it. `.githooks/pre-push` runs
`scripts-check`, which parses every script by shebang, verifies the executable
bits, and runs `shellcheck -S error` over the shell ones. Then publish the
release object:

```sh
gh release create v0.2.0 --title "v0.2.0 — ..." --notes-file notes.md
```

**There is no CI, on purpose.** This was a GitHub Actions workflow until
2026-08-29, when the job was refused for billing before it ever ran —
`profullstack` is on the free plan and this repo is private, so every workflow
minute was chargeable. It failed as a red X with no logs, which reads exactly
like a broken workflow and is not one; a gate that does not run is worse than no
gate, because the X implies something was checked. Nothing here needs a hosted
runner anyway: no build, no matrix, no secret, just three loops over files that
are already on disk.

**A development checkout is left alone.** Because `~/.local/bin/*` are symlinks
into the working tree, the command on PATH is whatever the checkout is at, so
tracking `main` means an unfinished edit is instantly the installed tool. That
is why the default is a tag. The box where this repo is actually developed is
the exception and needs no flag: a tree with uncommitted changes or unpushed
commits is never moved, only re-symlinked.

## Tools

### `gh-prs`

Lists open pull requests across any number of organizations and personal
accounts, newest first, as an aligned table. In a capable terminal the PR number
and URL become clickable hyperlinks.

```sh
gh-prs --orgs profullstack,moshcoder,h4kr,infernetprotocol
gh-prs --users ralyodio
gh-prs --orgs profullstack --users ralyodio --limit 50
```

### `gh-prs-merge`

Walks the same scopes and squash-merges every PR that qualifies, oldest first.
**Dry run by default** — nothing changes until you pass `--apply`.

```sh
gh-prs-merge --orgs profullstack,moshcoder          # report only
gh-prs-merge --orgs profullstack,moshcoder --apply  # actually merge
```

A PR is merged only when all of these hold:

- it is open
- it is not a draft, or was successfully marked ready (see below)
- `mergeable` is `MERGEABLE` and `mergeStateStatus` is `CLEAN`
- at least one CI check exists, unless `--allow-no-checks` is passed
- every check is `pass` or `skipping`
- the head commit has not moved between the check and the merge, enforced with
  `--match-head-commit`

Merges never pass `--admin`, so branch protection and required reviews are still
enforced by GitHub. If a merge is refused, that refusal stands.

**Drafts.** Draft PRs are included by default. Under `--apply` each one is marked
ready for review, re-read, and then judged by the rules above — so a draft with
red CI ends up ready but unmerged, which is usually what you want. A dry run
reports them as `WOULD-READY` and changes nothing. Pass `--no-ready-drafts` to
ignore drafts entirely.

Options:

| Flag | Effect |
| --- | --- |
| `--orgs A,B` | search repositories owned by these organizations |
| `--users A,B` | search repositories owned by these personal accounts |
| `--limit N` | maximum PRs per owner, default 1000 |
| `--apply` | actually mark drafts ready and squash-merge |
| `--allow-no-checks` | also merge clean PRs that have no CI checks at all |
| `--no-ready-drafts` | leave draft PRs alone |

The closing summary counts `ready`, `readied`, `merged`, `skipped`, and `failed`.

### `domainjson`

Whois-style, JSON-first name lookup. Prints a single JSON object:

```json
{ "name": "...", "rdap": { ... }, "dns": { "records": {}, "hosts": [], "reverse": [], "axfr": [] } }
```

```sh
domainjson example.com
domainjson --timeout 8000 test.hacker
domainjson -s https://rdap.nic.cz -t domain example.cz   # openrdap args pass through
```

Names ending in a [Moshpit](https://pit.moshcode.sh) TLD skip RDAP and are
served from the registry API under a `moshpit` key instead. Everything else
goes through the OpenRDAP CLI (`rdap`); its flags pass through unchanged,
except the output-format flags (`--text`, `--whois`, `--raw`), which are
dropped — the RDAP section is always JSON. DNS is queried one type at a time
(`A`, `AAAA`, `CNAME`, `MX`, `TXT`, `NS`; never `ANY`), plus reverse PTR for
every resolved address and an AXFR attempt against each nameserver — a
refused transfer is reported, never fatal. If every data source fails, the
exit status is non-zero and the JSON carries an `error` key.

| Flag | Effect |
| --- | --- |
| `--registry URL` | Moshpit registry base URL, default `https://pit.moshcode.sh` |
| `--timeout MS` | per-query timeout for HTTP and dig, default 4000 |
| `--name NAME` | alternative to the positional name argument |

### `provision-ssh-keys`

Authorizes our public keys on a machine, so every box we buy is reachable
without a password. **Dry run by default** — nothing is written until you pass
`--apply`. Idempotent, so it doubles as a drift check on hosts we already own.

```sh
provision-ssh-keys 152.53.47.37                  # report only
provision-ssh-keys --apply 152.53.47.37          # install
provision-ssh-keys --apply --user anthony box    # into a non-root account
```

Every `~/.ssh/*.pub` is installed unless you narrow it with `--key`. Only `.pub`
files are accepted; the script refuses anything else, so a private key cannot be
shipped by a slip of the shell.

**The first key is a chicken-and-egg and this script will not solve it.** A
machine that has never seen one of our keys answers `Permission denied
(publickey,password)`, and nothing here handles passwords. Bootstrap one key
through the provider's own provisioning — netcup SCP, cloud-init, a rescue
console — or interactively, once, with `ssh-copy-id -i ~/.ssh/id_ed25519.pub
root@HOST`. After that this script converges the rest and re-converges later.

**Host keys.** By default an unknown host is refused rather than trusted;
`--accept-new` waives that. Better, pass `--fingerprint` with the value read off
the provider's console and the script verifies before it opens a session,
refusing on mismatch:

```sh
provision-ssh-keys --apply --fingerprint SHA256:AUyILK… 152.53.47.37
```

A reinstalled machine legitimately presents new host keys, so a mismatch means
*go re-read the console*, not necessarily an attack. It is still a stop.

Options:

| Flag | Effect |
| --- | --- |
| `--user USER` | Remote account to install into; default `root` |
| `--port N` | SSH port; default 22 |
| `--key PATH` | Public key to install; repeatable. Default: every `~/.ssh/*.pub` |
| `--fingerprint SHA256:…` | Require the host to present this key; repeatable |
| `--accept-new` | Trust an unknown host key instead of refusing |
| `--apply` | Actually write `authorized_keys` |

### `ssh-logins`

Who actually got in over SSH, and from where. Defaults to today.

```sh
ssh-logins                # today
ssh-logins yesterday      # any journalctl --since expression
ssh-logins -7d
ssh-logins --count        # one row per user+source
ssh-logins --raw          # the original journal lines
```

No `sudo`. Membership in the `adm` group is enough to read the journal, so the
command never stops to authenticate. Scoped to `-u ssh` because a full day is
~15k lines and grepping all of them to find thirty is most of the runtime.

Counts `Accepted` only. Failed and half-finished attempts are thousands a day on
a public box and answer a different question.

### `scripts-upgrade`

Moves this box to the newest release of this repo. See [Upgrading](#upgrading).

### `scripts-check`

The release gate, runnable. Parses every script by shebang, checks that
everything in `bin/` is executable, and runs `shellcheck -S error` over the
shell ones.

```sh
scripts-check           # check the checkout this command lives in
scripts-check --quiet   # only complain
```

`.githooks/pre-push` runs it before every push, wired up by `install.sh` via
`git config core.hooksPath .githooks`. `git push --no-verify` bypasses it.

A missing `shellcheck` is skipped with a note rather than failing — an absent
linter must not be able to block a release.

## `wrappers/`

Snapshots of the launcher scripts that third-party installers drop into
`~/.local/bin`. They are kept here for reference and recovery, not for
installation:

| File | Installed by | Launches |
| --- | --- | --- |
| `coinpay` | `https://coinpayportal.com/install.sh` | `~/.coinpay/pkg/bin/coinpay.js` |
| `moshcode` | `https://moshcoding.com/install.sh` | `~/.moshcode/pkg/bin/moshcode.mjs` |
| `moshscript` | `https://moshcoding.com/install.sh` | `moshcode.mjs run` |
| `logicsrc` | logicsrc CLI | `~/.logicsrc-cli/.../cli/dist/index.js` |

Two reasons they live outside `bin/` and are deliberately **not** symlinked:

- They hardcode absolute `/home/anthony` paths, so they are not portable to
  another machine or user.
- Their installers rewrite `~/.local/bin/<name>` on every update. Symlinking
  would let an installer write through into this repository, producing surprise
  diffs or silently replacing the link.

Re-run the relevant installer to restore or update one; copy from here only if
an installer is unavailable and you need the old contents back.

## Requirements

`gh` (authenticated), `jq`, and `awk`. `provision-ssh-keys` needs only OpenSSH
(`ssh`, `ssh-keyscan`, `ssh-keygen`) locally and `bash` on the remote host.
`domainjson` additionally wants `node`,
`dig`, and the OpenRDAP CLI (`go install github.com/openrdap/rdap/cmd/rdap@latest`,
run from `~/go/bin/rdap` or on `PATH`). `ssh-logins` needs `journalctl` and
membership in a group that can read the journal (`adm` on Ubuntu).

`install.sh` itself needs only POSIX `sh` and `git` — deliberately, since it is
the one file that runs before anything else is installed.
