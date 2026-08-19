# scripts

Hand-written command-line tools. Everything in `bin/` is meant to sit on `PATH`.

## Install

```sh
git clone git@github.com:profullstack/scripts.git ~/scripts
ln -sf ~/scripts/bin/* ~/.local/bin/
```

Symlinking rather than copying keeps `~/.local/bin` and this repo from drifting
apart.

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

### `domainfree`

Bulk domain availability, straight from the registry. Prints only the names you
can actually buy, one per line, so it pipes into anything.

```sh
domainfree sorrycheck.com sinkstate.com
domainfree -f candidates.txt
generate-names | domainfree --jobs 24
domainfree --all example.com          # show TAKEN rows too
```

Availability is read from **RDAP, never inferred from DNS**, because DNS cannot
tell registration apart from configuration:

- A parked domain resolves fine and is taken.
- A registered domain with no nameservers returns `NXDOMAIN` — identical to a
  name nobody owns.

Checked against 8,513 generated candidates, the DNS shortcut (`dig NAME | grep
"ANSWER: 0"`) reported 20 registered domains as free while missing none that
were genuinely free. `oubliette.com` is the instructive one: registered in 1996,
paid through 2034, three nameservers, no `A` record — so `dig` says `ANSWER: 0`
and reads as available. Fine as a cheap prefilter, useless as a buy signal.

Lookups run in parallel (16 by default; 8,500 names take about 45 seconds).
Anything indeterminate — a 429, a 5xx, a timeout — is retried once serially and
then reported as `ERR:<code>`, and the exit status is `2` so an unknown is never
silently read as available.

| Flag | Effect |
| --- | --- |
| `-f, --file FILE` | read names from FILE, one per line (`-` for stdin) |
| `-j, --jobs N` | parallel lookups, default 16 |
| `-t, --timeout S` | per-lookup timeout in seconds, default 20 |
| `-a, --all` | print every name as `STATUS domain`, not just the free ones |
| `-q, --quiet` | suppress the summary, which is written to stderr |

The summary goes to stderr and the names to stdout, so `domainfree -f in.txt |
wc -l` counts what you can buy. For a deep look at one name rather than a
verdict across thousands, use `domainjson`.

Single name, in the shape of the familiar `dig` one-liner:

```sh
curl -sfL -o /dev/null https://rdap.verisign.com/com/v1/domain/NAME && echo "not available"
```

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

`gh` (authenticated), `jq`, and `awk`. `domainfree` needs only `curl`.
`domainjson` additionally wants `node`, `dig`, and the OpenRDAP CLI (`go install github.com/openrdap/rdap/cmd/rdap@latest`,
run from `~/go/bin/rdap` or on `PATH`).
